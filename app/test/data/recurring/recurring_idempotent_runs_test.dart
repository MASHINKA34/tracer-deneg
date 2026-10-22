import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/data/repositories/expenses_repository.dart';
import 'package:shared/shared.dart';

import 'recurring_harness.dart';

void main() {
  late RecurringHarness r;

  setUp(() async => r = await RecurringHarness().seed());

  tearDown(() => r.dispose());

  test('повторный запуск: дублей нет, outbox не растёт, в итоге — «уже есть»',
      () async {
    final rule = await r.rule(day: 5, from: YearMonth(2026, 8));
    expect((await r.run()).created, 3);
    final expenses = await r.expensesOf(rule.id);
    final outbox = (await r.repo.outboxRows()).length;

    final again = await r.run();

    expect(again.created, 0);
    expect(again.skippedExisting, 3);
    expect(again.skippedDeleted, 0);
    expect(await r.expensesOf(rule.id), expenses);
    expect(await r.expenseCount(), 3);
    expect((await r.repo.outboxRows()).length, outbox);
  });

  test('удалённая пользователем сгенерированная трата не возвращается — ни '
      'сразу, ни после окна отмены', () async {
    final rule = await r.rule(day: 5, from: YearMonth(2026, 9));
    await r.run();
    final october = recurringExpenseId(rule.id, YearMonth(2026, 10));

    final tombstone = await r.repo.expenses.delete(october);
    final outbox = (await r.repo.outboxRows()).length;

    final soon = await r.run();
    expect(soon.created, 0);
    expect(soon.skippedExisting, 1);
    expect(soon.skippedDeleted, 1);

    r.repo.advance(expenseUndoWindow + const Duration(seconds: 1));
    r.today = LocalDate(2026, 10, 23);
    final later = await r.run();
    expect(later.created, 0);
    expect(later.skippedDeleted, 1);

    final expenses = await r.expensesOf(rule.id);
    expect(expenses, hasLength(2));
    expect(expenses.last.id, october);
    expect(expenses.last.deletedAt, tombstone.deletedAt);
    expect(await r.repo.expenses.watchById(october).first, isNull);
    expect((await r.repo.outboxRows()).length, outbox);
  });

  test('удалённая на другом телефоне (надгробие пришло синхронизацией) тоже '
      'не пересоздаётся', () async {
    final rule = await r.rule(day: 5, from: YearMonth(2026, 10));
    final id = recurringExpenseId(rule.id, YearMonth(2026, 10));
    final at = DateTime.utc(2026, 10, 5, 8);
    await r.repo.expenses.applyFromServer([
      Expense(
        id: id,
        budgetId: r.budget.id,
        categoryId: rule.categoryId,
        amount: rule.amount,
        spentOn: LocalDate(2026, 10, 5),
        comment: rule.title,
        authorId: serverUserId,
        recurringId: rule.id,
        recurringMonth: YearMonth(2026, 10),
        createdAt: at,
        updatedAt: at,
        updatedBy: serverUserId,
        deletedAt: at,
        seq: 7,
      ),
    ]);

    final result = await r.run();

    expect(result.created, 0);
    expect(result.skippedDeleted, 1);
    expect((await r.expensesOf(rule.id)).single.deletedAt, at);
  });
}
