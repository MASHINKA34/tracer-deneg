import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/app.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/queries/stats_queries.dart';
import 'package:milionchik/features/month/month_picker_sheet.dart';
import 'package:milionchik/ui/components/month_tab.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';
import '../shell/shell_harness.dart';
import 'month_picker_fixture.dart';

const String _secret = 'Подарок для Ани';

final class _BrokenStatsQueries implements StatsQueries {
  final List<int> requested = [];

  @override
  Stream<List<Money>> watchMonthTotals(String budgetId, int year) {
    requested.add(year);
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

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  late List<LogRecord> records;
  late StreamSubscription<LogRecord> sub;

  setUp(() {
    records = [];
    Logger.root.level = Level.ALL;
    sub = Logger.root.onRecord.listen(records.add);
  });
  tearDown(() => sub.cancel());

  List<String> pickerLines(Level level) => [
    for (final r in records)
      if (r.loggerName == 'month' &&
          r.level == level &&
          r.message.startsWith('month picker'))
        formatLogRecord(r),
  ];

  testWidgets('открытие, год, месяц, «Открыть» и закрытие — debug [month] с '
      'месяцами, отрезками сравнения и номером самого дорогого месяца; сумм '
      'в логах нет', (tester) async {
    final db = openTestDatabase();
    final budgetId = (await tester.runAsync(() => seedMockupYear(db)))!;
    final h = await ShellHarness.start(tester, db: db);

    await tester.tap(find.bySemanticsLabel('Октябрь 2026, выбрать месяц'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Предыдущий год'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Следующий год'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Сентябрь 2026'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Открыть сентябрь'));
    await tester.pumpAndSettle();

    final debug = [
      for (final r in h.records)
        if (r.loggerName == 'month' && r.level == Level.FINE) r.message,
    ];
    expect(
      debug,
      containsAllInOrder([
        'month title tap month=2026-10 → month picker',
        'month picker opened shown=2026-10',
        'month picker year=2026 selected=2026-10, compare '
            '2026-10-01..2026-10-19 with 2026-09-01..2026-09-19',
        'month picker year data budgetId=$budgetId year=2026 '
            'monthsWithSpending=10 priciest=7',
        'month picker year 2026 → 2025 by=arrow selected=2025-10, compare '
            '2025-10-01..2025-10-31 with 2025-09-01..2025-09-30',
        'month picker year data budgetId=$budgetId year=2025 '
            'monthsWithSpending=0 priciest=-',
        'month picker year 2025 → 2026 by=arrow selected=2026-10, compare '
            '2026-10-01..2026-10-19 with 2026-09-01..2026-09-19',
        'month picker selected 2026-10 → 2026-09 by=tab, compare '
            '2026-09-01..2026-09-30 with 2026-08-01..2026-08-31',
        'month picker open button month=2026-09',
        matches(r'^month picker closed: open 2026-09 after \d+ms$'),
        'month 2026-10 → 2026-09 by=picker',
      ]),
    );
    expect(pickerLines(Level.SEVERE), isEmpty);
    expect(pickerLines(Level.WARNING), isEmpty);
    for (final r in h.records.where((r) => r.loggerName == 'month')) {
      final message = r.message.replaceAll(budgetId, '<budget>');
      expect(message, isNot(contains('₽')));
      for (final amount in ['18300', '24300', '20400', '2100', '963']) {
        expect(message, isNot(contains(amount)));
      }
    }
  });

  testWidgets('итоги года не прочитались — error [month] с бюджетом, годом и '
      'месяцем, тип, код, SQL и стек, параметры только типами; шторка без '
      'сумм, «Открыть» работает', (tester) async {
    final db = openTestDatabase();
    final budgetId = (await tester.runAsync(() => seedMockupYear(db)))!;
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
    await tester.tap(find.bySemanticsLabel('Октябрь 2026, выбрать месяц'));
    await tester.pumpAndSettle();

    expect(find.byType(MonthPicker), findsOneWidget);
    expect(tester.takeException(), isNull);
    final tabs = tester.widgetList<MonthTab>(find.byType(MonthTab));
    expect(tabs.map((t) => t.fraction), List<double>.filled(12, 0));
    expect(
      find.descendant(
        of: find.byType(MonthPicker),
        matching: find.text('0$nbsp₽'),
      ),
      findsOneWidget,
    );

    final errors = pickerLines(Level.SEVERE);
    expect(errors, hasLength(1));
    final line = errors.single;
    expect(
      line,
      contains(
        'ERROR [month] month picker data failed budgetId=$budgetId '
        'year=2026 selected=2026-10: year totals stream failed, showing '
        'picker without sums: SqliteException',
      ),
    );
    expect(line, contains('database disk image is malformed'));
    expect(line, contains('WHERE budget_id = ? AND comment = ?'));
    expect(
      line,
      contains('<text:${budgetId.length}>, <text:${_secret.length}>'),
    );
    expect(line, contains('stack:'));
    expect(broken.requested, [2026]);

    await tester.tap(find.text('Открыть октябрь'));
    await tester.pumpAndSettle();
    expect(find.byType(MonthPicker), findsNothing);

    for (final r in records) {
      expect(formatLogRecord(r), isNot(contains(_secret)));
      expect('${r.error}', isNot(contains(_secret)));
    }
  });
}
