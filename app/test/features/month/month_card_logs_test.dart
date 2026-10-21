import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/app.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/queries/month_queries.dart';
import 'package:milionchik/ui/components/month_card.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';
import '../shell/shell_harness.dart';
import 'month_fixture.dart';

const String _secret = 'Подарок для Ани';

final class _BrokenMonthQueries implements MonthQueries {
  final List<YearMonth> requested = [];

  @override
  Stream<Map<int, Money>> watchDayTotals(String budgetId, YearMonth month) {
    requested.add(month);
    return Stream.error(
      SqliteException(
        extendedResultCode: 11,
        message: 'database disk image is malformed',
        causingStatement:
            'SELECT spent_on, SUM(amount_kopecks) FROM expenses '
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

  List<String> monthLines(Level level) => [
    for (final r in records)
      if (r.loggerName == 'month' && r.level == level) formatLogRecord(r),
  ];

  testWidgets('открытие и смена месяца — debug [month] с budgetId, месяцем, '
      'числом дней с тратами и временем построения данных; сумм в логах нет', (
    tester,
  ) async {
    final db = openTestDatabase();
    final budgetId = (await tester.runAsync(() => seedMockupOctober(db)))!;
    final h = await ShellHarness.start(tester, db: db);
    await tester.tap(find.bySemanticsLabel('Предыдущий месяц'));
    await tester.pumpAndSettle();

    final debug = [
      for (final r in h.records)
        if (r.loggerName == 'month' && r.level == Level.FINE) r.message,
    ];
    expect(
      debug,
      containsAllInOrder([
        'month screen opened month=2026-10 today=2026-10-19',
        matches(
          RegExp(
            '^month shown budgetId=$budgetId month=2026-10 '
            r'daysWithSpending=17 data built in \d+ms$',
          ),
        ),
        'month 2026-10 → 2026-09 by=arrow',
        matches(
          RegExp(
            '^month shown budgetId=$budgetId month=2026-09 '
            r'daysWithSpending=\d+ data built in \d+ms$',
          ),
        ),
      ]),
    );
    for (final r in h.records.where((r) => r.loggerName == 'month')) {
      expect(r.message, isNot(contains('₽')));
      expect(r.message, isNot(contains('18300')));
      expect(r.message, isNot(contains('1830000')));
    }
  });

  testWidgets('поток сумм упал — error [month] с бюджетом и месяцем, тип, '
      'код, SQL и стек, параметры только типами; карточка без сумм, стрелки '
      'листают', (tester) async {
    final db = openTestDatabase();
    final budget = await testBudgets(db).createLocalPersonal();
    final broken = _BrokenMonthQueries();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(Clock(now: () => testNow)),
          monthQueriesProvider.overrideWithValue(broken),
        ],
        child: MilionchikApp(today: LocalDate(2026, 10, 19)),
      ),
    );
    await tester.pumpAndSettle();

    final card = tester.widget<MonthCard>(find.byType(MonthCard));
    expect(card.month, YearMonth(2026, 10));
    expect(card.dayTotals, isEmpty);
    expect(tester.takeException(), isNull);

    final errors = monthLines(Level.SEVERE);
    expect(errors, hasLength(1));
    final line = errors.single;
    expect(
      line,
      contains(
        'ERROR [month] month data failed budgetId=${budget.id} '
        'month=2026-10: day totals stream failed after ',
      ),
    );
    expect(line, contains('showing card without sums: SqliteException'));
    expect(line, contains('database disk image is malformed'));
    expect(line, contains('WHERE budget_id = ? AND comment = ?'));
    expect(
      line,
      contains('<text:${budget.id.length}>, <text:${_secret.length}>'),
    );
    expect(line, contains('stack:'));

    await tester.tap(find.bySemanticsLabel('Предыдущий месяц'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<MonthCard>(find.byType(MonthCard)).month,
      YearMonth(2026, 9),
    );
    expect(broken.requested, [YearMonth(2026, 10), YearMonth(2026, 9)]);
    expect(monthLines(Level.SEVERE), hasLength(2));
    expect(monthLines(Level.SEVERE).last, contains('month=2026-09'));

    for (final r in records) {
      expect(formatLogRecord(r), isNot(contains(_secret)));
      expect('${r.error}', isNot(contains(_secret)));
    }
  });
}
