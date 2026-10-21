import 'package:flutter/material.dart';
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
import 'package:milionchik/features/month/today_block.dart';
import 'package:milionchik/features/expense/edit_expense_screen.dart';
import 'package:milionchik/features/expense/new_expense_screen.dart';
import 'package:milionchik/ui/components/bottom_nav.dart';
import 'package:milionchik/ui/components/button.dart';
import 'package:milionchik/ui/components/expense_row.dart';
import 'package:milionchik/ui/components/month_card.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';
import '../shell/shell_harness.dart';
import 'month_fixture.dart';

String _rub(String digits) => '${digits.replaceAll(' ', nbsp)}$nbsp₽';

const String _hint =
    'Записывай траты — и календарь начнёт раскрашиваться: чем больше '
    'потратил за день, тем ярче ячейка.';

Finder get _block => find.byType(TodayBlock);

Finder _inBlock(Finder finder) => find.descendant(of: _block, matching: finder);

Finder _blockText(String text) => _inBlock(find.text(text));

List<ExpenseRow> _rows(WidgetTester tester) =>
    tester.widgetList<ExpenseRow>(_inBlock(find.byType(ExpenseRow))).toList();

MonthCard _card(WidgetTester tester) =>
    tester.widget<MonthCard>(find.byType(MonthCard));

String _location(WidgetTester tester) =>
    GoRouter.of(tester.element(find.byType(AppBottomNav, skipOffstage: false)))
        .state
        .uri
        .toString();

Future<String> _seedOctober(WidgetTester tester, AppDatabase db) async =>
    (await tester.runAsync(() => seedMockupOctober(db)))!;

Future<String> _personalBudget(WidgetTester tester, AppDatabase db) async =>
    (await tester.runAsync(() => testBudgets(db).createLocalPersonal()))!.id;

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

DriftExpensesRepository _expenses(AppDatabase db, DateTime now) =>
    DriftExpensesRepository(
      db,
      currentUser: LocalPrefsCurrentUser(DriftPrefsRepository(db)),
      outbox: DriftOutboxQueue(db),
      now: () => now,
    );

Future<void> _tapArrow(WidgetTester tester, String label) async {
  await tester.tap(find.bySemanticsLabel(label));
  await tester.pumpAndSettle();
}

void _expectEmptyState(WidgetTester tester) {
  expect(_blockText('Сегодня, 19 октября'), findsOneWidget);
  expect(_blockText('0$nbsp₽'), findsOneWidget);
  expect(_blockText('👋'), findsOneWidget);
  expect(_blockText(_hint), findsOneWidget);
  final button = tester.widget<AppButton>(_inBlock(find.byType(AppButton)));
  expect(button.label, 'Добавить первую трату');
  expect(button.type, AppButtonType.soft);
  expect(button.size, AppButtonSize.m);
  expect(button.icon, isNull);
  expect(_inBlock(find.byType(ExpenseRow)), findsNothing);
  expect(_blockText('Сегодня трат нет'), findsNothing);
}

void main() {
  testWidgets('текущий месяц: под карточкой «Сегодня, 19 октября», 1 100 ₽ и '
      'три траты дня как на 7:7 — свежая первой, категория, комментарий и '
      'время', (tester) async {
    final db = openTestDatabase();
    await _seedOctober(tester, db);
    await ShellHarness.start(tester, db: db);

    expect(_block, findsOneWidget);
    expect(_blockText('Сегодня, 19 октября'), findsOneWidget);
    expect(_blockText(_rub('1 100')), findsOneWidget);
    final rows = _rows(tester);
    expect(rows.map((r) => r.emoji), ['🛒', '🚇', '☕']);
    expect(rows.map((r) => r.color), [
      CategoryColor.green,
      CategoryColor.yellow,
      CategoryColor.orange,
    ]);
    expect(rows.map((r) => r.title), ['Продукты', 'Транспорт', 'Кафе']);
    expect(rows.map((r) => r.subtitle), [
      'Пятёрочка · 18:40',
      'Метро, 2 поездки · 12:40',
      'Кофе с собой · 09:15',
    ]);
    expect(rows.map((r) => r.amount), [_rub('640'), _rub('250'), _rub('210')]);
    expect(rows.map((r) => r.author), [null, null, null]);
    expect(_blockText('👋'), findsNothing);
    expect(_blockText('Сегодня трат нет'), findsNothing);

    final card = tester.getRect(find.byType(MonthCard));
    final block = tester.getRect(_block);
    expect(block.top - card.bottom, 20);
    expect(block.left, card.left);
    expect(block.width, card.width);
  });

  testWidgets('на сентябре и августе блока нет, на октябре он снова под '
      'карточкой', (tester) async {
    final db = openTestDatabase();
    await _seedOctober(tester, db);
    await ShellHarness.start(tester, db: db);

    await _tapArrow(tester, 'Предыдущий месяц');
    expect(_card(tester).month, YearMonth(2026, 9));
    expect(_block, findsNothing);
    expect(find.text('Сегодня, 19 октября'), findsNothing);

    await _tapArrow(tester, 'Предыдущий месяц');
    expect(_card(tester).month, YearMonth(2026, 8));
    expect(_block, findsNothing);

    await _tapArrow(tester, 'Следующий месяц');
    await _tapArrow(tester, 'Следующий месяц');
    expect(_card(tester).month, YearMonth(2026, 10));
    expect(_block, findsOneWidget);
    expect(_rows(tester), hasLength(3));
  });

  testWidgets('прошлый месяц и в пустой базе — блок и пустое состояние '
      'скрыты', (tester) async {
    await ShellHarness.start(tester);
    expect(_block, findsOneWidget);

    await _tapArrow(tester, 'Предыдущий месяц');

    expect(_block, findsNothing);
    expect(find.text('👋'), findsNothing);
    expect(find.text('Добавить первую трату'), findsNothing);
  });

  testWidgets('тап по трате в блоке открывает /expense/<id> (экран '
      '«Трата»), «назад» возвращает на главную', (tester) async {
    final db = openTestDatabase();
    final budgetId = await _seedOctober(tester, db);
    final today = (await tester.runAsync(
      () =>
          DriftMonthQueries(db)
              .watchDayExpenses(budgetId, LocalDate(2026, 10, 19))
              .first,
    ))!;
    final pyaterochka = today.singleWhere((e) => e.comment == 'Пятёрочка');
    await ShellHarness.start(tester, db: db);

    await tester.ensureVisible(_blockText('Пятёрочка · 18:40'));
    await tester.pumpAndSettle();
    await tester.tap(_blockText('Пятёрочка · 18:40'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<EditExpenseScreen>(find.byType(EditExpenseScreen))
          .expenseId,
      pyaterochka.id,
    );
    expect(_location(tester), '/expense/${pyaterochka.id}');

    await tester.tap(find.bySemanticsLabel('Назад'));
    await tester.pumpAndSettle();
    expect(find.byType(EditExpenseScreen), findsNothing);
    expect(_location(tester), '/month');
    expect(_block, findsOneWidget);
  });

  testWidgets('чистая установка без бюджета — пустое состояние как 47:5524: '
      '0 ₽, 👋, подсказка и «Добавить первую трату» открывает «Новую трату»', (
    tester,
  ) async {
    await ShellHarness.start(tester);

    _expectEmptyState(tester);

    await tester.ensureVisible(_blockText('Добавить первую трату'));
    await tester.pumpAndSettle();
    await tester.tap(_blockText('Добавить первую трату'));
    await tester.pumpAndSettle();
    expect(find.byType(NewExpenseScreen), findsOneWidget);
    expect(_location(tester), '/expense/new');
  });

  testWidgets('бюджет есть, трат за всё время нет (одна удалена) — пустое '
      'состояние', (tester) async {
    final db = openTestDatabase();
    final budgetId = await _personalBudget(tester, db);
    final categories = await _categories(tester, db, budgetId);
    final repo = _expenses(db, DateTime(2026, 10, 2, 12));
    await tester.runAsync(() async {
      final expense = await repo.create(
        budgetId: budgetId,
        categoryId: categories.first.id,
        amount: const Money.rubles(300),
        spentOn: LocalDate(2026, 10, 2),
      );
      await repo.delete(expense.id);
    });
    await ShellHarness.start(tester, db: db);

    _expectEmptyState(tester);
  });

  testWidgets('сегодня трат нет, а раньше были — «Сегодня трат нет» и 0 ₽, '
      'без пустого состояния', (tester) async {
    final db = openTestDatabase();
    await _seedOctober(tester, db);
    await ShellHarness.start(tester, db: db, now: DateTime(2026, 10, 4, 12));

    expect(_blockText('Сегодня, 4 октября'), findsOneWidget);
    expect(_blockText('0$nbsp₽'), findsOneWidget);
    expect(_blockText('Сегодня трат нет'), findsOneWidget);
    expect(_inBlock(find.byType(ExpenseRow)), findsNothing);
    expect(_blockText('👋'), findsNothing);
    expect(_inBlock(find.byType(AppButton)), findsNothing);
  });

  testWidgets('первая трата сегодня сразу заменяет пустое состояние строкой, '
      'вторая встаёт первой', (tester) async {
    final db = openTestDatabase();
    final budgetId = await _personalBudget(tester, db);
    final categories = await _categories(tester, db, budgetId);
    await ShellHarness.start(tester, db: db);
    _expectEmptyState(tester);

    await tester.runAsync(
      () => _expenses(db, DateTime(2026, 10, 19, 9, 5)).create(
        budgetId: budgetId,
        categoryId: categories.first.id,
        amount: const Money.rubles(120),
        spentOn: LocalDate(2026, 10, 19),
        comment: 'Булочка',
      ),
    );
    await tester.pumpAndSettle();
    expect(_blockText('👋'), findsNothing);
    expect(_rows(tester).map((r) => r.subtitle), ['Булочка · 09:05']);
    expect(_blockText(_rub('120')), findsNWidgets(2));

    await tester.runAsync(
      () => _expenses(db, DateTime(2026, 10, 19, 13)).create(
        budgetId: budgetId,
        categoryId: categories[1].id,
        amount: const Money.rubles(80, 50),
        spentOn: LocalDate(2026, 10, 19),
      ),
    );
    await tester.pumpAndSettle();
    expect(_rows(tester).map((r) => r.subtitle), ['13:00', 'Булочка · 09:05']);
    expect(_blockText(_rub('201')), findsOneWidget);
  });

  testWidgets('трата без найденной категории — строка как системная '
      '«Другое»', (tester) async {
    final db = openTestDatabase();
    final budgetId = await _seedOctober(tester, db);
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
          comment: 'Хлеб',
          authorId: 'u-1',
          createdAt: DateTime(2026, 10, 19, 21),
          updatedAt: DateTime(2026, 10, 19, 21),
          updatedBy: 'u-1',
        ),
      ]),
    );
    await ShellHarness.start(tester, db: db);

    final row = _rows(tester).first;
    expect(row.title, other.name);
    expect(row.emoji, other.emoji);
    expect(row.color, isNull);
    expect(row.subtitle, 'Хлеб · 21:00');
  });

  for (final (name, seed) in [
    ('три траты', _seedOctober),
    ('пустое состояние', _personalBudget),
  ]) {
    testWidgets('320 dp и шрифт 2.0, $name: без переполнений, всё доступно '
        'прокруткой', (tester) async {
      final db = openTestDatabase();
      await seed(tester, db);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      final h = await ShellHarness.start(
        tester,
        db: db,
        size: const Size(320, 800),
      );

      expect(tester.takeException(), isNull);
      final title = _blockText('Сегодня, 19 октября');
      expect(title, findsOneWidget);
      final last = _inBlock(
        name == 'три траты'
            ? find.byType(ExpenseRow).last
            : find.byType(AppButton),
      );
      await tester.ensureVisible(last);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(last).bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(AppBottomNav)).top),
      );
      expect(tester.getSize(last).height, greaterThanOrEqualTo(48));
      await tester.tap(last);
      await tester.pumpAndSettle();
      expect(
        h.records.where(
          (r) => r.level >= Level.WARNING && r.loggerName == 'month',
        ),
        isEmpty,
      );
      expect(
        find.byType(name == 'три траты' ? EditExpenseScreen : NewExpenseScreen),
        findsOneWidget,
      );
    });
  }
}
