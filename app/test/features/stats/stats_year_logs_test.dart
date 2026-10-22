import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/app.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/data/current_user.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/queries/stats_queries.dart';
import 'package:milionchik/data/repositories/expenses_repository.dart';
import 'package:milionchik/data/repositories/outbox_queue.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:milionchik/features/stats/stats_screen.dart';
import 'package:milionchik/features/stats/year_chart.dart';
import 'package:milionchik/ui/components/bottom_nav.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';
import '../../support/test_fonts.dart';
import '../shell/shell_harness.dart';
import 'stats_fixture.dart';
import 'stats_year_fixture.dart';

const String _secret = 'Подарок для Ани';

const int _idle = 600;

final class _BrokenYearQueries implements StatsQueries {
  _BrokenYearQueries(this._real);

  final StatsQueries _real;
  final List<String> requested = [];

  @override
  Stream<List<CategoryTotal>> watchCategoryTotals(
    String budgetId, {
    required LocalDate from,
    required LocalDate to,
  }) => _real.watchCategoryTotals(budgetId, from: from, to: to);

  @override
  Stream<List<Money>> watchMonthTotals(String budgetId, int year) {
    requested.add('$year');
    return Stream.error(
      SqliteException(
        extendedResultCode: 11,
        message: 'database disk image is malformed',
        causingStatement:
            'SELECT substr(spent_on, 1, 7), SUM(amount_kopecks) FROM expenses '
            'WHERE budget_id = ? AND comment = ?',
        parametersToStatement: [budgetId, _secret],
      ),
    );
  }
}

List<String> _stats(Iterable<LogRecord> records, Level level) => [
  for (final r in records)
    if (r.loggerName == 'stats' && r.level == level) r.message,
];

void main() {
  testWidgets('год: открытие, ‹ на пустой 2025, новая трата, › и тап по '
      'сентябрю — debug [stats] с годом, бюджетом, числом месяцев, категорий '
      'и трат и мс (отсчёт с нажатия ‹, а не с открытия года); сумм и '
      'комментариев в логах нет', (tester) async {
    await loadTestFonts();
    final db = openTestDatabase();
    final budget = (await tester.runAsync(() => seedMockupYear(db)))!;
    final id = budget.id;
    final h = await ShellHarness.start(tester, db: db);
    await openStatsTab(h);

    await tester.tap(
      find.descendant(of: find.byType(StatsScreen), matching: find.text('Год')),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: _idle)),
    );
    await tester.tap(find.bySemanticsLabel('Предыдущий год'));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () =>
          DriftExpensesRepository(
            db,
            currentUser: LocalPrefsCurrentUser(DriftPrefsRepository(db)),
            outbox: DriftOutboxQueue(db),
          ).create(
            budgetId: id,
            categoryId: budget.categoryIds['Одежда']!,
            amount: Money.rubles(_secret.length * 100),
            spentOn: LocalDate(2025, 9, 3),
            comment: _secret,
          ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Следующий год'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is YearChartColumn && w.month.month == 9,
        ),
        matching: find.text('С'),
      ),
    );
    await tester.pumpAndSettle();

    final debug = _stats(h.records, Level.FINE);
    expect(
      debug,
      containsAllInOrder([
        'stats mode month → year by=segmented month=2026-10, '
            'opening its year 2026',
        'stats year=2026 (current) today=2026-10-19',
        'stats year open 2026 by=mode: already shown',
        matches(
          '^stats year built year=2026 budgetId=$id monthsWithSpending=10 '
          'priciest=7 categories=9 expenses=697 in \\d+ms\$',
        ),
        'stats year 2026 → 2025 by=arrow',
        matches(
          '^stats year built year=2025 budgetId=$id monthsWithSpending=0 '
          'priciest=- categories=0 expenses=0: no expenses, empty state '
          'in \\d+ms\$',
        ),
        matches(
          '^stats year updated year=2025 budgetId=$id '
          'monthsWithSpending=[01] → 1 categories=[01] → 1 '
          'expenses=[01] → 1\$',
        ),
        'stats year 2025 → 2026 by=arrow',
        matches('^stats year built year=2026 budgetId=$id .* in \\d+ms\$'),
        'stats year bar tap month=2026-09 → month mode',
        'stats month 2026-10 → 2026-09 by=year-bar',
      ]),
    );
    final built2025 = RegExp(r'^stats year built year=2025 .* in (\d+)ms$')
        .firstMatch(
          debug.firstWhere((m) => m.startsWith('stats year built year=2025')),
        );
    expect(int.parse(built2025!.group(1)!), lessThan(_idle));
    expect(_stats(h.records, Level.SEVERE), isEmpty);
    expect(_stats(h.records, Level.WARNING), isEmpty);
    expect(_stats(h.records, Level.INFO), isEmpty);
    for (final r in h.records.where((r) => r.loggerName == 'stats')) {
      final message = r.message.replaceAll(id, '<budget>');
      expect(message, isNot(contains('₽')));
      expect(message, isNot(contains(_secret)));
      for (final amount in [
        '211350',
        '21135',
        '24300',
        '72400',
        '24,3',
        '1500',
      ]) {
        expect(message, isNot(contains(amount)));
      }
    }
  });

  testWidgets('итоги месяцев года не прочитались — error [stats] с годом, '
      'бюджетом и потоком, тип, код, SQL и стек, параметры только типами; '
      'на экране текст ошибки года, стрелка года работает', (tester) async {
    await loadTestFonts();
    final records = <LogRecord>[];
    Logger.root.level = Level.ALL;
    final sub = Logger.root.onRecord.listen(records.add);
    addTearDown(sub.cancel);
    final db = openTestDatabase();
    final budget = (await tester.runAsync(() => seedStatsBudget(db)))!;
    final broken = _BrokenYearQueries(DriftStatsQueries(db));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(Clock(now: () => testNow)),
          statsQueriesProvider.overrideWithValue(broken),
        ],
        child: MilionchikApp(today: LocalDate(2026, 10, 19)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AppBottomNav),
        matching: find.text('Статистика'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(StatsScreen), matching: find.text('Год')),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(YearChart), findsNothing);
    const failed =
        'Не удалось посчитать статистику за год. Выбери другой год или '
        'открой вкладку позже.';
    expect(find.text(failed), findsOneWidget);
    final errors = [
      for (final r in records)
        if (r.loggerName == 'stats' && r.level == Level.SEVERE)
          formatLogRecord(r),
    ];
    expect(errors, hasLength(1));
    final line = errors.single;
    expect(
      line,
      matches(
        'ERROR \\[stats\\] stats year failed year=2026 '
        'budgetId=${budget.id}: month totals stream failed after \\d+ms, '
        'showing error text: SqliteException',
      ),
    );
    expect(line, contains('database disk image is malformed'));
    expect(line, contains('WHERE budget_id = ? AND comment = ?'));
    expect(
      line,
      contains('<text:${budget.id.length}>, <text:${_secret.length}>'),
    );
    expect(line, contains('stack:'));

    await tester.tap(find.bySemanticsLabel('Предыдущий год'));
    await tester.pumpAndSettle();
    expect(find.text(failed), findsOneWidget);
    expect(
      [
        for (final r in records)
          if (r.loggerName == 'stats' && r.level == Level.SEVERE) r.message,
      ].last,
      startsWith(
        'stats year failed year=2025 budgetId=${budget.id}: '
        'month totals stream failed',
      ),
    );
    expect(broken.requested, ['2026', '2025']);
    for (final r in records) {
      expect(formatLogRecord(r), isNot(contains(_secret)));
      expect('${r.error}', isNot(contains(_secret)));
    }
  });
}
