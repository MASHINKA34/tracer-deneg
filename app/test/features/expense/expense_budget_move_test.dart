import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/router.dart';
import 'package:milionchik/data/current_user.dart';
import 'package:milionchik/data/queries/month_queries.dart';
import 'package:milionchik/data/repositories/expenses_repository.dart';
import 'package:milionchik/data/repositories/outbox_queue.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:milionchik/features/budgets/budget_switcher_sheet.dart';
import 'package:milionchik/features/expense/edit_expense_controller.dart';
import 'package:milionchik/features/expense/edit_expense_screen.dart';
import 'package:milionchik/features/month/month_header.dart';
import 'package:milionchik/ui/components/bottom_nav.dart';
import 'package:milionchik/ui/components/button.dart';
import 'package:milionchik/ui/components/chip.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';
import '../auth/session_expired_fixture.dart' show testUnmounting;
import '../budgets/budget_switcher_fixture.dart';
import '../shell/shell_harness.dart';
import 'new_expense_harness.dart';

final LocalDate _october19 = LocalDate(2026, 10, 19);

Finder _inEdit(Finder finder) =>
    find.descendant(of: find.byType(EditExpenseScreen), matching: finder);

Finder _row(String label) => _inEdit(find.bySemanticsLabel(RegExp('^$label')));

Finder _sheetRow(String budgetId) => find.byWidgetPredicate(
  (w) => w is BudgetSheetRow && w.budget.id == budgetId,
);

final class _Move {
  _Move(this.h, this.fixture, this.expense);

  final ShellHarness h;
  final SwitcherFixture fixture;
  final Expense expense;

  WidgetTester get tester => h.tester;

  static Future<_Move> start(
    WidgetTester tester, {
    List<Category> Function(List<Category> presets)? familyCategories,
  }) async {
    final db = openTestDatabase();
    final (fixture, expense) = (await tester.runAsync(() async {
      final fixture = await SwitcherFixture.mockup(
        db,
        familyCategories: familyCategories,
      );
      final today = await DriftMonthQueries(db)
          .watchDayExpenses(fixture.personalId, _october19)
          .first;
      return (fixture, today.singleWhere((e) => e.comment == 'Пятёрочка'));
    }))!;
    final h = await ShellHarness.start(tester, db: db);
    unawaited(
      GoRouter.of(tester.element(find.byType(AppBottomNav)))
          .push<void>(AppRoutes.expenseOf(expense.id)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(EditExpenseScreen), findsOneWidget);
    return _Move(h, fixture, expense);
  }

  String label(String row) => tester.getSemantics(_row(row)).label;

  bool get saveEnabled =>
      tester
          .widget<AppButton>(
            _inEdit(find.widgetWithText(AppButton, 'Сохранить')),
          )
          .onPressed !=
      null;

  Future<void> moveTo(String budgetId) async {
    await tester.ensureVisible(_row('Бюджет'));
    await tester.pumpAndSettle();
    await tester.tap(_row('Бюджет'));
    await tester.pumpAndSettle();
    expect(find.byType(BudgetSheet), findsOneWidget);
    expect(find.text('Создать общий бюджет'), findsNothing);
    expect(find.text('Войти по коду приглашения'), findsNothing);
    await tester.tap(_sheetRow(budgetId));
    await _settle(tester);
    expect(find.byType(BudgetSheet), findsNothing);
  }

  Future<Expense?> stored() => tester.runAsync<Expense?>(
    () => DriftExpensesRepository(
      h.db,
      currentUser: LocalPrefsCurrentUser(DriftPrefsRepository(h.db)),
      outbox: DriftOutboxQueue(h.db),
    ).watchById(expense.id).first,
  );
}

Category _category(String id, String name, {bool system = false}) => Category(
  id: id,
  budgetId: familyId,
  name: name,
  emoji: '🏷',
  color: system ? null : CategoryColor.teal,
  sortOrder: system ? 99 : 0,
  isSystem: system,
  updatedAt: DateTime.utc(2026, 10, 1),
  updatedBy: familyOwnerId,
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  test('categoryForMove: та же категория по названию без учёта регистра и '
      'ё/е, иначе «Другое» нового бюджета; без «Другое» — null', () {
    final target = [
      _category('c-kids', 'Детское ПИТАНИЕ'),
      _category('c-other', 'Другое', system: true),
    ];
    final current = _category('p-kids', ' детское питание ');
    expect(categoryForMove(current, target)?.id, 'c-kids');
    expect(
      categoryForMove(_category('p-yo', 'Ёлка'), [
        _category('c-yo', 'елка'),
        ...target,
      ])?.id,
      'c-yo',
    );
    expect(categoryForMove(_category('p-x', 'Кафе'), target)?.id, 'c-other');
    expect(
      categoryForMove(_category('p-o', 'Другое', system: true), target)?.id,
      'c-other',
    );
    expect(categoryForMove(null, target)?.id, 'c-other');
    expect(categoryForMove(_category('p-x', 'Кафе'), const []), isNull);
  });

  testUnmounting('перенос траты в «Семью», где нет «Продуктов»: категория — '
      '«Другое» «Семьи», после «Сохранить» трата в «Семье», в очереди upsert', (
    tester,
  ) async {
    final m = await _Move.start(
      tester,
      familyCategories: (presets) => [
        for (final c in presets)
          if (c.name != 'Продукты') c,
      ],
    );
    expect(m.label('Бюджет'), 'Бюджет, 👛 Личный');
    expect(m.label('Категория'), 'Категория, Продукты');

    await m.moveTo(familyId);

    expect(m.label('Бюджет'), 'Бюджет, 🏠 Семья');
    expect(m.label('Категория'), 'Категория, Другое');
    expect(m.saveEnabled, isTrue);

    await tester.ensureVisible(
      _inEdit(find.widgetWithText(AppButton, 'Сохранить')),
    );
    await tester.tap(_inEdit(find.widgetWithText(AppButton, 'Сохранить')));
    await tester.pumpAndSettle();

    expect(find.byType(EditExpenseScreen), findsNothing);
    final saved = await m.stored();
    expect(saved?.budgetId, familyId);
    expect(saved?.categoryId, m.fixture.familyOther.id);
    expect(saved?.amount, m.expense.amount);
    final outbox = (await tester.runAsync(
      () => m.h.db.select(m.h.db.outbox).get(),
    ))!;
    expect(
      outbox.where((o) => o.entityId == m.expense.id).last.payload,
      contains('"budgetId":"$familyId"'),
    );
    expect(
      m.h.records
          .where((r) => r.loggerName == 'expense' && r.level == Level.INFO)
          .map((r) => r.message),
      contains(
        matches(
          RegExp(
            'expense updated id=${m.expense.id} budgetId=$familyId '
            'fields=category,budget movedFrom=${m.fixture.personalId} '
            r'in \d+ms$',
          ),
        ),
      ),
    );
    expect(
      m.h.records
          .where((r) => r.loggerName == 'expense' && r.level == Level.FINE)
          .map((r) => r.message),
      contains(
        contains(
          'expense edit id=${m.expense.id} budget ${m.fixture.personalId} → '
          '$familyId category ${m.expense.categoryId} → '
          '${m.fixture.familyOther.id} (no category with this name there → '
          '«Другое»)',
        ),
      ),
    );
  });

  testUnmounting('в «Семье» есть «Продукты»: категория та же по названию; '
      'вернул бюджет назад — исходная категория, «Сохранить» неактивна', (
    tester,
  ) async {
    final m = await _Move.start(tester);

    await m.moveTo(familyId);
    expect(m.label('Категория'), 'Категория, Продукты');
    expect(m.label('Бюджет'), 'Бюджет, 🏠 Семья');
    expect(m.saveEnabled, isTrue);

    await m.moveTo(m.fixture.personalId);
    expect(m.label('Бюджет'), 'Бюджет, 👛 Личный');
    expect(m.label('Категория'), 'Категория, Продукты');
    expect(m.saveEnabled, isFalse);
    expect((await m.stored())?.budgetId, m.fixture.personalId);
  });

  testUnmounting('у нового бюджета нет категорий: снекбар «Не получилось '
      'перенести трату», бюджет и категория прежние', (tester) async {
    final m = await _Move.start(tester, familyCategories: (_) => const []);

    await m.moveTo(familyId);

    expect(
      find.text('Не получилось перенести трату. Попробуй ещё раз'),
      findsOneWidget,
    );
    expect(m.label('Бюджет'), 'Бюджет, 👛 Личный');
    expect(m.label('Категория'), 'Категория, Продукты');
    expect(m.saveEnabled, isFalse);
  });

  testUnmounting('«Новая трата»: чип бюджета открывает шторку без «Создать…», '
      'выбор «Семьи» — сетка её категорий, трата сохраняется в «Семью», '
      'открытый на главной бюджет не меняется', (tester) async {
    final db = openTestDatabase();
    final fixture = (await tester.runAsync(
      () => SwitcherFixture.mockup(
        db,
        familyCategories: (presets) => [
          presets.first.copyWith(name: 'Дача', emoji: '🏡'),
          ...presets.skip(1),
        ],
      ),
    ))!;
    final h = await ShellHarness.start(tester, db: db);
    await h.tapPlus();
    expect(categoryTile('Продукты'), findsOneWidget);
    expect(categoryTile('Дача'), findsNothing);

    await tester.tap(inNewExpense(find.widgetWithText(AppChip, 'Личный')));
    await tester.pumpAndSettle();
    expect(find.byType(BudgetSheet), findsOneWidget);
    expect(find.text('Создать общий бюджет'), findsNothing);
    await tester.tap(_sheetRow(familyId));
    await tester.pumpAndSettle();

    expect(inNewExpense(find.widgetWithText(AppChip, 'Семья')), findsOneWidget);
    expect(categoryTile('Дача'), findsOneWidget);
    expect(categoryTile('Продукты'), findsNothing);

    await typeKeys(tester, '250');
    await tapCategory(tester, 'Дача');

    final family = (await tester.runAsync(
      () => DriftMonthQueries(db).watchDayExpenses(familyId, _october19).first,
    ))!;
    expect([
      for (final e in family) (e.amount, e.categoryId),
    ], contains((Money.rubles(250), fixture.familyCategories.first.id)));
    expect(
      find.descendant(
        of: find.byType(MonthHeaderView),
        matching: find.text('Личный бюджет'),
      ),
      findsOneWidget,
    );
    expect(
      await tester.runAsync(
        () => DriftPrefsRepository(db).getString(PrefKeys.selectedBudgetId),
      ),
      isNull,
    );
    expect(
      h.records
          .where((r) => r.loggerName == 'expense' && r.level == Level.FINE)
          .map((r) => r.message),
      contains(
        'new expense budget ${fixture.personalId} → $familyId by=budget '
        'sheet (selected budget stays ${fixture.personalId})',
      ),
    );
  });
}
