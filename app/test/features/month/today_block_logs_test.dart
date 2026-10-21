import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/app.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/data/current_user.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/queries/month_queries.dart';
import 'package:milionchik/data/queries/today_queries.dart';
import 'package:milionchik/data/repositories/categories_repository.dart';
import 'package:milionchik/data/repositories/expenses_repository.dart';
import 'package:milionchik/data/repositories/outbox_queue.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:milionchik/features/month/today_block.dart';
import 'package:milionchik/ui/components/expense_row.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';
import '../shell/shell_harness.dart';
import 'month_fixture.dart';

const String _secret = 'Подарок для Ани';

final class _BrokenTodayQueries implements TodayQueries {
  final List<LocalDate> requested = [];

  @override
  Stream<TodayExpenses> watchToday(String budgetId, LocalDate day) {
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

DriftExpensesRepository _expenses(AppDatabase db, DateTime now) =>
    DriftExpensesRepository(
      db,
      currentUser: LocalPrefsCurrentUser(DriftPrefsRepository(db)),
      outbox: DriftOutboxQueue(db),
      now: () => now,
    );

Future<List<Category>> _categories(
  WidgetTester tester,
  AppDatabase db,
  String budgetId,
) async => (await tester.runAsync(
  () => DriftCategoriesRepository(
    db,
    currentUser: LocalPrefsCurrentUser(DriftPrefsRepository(db)),
    outbox: DriftOutboxQueue(db),
  ).watchByBudget(budgetId).first,
))!;

void main() {
  late List<LogRecord> records;
  late StreamSubscription<LogRecord> sub;

  setUp(() {
    records = [];
    Logger.root.level = Level.ALL;
    sub = Logger.root.onRecord.listen(records.add);
  });
  tearDown(() => sub.cancel());

  List<String> todayLines(Level level) => [
    for (final r in records)
      if (r.loggerName == 'month' &&
          r.level == level &&
          r.message.startsWith('today '))
        formatLogRecord(r),
  ];

  List<String> monthDebug(ShellHarness h) => [
    for (final r in h.records)
      if (r.loggerName == 'month' && r.level == Level.FINE) r.message,
  ];

  testWidgets('чистая установка — показ пустого состояния в debug-логе '
      '[month] с датой и причиной «нет бюджета»', (tester) async {
    final h = await ShellHarness.start(tester);

    expect(
      monthDebug(h),
      contains(
        'today block empty state shown date=2026-10-19 without budget: no '
        'budget selected, first expense hint and button',
      ),
    );
    final line = todayLines(Level.FINE)
        .firstWhere((l) => l.contains('today block empty state shown'));
    expect(line, contains('DEBUG [month] today block empty state shown'));
    expect(todayLines(Level.WARNING), isEmpty);
    expect(todayLines(Level.SEVERE), isEmpty);
  });

  testWidgets('бюджет без трат — debug [month] с budgetId и временем, первая '
      'трата — «empty state left»', (tester) async {
    final db = openTestDatabase();
    final budget = (await tester.runAsync(
      () => testBudgets(db).createLocalPersonal(),
    ))!;
    final categories = await _categories(tester, db, budget.id);
    final h = await ShellHarness.start(tester, db: db);

    await tester.runAsync(
      () => _expenses(db, DateTime(2026, 10, 19, 9, 5)).create(
        budgetId: budget.id,
        categoryId: categories.first.id,
        amount: const Money.rubles(120),
        spentOn: LocalDate(2026, 10, 19),
        comment: _secret,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      monthDebug(h),
      containsAllInOrder([
        matches(
          '^today block empty state shown date=2026-10-19 '
          'budgetId=${budget.id}: no expenses in budget yet, first expense '
          r'hint and button in \d+ms$',
        ),
        'today block updated date=2026-10-19 budgetId=${budget.id} '
            'expenses=0 → 1, empty state left: budget has expenses',
      ]),
    );
    for (final r in h.records.where((r) => r.loggerName == 'month')) {
      expect(r.message, isNot(contains(_secret)));
      expect(
        r.message
            .replaceAll(budget.id, '<budget>')
            .replaceAll(RegExp(r'\d+ms'), '<ms>'),
        isNot(contains('120')),
      );
      expect(r.message, isNot(contains('₽')));
    }
  });

  testWidgets('блок с тратами, сентябрь и обратно, тап по трате — debug '
      '[month]; сумм, комментариев и названий категорий в логах нет', (
    tester,
  ) async {
    final db = openTestDatabase();
    final budgetId = (await tester.runAsync(() => seedMockupOctober(db)))!;
    final expenses = (await tester.runAsync(
      () =>
          DriftMonthQueries(db)
              .watchDayExpenses(budgetId, LocalDate(2026, 10, 19))
              .first,
    ))!;
    final pyaterochka = expenses.singleWhere((e) => e.comment == 'Пятёрочка');
    final h = await ShellHarness.start(tester, db: db);

    await tester.tap(find.bySemanticsLabel('Предыдущий месяц'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Следующий месяц'));
    await tester.pumpAndSettle();
    final row = find.descendant(
      of: find.byType(TodayBlock),
      matching: find.byType(ExpenseRow),
    );
    await tester.ensureVisible(row.first);
    await tester.pumpAndSettle();
    await tester.tap(row.first);
    await tester.pumpAndSettle();

    expect(
      monthDebug(h),
      containsAllInOrder([
        matches(
          '^today block shown date=2026-10-19 budgetId=$budgetId expenses=3 '
          r'withTime=3 in \d+ms$',
        ),
        'today block hidden month=2026-09: not the current month 2026-10',
        'today block shown again month=2026-10: current month',
        matches(
          '^today block shown date=2026-10-19 budgetId=$budgetId expenses=3 '
          r'withTime=3 in \d+ms$',
        ),
        'today expense tap id=${pyaterochka.id} date=2026-10-19 → '
            '/expense/:id',
      ]),
    );
    expect(todayLines(Level.WARNING), isEmpty);
    expect(todayLines(Level.SEVERE), isEmpty);
    final ids = {for (final e in expenses) e.id};
    for (final r in h.records.where((r) => r.loggerName == 'month')) {
      var message = r.message
          .replaceAll(budgetId, '<budget>')
          .replaceAll(RegExp(r'\d+ms'), '<ms>');
      for (final id in ids) {
        message = message.replaceAll(id, '<expense>');
      }
      expect(message, isNot(contains('₽')));
      for (final secret in [
        '1100',
        '1 100',
        '640',
        '250',
        '210',
        'Пятёрочка',
        'Метро',
        'Кофе',
        'Продукты',
        'Транспорт',
        'Кафе',
      ]) {
        expect(message, isNot(contains(secret)));
      }
    }
  });

  testWidgets('категория траты не найдена — warn [month] с id траты и '
      'категории, без комментария', (tester) async {
    final db = openTestDatabase();
    final budgetId = (await tester.runAsync(() => seedMockupOctober(db)))!;
    final categories = await _categories(tester, db, budgetId);
    final other = categories.singleWhere((c) => c.isSystem);
    await tester.runAsync(
      () => _expenses(db, DateTime(2026, 10, 19, 21)).applyFromServer([
        Expense(
          id: 'e-orphan',
          budgetId: budgetId,
          categoryId: 'deleted-category',
          amount: Money.rubles(70),
          spentOn: LocalDate(2026, 10, 19),
          comment: _secret,
          authorId: 'u-1',
          createdAt: DateTime(2026, 10, 19, 21),
          updatedAt: DateTime(2026, 10, 19, 21),
          updatedBy: 'u-1',
        ),
      ]),
    );
    final h = await ShellHarness.start(tester, db: db);
    await tester.pumpAndSettle();

    final warnings = [
      for (final r in h.records)
        if (r.loggerName == 'month' && r.level == Level.WARNING) r.message,
    ];
    expect(warnings, [
      'today block expense id=e-orphan category=deleted-category not found '
          'among 11 categories of budgetId=$budgetId, showing it as system '
          'category ${other.id}',
    ]);
    expect(warnings.single, isNot(contains(_secret)));
  });

  testWidgets('траты сегодня не прочитались — error [month] с бюджетом и '
      'датой, тип, код, SQL и стек, параметры только типами; блок с «—» без '
      'списка', (tester) async {
    final db = openTestDatabase();
    final budgetId = (await tester.runAsync(() => seedMockupOctober(db)))!;
    final broken = _BrokenTodayQueries();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(Clock(now: () => testNow)),
          todayQueriesProvider.overrideWithValue(broken),
        ],
        child: MilionchikApp(today: LocalDate(2026, 10, 19)),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final block = find.byType(TodayBlock);
    Finder inBlock(Finder f) => find.descendant(of: block, matching: f);
    expect(inBlock(find.text('Сегодня, 19 октября')), findsOneWidget);
    expect(inBlock(find.text('—')), findsOneWidget);
    expect(inBlock(find.byType(ExpenseRow)), findsNothing);
    expect(inBlock(find.text('👋')), findsNothing);

    final errors = todayLines(Level.SEVERE);
    expect(errors, hasLength(1));
    final line = errors.single;
    expect(
      line,
      contains(
        'ERROR [month] today block data failed budgetId=$budgetId '
        'date=2026-10-19: today expenses stream failed, showing «—» without '
        'list: SqliteException',
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
    expect(broken.requested, [LocalDate(2026, 10, 19)]);

    for (final r in records) {
      expect(formatLogRecord(r), isNot(contains(_secret)));
      expect('${r.error}', isNot(contains(_secret)));
    }
  });
}
