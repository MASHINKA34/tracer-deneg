import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

import 'recurring_harness.dart';

void main() {
  late RecurringHarness r;

  setUp(() async => r = await RecurringHarness().seed());

  tearDown(() => r.dispose());

  test('правка суммы, категории и названия правила не меняет прошлые траты, '
      'новые — по новым значениям', () async {
    final rule = await r.rule(day: 5, from: YearMonth(2026, 9));
    await r.run();
    final before = await r.expensesOf(rule.id);
    expect(before.map((e) => e.amount), [
      const Money.rubles(650),
      const Money.rubles(650),
    ]);

    r.repo.advance(const Duration(days: 1));
    await r.repo.recurring.update(
      rule.id,
      amount: const Money.rubles(700),
      categoryId: r.budget.byName('Дом').id,
      title: 'Домашний интернет',
    );
    final rerun = await r.run();
    expect(rerun.created, 0);
    expect(await r.expensesOf(rule.id), before);

    r.today = LocalDate(2026, 11, 5);
    expect((await r.run()).created, 1);
    final after = await r.expensesOf(rule.id);
    expect(after.take(2), before);
    expect(after.last.amount, const Money.rubles(700));
    expect(after.last.categoryId, r.budget.byName('Дом').id);
    expect(after.last.comment, 'Домашний интернет');
  });

  test('удалённое правило не генерирует, уже созданные траты остаются',
      () async {
    final rule = await r.rule(day: 5, from: YearMonth(2026, 10));
    await r.run();
    final created = await r.expensesOf(rule.id);
    expect(created, hasLength(1));

    await r.repo.recurring.delete(rule.id);
    r.today = LocalDate(2026, 12, 6);
    final result = await r.run();

    expect(result.rules, 0);
    expect(result.created, 0);
    expect(await r.expensesOf(rule.id), created);
  });

  test('правило, удалённое до первого списания, не создаёт ничего', () async {
    final rule = await r.rule(day: 5, from: YearMonth(2026, 8));
    await r.repo.recurring.delete(rule.id);

    final result = await r.run();

    expect(result.rules, 0);
    expect(result.created, 0);
    expect(await r.expenseCount(), 0);
  });

  test('правило удалённого бюджета не генерирует', () async {
    final shared = await r.repo.seedBudget(kind: BudgetKind.shared);
    final rule = await r.repo.recurring.create(
      budgetId: shared.id,
      categoryId: shared.byName('Дом').id,
      title: 'Квартплата',
      amount: const Money.rubles(5400),
      dayOfMonth: 1,
      startMonth: YearMonth(2026, 10),
    );
    final gone = DateTime.utc(2026, 10, 15);
    await r.repo.budgets.applyFromServer([
      shared.budget.copyWith(deletedAt: gone, updatedAt: gone),
    ]);

    final result = await r.run();

    expect(result.rules, 0);
    expect(await r.expensesOf(rule.id), isEmpty);
  });
}
