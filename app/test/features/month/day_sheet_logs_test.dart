import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/app.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/queries/month_queries.dart';
import 'package:milionchik/features/month/day_sheet.dart';
import 'package:milionchik/features/shell/new_expense_stub_screen.dart';
import 'package:milionchik/ui/components/expense_row.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';
import '../shell/shell_harness.dart';
import 'month_fixture.dart';

const String _secret = 'Подарок для Ани';

final class _BrokenDayQueries implements MonthQueries {
  _BrokenDayQueries(this._inner);

  final MonthQueries _inner;
  final List<LocalDate> requested = [];

  @override
  Stream<Map<int, Money>> watchDayTotals(String budgetId, YearMonth month) =>
      _inner.watchDayTotals(budgetId, month);

  @override
  Stream<Money> watchMonthTotal(String budgetId, YearMonth month) =>
      _inner.watchMonthTotal(budgetId, month);

  @override
  Stream<List<Expense>> watchDayExpenses(String budgetId, LocalDate day) {
    requested.add(day);
    return Stream.error(
      SqliteException(
        extendedResultCode: 11,
        message: 'database disk image is malformed',
        causingStatement:
            'SELECT * FROM expenses WHERE budget_id = ? AND spent_on = ? '
            'AND comment = ?',
        parametersToStatement: [budgetId, '$day', _secret],
      ),
    );
  }
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

  List<String> sheetLines(Level level) => [
    for (final r in records)
      if (r.loggerName == 'month' &&
          r.level == level &&
          r.message.startsWith('day sheet'))
        formatLogRecord(r),
  ];

  testWidgets('тап по дню, открытие с датой и числом трат, тап по трате, '
      '«Добавить» и закрытие — debug [month]; сумм, комментариев и названий '
      'в логах нет', (tester) async {
    final db = openTestDatabase();
    final budgetId = (await tester.runAsync(() => seedMockupOctober(db)))!;
    final expenses = (await tester.runAsync(
      () =>
          DriftMonthQueries(db)
              .watchDayExpenses(budgetId, LocalDate(2026, 10, 17))
              .first,
    ))!;
    final h = await ShellHarness.start(tester, db: db);

    await tester.tap(find.bySemanticsLabel(RegExp('^17 октября')));
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .descendant(
            of: find.byType(DaySheet),
            matching: find.byType(ExpenseRow),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await h.systemBack();
    await tester.tap(find.text('Добавить трату в этот день'));
    await tester.pumpAndSettle();
    expect(find.byType(NewExpenseStubScreen), findsOneWidget);
    await h.systemBack();
    await h.systemBack();
    expect(find.byType(DaySheet), findsNothing);

    final debug = [
      for (final r in h.records)
        if ((r.loggerName == 'month' || r.loggerName == 'nav') &&
            r.level == Level.FINE)
          r.message,
    ];
    expect(
      debug,
      containsAllInOrder([
        'day tap date=2026-10-17 → day sheet',
        matches(
          '^day sheet opened date=2026-10-17 budgetId=$budgetId expenses=2 '
          r'withTime=2 in \d+ms$',
        ),
        'day sheet expense tap id=${expenses.first.id} date=2026-10-17 → '
            '/expense/:id',
        'expense opened id=${expenses.first.id}: stub screen, editing is not '
            'available yet',
        'expense closed id=${expenses.first.id} by back',
        'day sheet add expense date=2026-10-17 → /expense/new with '
            'date=2026-10-17',
        'new expense closed by back',
        matches(
          r'^day sheet closed date=2026-10-17 after \d+ms: back gesture, tap '
          r'outside or swipe down$',
        ),
      ]),
    );
    final opened = h.records.firstWhere(
      (r) => r.message.startsWith('day sheet opened'),
    );
    expect(
      formatLogRecord(opened),
      contains('DEBUG [month] day sheet opened date=2026-10-17'),
    );
    expect(sheetLines(Level.SEVERE), isEmpty);
    expect(sheetLines(Level.WARNING), isEmpty);
    for (final r in h.records.where((r) => r.loggerName == 'month')) {
      final message = r.message
          .replaceAll(budgetId, '<budget>')
          .replaceAll(expenses.first.id, '<expense>');
      expect(message, isNot(contains('₽')));
      for (final secret in [
        '1450',
        '890',
        '560',
        '487',
        'Обед с коллегами',
        'ВкусВилл',
        'Кафе',
        'Продукты',
      ]) {
        expect(message, isNot(contains(secret)));
      }
    }
  });

  testWidgets('траты дня не прочитались — error [month] с бюджетом и датой, '
      'тип, код, SQL и стек, параметры только типами; шторка с «—» без '
      'списка, «Добавить» работает', (tester) async {
    final db = openTestDatabase();
    final budgetId = (await tester.runAsync(() => seedMockupOctober(db)))!;
    final broken = _BrokenDayQueries(DriftMonthQueries(db));

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
    await tester.tap(find.bySemanticsLabel(RegExp('^17 октября')));
    await tester.pumpAndSettle();

    final sheet = find.byType(DaySheet);
    expect(sheet, findsOneWidget);
    expect(tester.takeException(), isNull);
    Finder inSheet(Finder f) => find.descendant(of: sheet, matching: f);
    expect(inSheet(find.text('Суббота, 17 октября')), findsOneWidget);
    expect(inSheet(find.text('—')), findsOneWidget);
    expect(inSheet(find.byType(ExpenseRow)), findsNothing);
    expect(inSheet(find.textContaining(RegExp(r'^\d+ трат'))), findsNothing);

    final errors = sheetLines(Level.SEVERE);
    expect(errors, hasLength(1));
    final line = errors.single;
    expect(
      line,
      contains(
        'ERROR [month] day sheet data failed budgetId=$budgetId '
        'date=2026-10-17: day expenses stream failed: SqliteException',
      ),
    );
    expect(line, contains('database disk image is malformed'));
    expect(line, contains('WHERE budget_id = ? AND spent_on = ? AND comment'));
    expect(
      line,
      contains(
        '<text:${budgetId.length}>, <text:10>, <text:${_secret.length}>',
      ),
    );
    expect(line, contains('stack:'));
    expect(broken.requested, [LocalDate(2026, 10, 17)]);

    await tester.tap(inSheet(find.text('Добавить трату в этот день')));
    await tester.pumpAndSettle();
    expect(find.byType(NewExpenseStubScreen), findsOneWidget);

    for (final r in records) {
      expect(formatLogRecord(r), isNot(contains(_secret)));
      expect('${r.error}', isNot(contains(_secret)));
    }
  });
}
