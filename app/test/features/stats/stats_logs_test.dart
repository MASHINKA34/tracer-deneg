import 'dart:async';

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
import 'package:milionchik/features/stats/donut_chart.dart';
import 'package:milionchik/features/stats/stats_screen.dart';
import 'package:milionchik/ui/components/bottom_nav.dart';
import 'package:milionchik/ui/components/chip.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';
import '../../support/test_fonts.dart';
import '../month/month_fixture.dart';
import '../shell/shell_harness.dart';
import 'stats_fixture.dart';

const String _secret = 'Подарок для Ани';

final class _BrokenStatsQueries implements StatsQueries {
  final List<String> requested = [];

  @override
  Stream<List<CategoryTotal>> watchCategoryTotals(
    String budgetId, {
    required LocalDate from,
    required LocalDate to,
  }) {
    requested.add('$from..$to');
    return Stream.error(
      SqliteException(
        extendedResultCode: 11,
        message: 'database disk image is malformed',
        causingStatement:
            'SELECT category_id, SUM(amount_kopecks) FROM expenses '
            'WHERE budget_id = ? AND comment = ?',
        parametersToStatement: [budgetId, _secret],
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

List<String> _stats(Iterable<LogRecord> records, Level level) => [
  for (final r in records)
    if (r.loggerName == 'stats' && r.level == level) r.message,
];

void main() {
  testWidgets('открытие, выбор сентября и новая трата — debug [stats]: '
      'период, бюджет, сколько категорий и трат, мс; сумм и комментариев '
      'в логах нет', (tester) async {
    await loadTestFonts();
    final db = openTestDatabase();
    final budgetId = (await tester.runAsync(() => seedMockupOctober(db)))!;
    final h = await ShellHarness.start(tester, db: db);
    await openStatsTab(h);

    await tester.tap(
      find.descendant(
        of: find.byType(StatsScreen),
        matching: find.byType(AppChip),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Сентябрь 2026'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Открыть сентябрь'));
    await tester.pumpAndSettle();

    final ids = (await tester.runAsync(() => db.select(db.categories).get()))!;
    await tester.runAsync(
      () =>
          DriftExpensesRepository(
            db,
            currentUser: LocalPrefsCurrentUser(DriftPrefsRepository(db)),
            outbox: DriftOutboxQueue(db),
          ).create(
            budgetId: budgetId,
            categoryId: ids.firstWhere((c) => c.name == 'Одежда').id,
            amount: Money.rubles(_secret.length * 100),
            spentOn: LocalDate(2026, 9, 3),
            comment: _secret,
          ),
    );
    await tester.pumpAndSettle();

    expect(
      _stats(h.records, Level.FINE),
      containsAllInOrder([
        'stats month=2026-10 (current) today=2026-10-19',
        'stats screen opened month=2026-10 today=2026-10-19',
        matches(
          '^stats month built period=2026-10-01\\.\\.2026-10-31 '
          'budgetId=$budgetId categories=7 expenses=43 comparison=shown '
          'in \\d+ms\$',
        ),
        'stats period chip tap month=2026-10 → month picker',
        'stats month 2026-10 → 2026-09 by=picker',
        matches(
          '^stats month built period=2026-09-01\\.\\.2026-09-30 '
          'budgetId=$budgetId categories=10 expenses=32 comparison=shown '
          'in \\d+ms\$',
        ),
        'stats month updated period=2026-09-01..2026-09-30 '
            'budgetId=$budgetId categories=10 → 10 expenses=32 → 33',
      ]),
    );
    expect(_stats(h.records, Level.SEVERE), isEmpty);
    expect(_stats(h.records, Level.WARNING), isEmpty);
    expect(_stats(h.records, Level.INFO), isEmpty);
    for (final r in h.records.where((r) => r.loggerName == 'stats')) {
      final message = r.message.replaceAll(budgetId, '<budget>');
      expect(message, isNot(contains('₽')));
      expect(message, isNot(contains(_secret)));
      for (final amount in ['18300', '6240', '3180', '963', '2100', '1500']) {
        expect(message, isNot(contains(amount)));
      }
    }
  });

  testWidgets('итоги категорий не прочитались — error [stats] с месяцем, '
      'бюджетом и потоком, тип, код, SQL и стек, параметры только типами; '
      'на экране текст ошибки, чип периода работает', (tester) async {
    await loadTestFonts();
    final records = <LogRecord>[];
    Logger.root.level = Level.ALL;
    final sub = Logger.root.onRecord.listen(records.add);
    addTearDown(sub.cancel);
    final db = openTestDatabase();
    final budget = (await tester.runAsync(() => seedStatsBudget(db)))!;
    final broken = _BrokenStatsQueries();

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

    expect(tester.takeException(), isNull);
    expect(find.byType(DonutChart), findsNothing);
    expect(
      find.text(
        'Не удалось посчитать статистику. Выбери другой месяц или открой '
        'вкладку позже.',
      ),
      findsOneWidget,
    );
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
        'ERROR \\[stats\\] stats month failed month=2026-10 '
        'budgetId=${budget.id}: category totals stream failed after \\d+ms, '
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
    expect(broken.requested, ['2026-10-01..2026-10-31']);
    for (final r in records) {
      expect(formatLogRecord(r), isNot(contains(_secret)));
      expect('${r.error}', isNot(contains(_secret)));
    }

    await tester.tap(
      find.descendant(
        of: find.byType(StatsScreen),
        matching: find.byType(AppChip),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Открыть октябрь'), findsOneWidget);
  });
}
