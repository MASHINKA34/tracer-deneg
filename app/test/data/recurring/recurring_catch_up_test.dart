import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

import 'recurring_harness.dart';

void main() {
  late RecurringHarness r;

  setUp(() async => r = await RecurringHarness().seed());

  tearDown(() => r.dispose());

  test('догонялка: приложение не открывали три месяца — создаются август, '
      'сентябрь и октябрь, июль не трогается', () async {
    final rule = await r.rule(day: 5, from: YearMonth(2026, 7));

    r.today = LocalDate(2026, 7, 10);
    expect((await r.run()).created, 1);
    final july = (await r.expensesOf(rule.id)).single;

    r.repo.advance(const Duration(days: 104));
    r.today = LocalDate(2026, 10, 22);
    final result = await r.run();

    expect(result.rules, 1);
    expect(result.created, 3);
    expect(result.skippedExisting, 1);
    expect(result.skippedDeleted, 0);
    expect(result.ok, isTrue);

    final expenses = await r.expensesOf(rule.id);
    expect(expenses.map((e) => e.recurringMonth), [
      YearMonth(2026, 7),
      YearMonth(2026, 8),
      YearMonth(2026, 9),
      YearMonth(2026, 10),
    ]);
    expect(expenses.first, july);
    expect(expenses.skip(1).map((e) => e.spentOn), [
      LocalDate(2026, 8, 5),
      LocalDate(2026, 9, 5),
      LocalDate(2026, 10, 5),
    ]);
    for (final e in expenses) {
      expect(e.id, recurringExpenseId(rule.id, e.recurringMonth!));
      expect(e.recurringId, rule.id);
      expect(e.comment, internetTitle);
      expect(e.amount, const Money.rubles(650));
      expect(e.budgetId, r.budget.id);
      expect(e.categoryId, r.budget.byName('Связь').id);
      expect(e.authorId, meId);
      expect(e.deletedAt, isNull);
    }
  });

  test('созданные траты лежат в outbox одной записью upsert на трату с полной '
      'моделью', () async {
    final rule = await r.rule(day: 5, from: YearMonth(2026, 8));
    await r.run();

    final expenses = await r.expensesOf(rule.id);
    expect(expenses, hasLength(3));
    final rows = await r.repo.outboxRows();
    final expenseRows = [
      for (final row in rows)
        if (row.entity == SyncEntity.expense) row,
    ];
    expect(expenseRows.map((row) => row.op), everyElement(SyncOp.upsert));
    expect(expenseRows.map((row) => row.entityId), [
      for (final e in expenses) e.id,
    ]);
    expect(expenseRows.map(payloadOf), [for (final e in expenses) e.toJson()]);
  });

  test('правило на сегодняшнее число: трата появляется в первом же запуске '
      'после сохранения', () async {
    final today = r.today;
    final rule = await r.rule(
      day: today.day,
      from: startMonthForNewRule(today.day, today),
    );
    expect(rule.startMonth, YearMonth(2026, 10));

    final result = await r.run();

    expect(result.created, 1);
    final expense = (await r.expensesOf(rule.id)).single;
    expect(expense.spentOn, today);
    expect(expense.recurringMonth, YearMonth(2026, 10));
  });

  test(
    'правило на прошедшее число: первая трата только в следующем месяце',
    () async {
      final rule = await r.rule(
        day: 20,
        from: startMonthForNewRule(20, r.today),
      );

      expect((await r.run()).created, 0);
      expect(await r.expensesOf(rule.id), isEmpty);

      r.today = LocalDate(2026, 11, 20);
      expect((await r.run()).created, 1);
      expect(
        (await r.expensesOf(rule.id)).single.spentOn,
        LocalDate(2026, 11, 20),
      );
    },
  );

  test('правила всех бюджетов: личный и общий', () async {
    final shared = await r.repo.seedBudget(kind: BudgetKind.shared);
    final personal = await r.rule(day: 1, from: YearMonth(2026, 10));
    final family = await r.repo.recurring.create(
      budgetId: shared.id,
      categoryId: shared.byName('Дом').id,
      title: 'Квартплата',
      amount: const Money.rubles(5400),
      dayOfMonth: 10,
      startMonth: YearMonth(2026, 10),
    );

    final result = await r.run();

    expect(result.rules, 2);
    expect(result.created, 2);
    expect((await r.expensesOf(personal.id)).single.budgetId, r.budget.id);
    expect((await r.expensesOf(family.id)).single.budgetId, shared.id);
  });
}
