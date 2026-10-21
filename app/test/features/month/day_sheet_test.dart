import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/current_user.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/queries/month_queries.dart';
import 'package:milionchik/data/repositories/categories_repository.dart';
import 'package:milionchik/data/repositories/expenses_repository.dart';
import 'package:milionchik/data/repositories/outbox_queue.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:milionchik/features/month/day_sheet.dart';
import 'package:milionchik/features/shell/expense_stub_screen.dart';
import 'package:milionchik/features/shell/new_expense_stub_screen.dart';
import 'package:milionchik/ui/components/bottom_nav.dart';
import 'package:milionchik/ui/components/button.dart';
import 'package:milionchik/ui/components/expense_row.dart';
import 'package:milionchik/ui/components/month_card.dart';
import 'package:milionchik/ui/components/sheet.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';
import '../shell/shell_harness.dart';
import 'month_fixture.dart';

String _rub(String digits) => '${digits.replaceAll(' ', nbsp)}$nbsp₽';

Finder get _sheet => find.byType(DaySheet);

Finder _inSheet(Finder finder) => find.descendant(of: _sheet, matching: finder);

Finder _sheetText(String text) => _inSheet(find.text(text));

List<ExpenseRow> _rows(WidgetTester tester) =>
    tester.widgetList<ExpenseRow>(_inSheet(find.byType(ExpenseRow))).toList();

MonthCard _card(WidgetTester tester) =>
    tester.widget<MonthCard>(find.byType(MonthCard));

String _location(WidgetTester tester) =>
    GoRouter.of(tester.element(find.byType(AppBottomNav, skipOffstage: false)))
        .state
        .uri
        .toString();

Iterable<String> _monthDebug(ShellHarness h) => h.records
    .where((r) => r.loggerName == 'month' && r.level == Level.FINE)
    .map((r) => r.message);

Future<void> _openDay(WidgetTester tester, String date) async {
  await tester.tap(find.bySemanticsLabel(RegExp('^$date')));
  await tester.pumpAndSettle();
}

Future<String> _seedOctober(WidgetTester tester, AppDatabase db) async =>
    (await tester.runAsync(() => seedMockupOctober(db)))!;

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

Future<Expense> _addExpense(
  WidgetTester tester,
  AppDatabase db, {
  required String budgetId,
  required String categoryId,
  required LocalDate spentOn,
  required DateTime createdAt,
  required int rubles,
  String comment = '',
}) async => (await tester.runAsync(
  () =>
      DriftExpensesRepository(
        db,
        currentUser: LocalPrefsCurrentUser(DriftPrefsRepository(db)),
        outbox: DriftOutboxQueue(db),
        now: () => createdAt,
      ).create(
        budgetId: budgetId,
        categoryId: categoryId,
        amount: Money.rubles(rubles),
        spentOn: spentOn,
        comment: comment,
      ),
))!;

void main() {
  testWidgets('тап по 17 октября открывает шторку как на 9:439: заголовок с '
      'днём недели из intl, итог 1 450 ₽, «2 траты · больше среднего на '
      '487 ₽», две траты с категорией, комментарием и временем, подсказка и '
      '«Добавить трату в этот день»; день выбран на карточке, шторка поверх '
      'меню', (tester) async {
    final db = openTestDatabase();
    await _seedOctober(tester, db);
    await ShellHarness.start(tester, db: db);

    await _openDay(tester, '17 октября');

    expect(_sheet, findsOneWidget);
    expect(_sheetText('Суббота, 17 октября'), findsOneWidget);
    expect(_sheetText(_rub('1 450')), findsOneWidget);
    expect(
      _sheetText('2 траты · больше среднего на ${_rub('487')}'),
      findsOneWidget,
    );
    final rows = _rows(tester);
    expect(rows.map((r) => r.emoji), ['☕', '🛒']);
    expect(rows.map((r) => r.color), [
      CategoryColor.orange,
      CategoryColor.green,
    ]);
    expect(rows.map((r) => r.title), ['Кафе', 'Продукты']);
    expect(rows.map((r) => r.subtitle), [
      'Обед с коллегами · 13:30',
      'ВкусВилл · 19:10',
    ]);
    expect(rows.map((r) => r.amount), [_rub('890'), _rub('560')]);
    expect(rows.map((r) => r.author), [null, null]);
    expect(
      _sheetText('Нажми на трату, чтобы изменить. Смахни влево — удалить.'),
      findsOneWidget,
    );
    final button = tester.widget<AppButton>(_inSheet(find.byType(AppButton)));
    expect(button.label, 'Добавить трату в этот день');
    expect(button.type, AppButtonType.soft);

    expect(_card(tester).selectedDay, 17);
    final sheet = tester.getRect(find.byType(AppSheet));
    expect(sheet.bottom, 800);
    expect(sheet.top, lessThan(tester.getRect(find.byType(AppBottomNav)).top));
    expect(tester.takeException(), isNull);
  });

  testWidgets('жест «назад» закрывает шторку дня, выбор дня снимается, '
      'главная остаётся на октябре', (tester) async {
    final db = openTestDatabase();
    await _seedOctober(tester, db);
    final h = await ShellHarness.start(tester, db: db);

    await _openDay(tester, '17 октября');
    expect(_sheet, findsOneWidget);

    await h.systemBack();

    expect(_sheet, findsNothing);
    expect(_card(tester).selectedDay, isNull);
    expect(_card(tester).month, YearMonth(2026, 10));
    expect(h.systemPops, 0);
  });

  testWidgets('тап мимо шторки закрывает её', (tester) async {
    final db = openTestDatabase();
    await _seedOctober(tester, db);
    await ShellHarness.start(tester, db: db);

    await _openDay(tester, '17 октября');
    await tester.tapAt(const Offset(180, 40));
    await tester.pumpAndSettle();

    expect(_sheet, findsNothing);
    expect(_card(tester).selectedDay, isNull);
  });

  testWidgets('будущий день шторку не открывает, сегодняшний открывает', (
    tester,
  ) async {
    final db = openTestDatabase();
    await _seedOctober(tester, db);
    final h = await ShellHarness.start(tester, db: db);

    await _openDay(tester, '20 октября');
    expect(_sheet, findsNothing);
    expect(
      _monthDebug(h),
      contains('day tap date=2026-10-20 ignored: future day today=2026-10-19'),
    );

    await _openDay(tester, '19 октября');
    expect(_sheet, findsOneWidget);
    expect(_sheetText('Понедельник, 19 октября'), findsOneWidget);
    expect(_sheetText(_rub('1 100')), findsOneWidget);
    expect(
      _sheetText('3 траты · больше среднего на ${_rub('137')}'),
      findsOneWidget,
    );
  });

  testWidgets('день без трат: итог 0 ₽, «0 трат · меньше среднего на 963 ₽», '
      'без списка и подсказки — только кнопка', (tester) async {
    final db = openTestDatabase();
    await _seedOctober(tester, db);
    await ShellHarness.start(tester, db: db);

    await _openDay(tester, '4 октября');

    expect(_sheetText('Воскресенье, 4 октября'), findsOneWidget);
    expect(_sheetText('0$nbsp₽'), findsOneWidget);
    expect(
      _sheetText('0 трат · меньше среднего на ${_rub('963')}'),
      findsOneWidget,
    );
    expect(_inSheet(find.byType(ExpenseRow)), findsNothing);
    expect(
      _sheetText('Нажми на трату, чтобы изменить. Смахни влево — удалить.'),
      findsNothing,
    );
    expect(_sheetText('Добавить трату в этот день'), findsOneWidget);
  });

  testWidgets('число трат с окончанием: 1 трата, 3 траты, 5 трат, 7 трат, '
      '2 траты', (tester) async {
    final db = openTestDatabase();
    await _seedOctober(tester, db);
    final h = await ShellHarness.start(tester, db: db);

    for (final (date, line) in [
      ('12 октября', '1 трата · больше среднего на ${_rub('1 937')}'),
      ('1 октября', '3 траты · меньше среднего на ${_rub('513')}'),
      ('3 октября', '5 трат · больше среднего на ${_rub('1 377')}'),
      ('10 октября', '7 трат · больше среднего на ${_rub('1 707')}'),
      ('13 октября', '2 траты · меньше среднего на ${_rub('753')}'),
    ]) {
      await _openDay(tester, date);
      expect(_sheetText(line), findsOneWidget, reason: date);
      await h.systemBack();
    }
  });

  testWidgets('прошедший месяц: 12 сентября сравнивается со средним сентября '
      'за все 30 дней', (tester) async {
    final db = openTestDatabase();
    await _seedOctober(tester, db);
    await ShellHarness.start(tester, db: db);

    await tester.tap(find.bySemanticsLabel('Предыдущий месяц'));
    await tester.pumpAndSettle();
    await _openDay(tester, '12 сентября');

    expect(_sheetText('Суббота, 12 сентября'), findsOneWidget);
    expect(_sheetText(_rub('4 460')), findsOneWidget);
    expect(
      _sheetText('2 траты · больше среднего на ${_rub('3 607')}'),
      findsOneWidget,
    );
    expect(_card(tester).selectedDay, 12);
    expect(_card(tester).month, YearMonth(2026, 9));
  });

  testWidgets('время в подзаголовке только если трату создали в тот же день '
      '(00-spec §7.2): создана 19-го за 17-е — без времени, без комментария '
      '— только время или ничего', (tester) async {
    final db = openTestDatabase();
    final budgetId = await _seedOctober(tester, db);
    final categories = await _categories(tester, db, budgetId);
    final transport = categories.firstWhere((c) => c.name == 'Транспорт');
    final day = LocalDate(2026, 10, 17);
    await _addExpense(
      tester,
      db,
      budgetId: budgetId,
      categoryId: transport.id,
      spentOn: day,
      createdAt: DateTime(2026, 10, 19, 9, 5),
      rubles: 120,
      comment: 'Метро, 2 поездки',
    );
    await _addExpense(
      tester,
      db,
      budgetId: budgetId,
      categoryId: transport.id,
      spentOn: day,
      createdAt: DateTime(2026, 10, 19, 9, 10),
      rubles: 60,
    );
    await _addExpense(
      tester,
      db,
      budgetId: budgetId,
      categoryId: transport.id,
      spentOn: day,
      createdAt: DateTime(2026, 10, 17, 23, 59),
      rubles: 30,
    );
    await ShellHarness.start(tester, db: db);

    await _openDay(tester, '17 октября');

    final rows = _rows(tester);
    expect(rows.map((r) => r.title), [
      'Кафе',
      'Продукты',
      'Транспорт',
      'Транспорт',
      'Транспорт',
    ]);
    expect(rows.map((r) => r.subtitle), [
      'Обед с коллегами · 13:30',
      'ВкусВилл · 19:10',
      '23:59',
      'Метро, 2 поездки',
      null,
    ]);
    expect(
      _sheetText('5 трат · больше среднего на ${_rub('686')}'),
      findsOneWidget,
    );
    expect(_sheetText(_rub('1 660')), findsOneWidget);
  });

  testWidgets('новая трата за день сразу видна в открытой шторке', (
    tester,
  ) async {
    final db = openTestDatabase();
    final budgetId = await _seedOctober(tester, db);
    final categories = await _categories(tester, db, budgetId);
    await ShellHarness.start(tester, db: db);
    await _openDay(tester, '17 октября');

    await _addExpense(
      tester,
      db,
      budgetId: budgetId,
      categoryId: categories.first.id,
      spentOn: LocalDate(2026, 10, 17),
      createdAt: DateTime(2026, 10, 17, 21, 0),
      rubles: 100,
      comment: 'Хлеб',
    );
    await tester.pumpAndSettle();

    expect(_rows(tester), hasLength(3));
    expect(_sheetText(_rub('1 550')), findsOneWidget);
    expect(
      _sheetText('3 траты · больше среднего на ${_rub('582')}'),
      findsOneWidget,
    );
  });

  testWidgets('«Добавить трату в этот день» открывает «Новую трату» с датой '
      'в маршруте поверх шторки, «назад» возвращает к шторке', (tester) async {
    final db = openTestDatabase();
    await _seedOctober(tester, db);
    final h = await ShellHarness.start(tester, db: db);
    await _openDay(tester, '17 октября');

    await tester.tap(_sheetText('Добавить трату в этот день'));
    await tester.pumpAndSettle();

    expect(find.byType(NewExpenseStubScreen), findsOneWidget);
    expect(_location(tester), '/expense/new?date=2026-10-17');
    expect(
      GoRouter.of(tester.element(find.byType(NewExpenseStubScreen)))
          .state
          .uri
          .queryParameters,
      {'date': '2026-10-17'},
    );

    await h.systemBack();

    expect(find.byType(NewExpenseStubScreen), findsNothing);
    expect(_sheet, findsOneWidget);
    expect(_location(tester), '/month');
    await h.systemBack();
    expect(_sheet, findsNothing);
  });

  testWidgets('тап по трате открывает /expense/<id> (заглушка «Трата»), '
      'стрелка назад возвращает к шторке', (tester) async {
    final db = openTestDatabase();
    final budgetId = await _seedOctober(tester, db);
    final expenses = (await tester.runAsync(
      () =>
          DriftMonthQueries(db)
              .watchDayExpenses(budgetId, LocalDate(2026, 10, 17))
              .first,
    ))!;
    expect(expenses, hasLength(2));
    await ShellHarness.start(tester, db: db);
    await _openDay(tester, '17 октября');

    await tester.tap(_sheetText('Продукты'));
    await tester.pumpAndSettle();

    final screen = tester.widget<ExpenseStubScreen>(
      find.byType(ExpenseStubScreen),
    );
    expect(screen.expenseId, expenses[1].id);
    expect(_location(tester), '/expense/${expenses[1].id}');
    expect(find.text('Трата'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Назад'));
    await tester.pumpAndSettle();

    expect(find.byType(ExpenseStubScreen), findsNothing);
    expect(_sheet, findsOneWidget);
  });

  testWidgets('категория траты не найдена — строка как системная «Другое», '
      'warn в логе', (tester) async {
    final db = openTestDatabase();
    final budgetId = await _seedOctober(tester, db);
    final categories = await _categories(tester, db, budgetId);
    final other = categories.singleWhere((c) => c.isSystem);
    final orphan = Expense(
      id: 'e-orphan',
      budgetId: budgetId,
      categoryId: 'deleted-category',
      amount: Money.rubles(70),
      spentOn: LocalDate(2026, 10, 17),
      comment: 'Хлеб',
      authorId: 'u-1',
      createdAt: DateTime(2026, 10, 17, 22),
      updatedAt: DateTime(2026, 10, 17, 22),
      updatedBy: 'u-1',
    );
    await tester.runAsync(
      () => DriftExpensesRepository(
        db,
        currentUser: LocalPrefsCurrentUser(DriftPrefsRepository(db)),
        outbox: DriftOutboxQueue(db),
      ).applyFromServer([orphan]),
    );
    final h = await ShellHarness.start(tester, db: db);

    await _openDay(tester, '17 октября');

    final row = _rows(tester).last;
    expect(row.title, other.name);
    expect(row.emoji, other.emoji);
    expect(row.color, isNull);
    expect(row.subtitle, 'Хлеб · 22:00');
    final warnings = h.records
        .where((r) => r.loggerName == 'month' && r.level == Level.WARNING)
        .map((r) => r.message)
        .toList();
    expect(warnings, [
      'day sheet expense id=e-orphan category=deleted-category not found '
          'among 11 categories of budgetId=$budgetId, showing it as system '
          'category ${other.id}',
    ]);
    expect(warnings.single, isNot(contains('Хлеб')));
  });

  testWidgets('в базе нет бюджета: шторка дня с 0 ₽ и «0 трат», кнопка '
      'работает', (tester) async {
    await ShellHarness.start(tester);

    await _openDay(tester, '17 октября');

    expect(_sheetText('Суббота, 17 октября'), findsOneWidget);
    expect(_sheetText('0$nbsp₽'), findsOneWidget);
    expect(_sheetText('0 трат'), findsOneWidget);
    expect(_inSheet(find.byType(ExpenseRow)), findsNothing);

    await tester.tap(_sheetText('Добавить трату в этот день'));
    await tester.pumpAndSettle();
    expect(find.byType(NewExpenseStubScreen), findsOneWidget);
  });

  testWidgets('320 dp и шрифт 2.0: шторка без переполнений, итог под '
      'заголовком, кнопка доступна', (tester) async {
    final db = openTestDatabase();
    await _seedOctober(tester, db);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await ShellHarness.start(tester, db: db, size: const Size(320, 800));

    await _openDay(tester, '17 октября');

    expect(tester.takeException(), isNull);
    final title = tester.getRect(_sheetText('Суббота, 17 октября'));
    final total = tester.getRect(_sheetText(_rub('1 450')));
    expect(total.top, greaterThan(title.bottom));
    await tester.ensureVisible(_sheetText('Добавить трату в этот день'));
    await tester.pumpAndSettle();
    await tester.tap(_sheetText('Добавить трату в этот день'));
    await tester.pumpAndSettle();
    expect(find.byType(NewExpenseStubScreen), findsOneWidget);
  });
}
