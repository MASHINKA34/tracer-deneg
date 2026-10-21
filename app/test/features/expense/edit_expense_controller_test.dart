import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/queries/month_queries.dart';
import 'package:milionchik/features/expense/edit_expense_controller.dart';
import 'package:shared/shared.dart';

import '../../data/provider_harness.dart';
import '../month/month_fixture.dart';

Future<(ProviderHarness, Expense)> _start() async {
  final h = ProviderHarness();
  final budgetId = await seedMockupOctober(h.db);
  final today = await DriftMonthQueries(h.db)
      .watchDayExpenses(budgetId, LocalDate(2026, 10, 19))
      .first;
  return (h, today.singleWhere((e) => e.comment == 'Пятёрочка'));
}

void main() {
  final original = Expense(
    id: 'e1',
    budgetId: 'b1',
    categoryId: 'food',
    amount: const Money.rubles(640),
    spentOn: LocalDate(2026, 10, 19),
    comment: 'Пятёрочка',
    authorId: 'u1',
    createdAt: DateTime.utc(2026, 10, 19, 15, 40),
    updatedAt: DateTime.utc(2026, 10, 19, 15, 40),
    updatedBy: 'u1',
  );

  test('изменённые поля — только те, что отличаются от траты, по порядку '
      'сумма, категория, дата, комментарий', () {
    expect(const ExpenseEdits().changedFields(original), isEmpty);
    expect(
      ExpenseEdits(
        amount: const Money.rubles(640),
        categoryId: 'food',
        spentOn: LocalDate(2026, 10, 19),
        comment: 'Пятёрочка',
      ).changedFields(original),
      isEmpty,
    );
    expect(
      ExpenseEdits(
        comment: '',
        spentOn: LocalDate(2026, 10, 17),
        amount: Money(64001),
        categoryId: 'cafe',
      ).changedFields(original),
      [
        ExpenseField.amount,
        ExpenseField.category,
        ExpenseField.date,
        ExpenseField.comment,
      ],
    );
    final edits = ExpenseEdits(spentOn: LocalDate(2026, 10, 17));
    expect(edits.changedFields(original), [ExpenseField.date]);
    expect(edits.amountOf(original), const Money.rubles(640));
    expect(edits.dateOf(original), LocalDate(2026, 10, 17));
    expect(edits.commentOf(original), 'Пятёрочка');
    expect(edits.categoryOf(original), 'food');
    expect(fieldNames(const []), 'none');
    expect(
      fieldNames([ExpenseField.category, ExpenseField.comment]),
      'category,comment',
    );
  });

  test(
    'будущая дата, комментарий длиннее 100 и сумма 0 не принимаются — '
    'warn без текста комментария; пробелы по краям комментария срезаются',
    () async {
      final (h, expense) = await _start();
      final controller = h.read(
        editExpenseControllerProvider(expense.id).notifier,
      );

      expect(controller.setDate(LocalDate(2026, 10, 20), by: 'test'), isFalse);
      expect(controller.setComment('ж' * 101), isFalse);
      expect(controller.setAmount(Money.zero), isFalse);
      expect(
        h
            .read(editExpenseControllerProvider(expense.id))
            .changedFields(expense),
        isEmpty,
      );
      final warnings = h.lines('expense', Level.WARNING);
      expect(warnings, hasLength(3));
      expect(warnings[0], contains('date 2026-10-20 by=test rejected: future'));
      expect(warnings[1], contains('comment rejected: comment_too_long'));
      expect(warnings[2], contains('amount rejected: amount_empty'));
      for (final line in warnings) {
        expect(line, isNot(contains('жжж')));
      }

      expect(controller.setComment('  Лента  '), isTrue);
      expect(
        h.read(editExpenseControllerProvider(expense.id)).commentOf(expense),
        'Лента',
      );
      expect(controller.setComment('Лента'), isFalse);
    },
  );

  test('сохранение без изменений ничего не пишет; с изменениями — только '
      'изменённые поля, info с именами полей без значений', () async {
    final (h, expense) = await _start();
    final controller = h.read(
      editExpenseControllerProvider(expense.id).notifier,
    );
    final outbox = (await h.db.select(h.db.outbox).get()).length;

    expect(await controller.save(expense), EditExpenseSave.noChanges);
    expect((await h.db.select(h.db.outbox).get()).length, outbox);

    controller
      ..setAmount(const Money.rubles(1250))
      ..setDate(LocalDate(2026, 10, 18), by: 'test');
    expect(await controller.save(expense), EditExpenseSave.saved);
    expect(
      h.read(editExpenseControllerProvider(expense.id)).changedFields(expense),
      isEmpty,
    );
    final row = await (h.db.select(
      h.db.expenses,
    )..where((e) => e.id.equals(expense.id))).getSingle();
    expect(row.amountKopecks, 125000);
    expect(row.spentOn, LocalDate(2026, 10, 18));
    expect(row.comment, 'Пятёрочка');
    expect(row.categoryId, expense.categoryId);
    expect((await h.db.select(h.db.outbox).get()).length, outbox + 1);

    final info = h.lines('expense', Level.INFO);
    expect(info, hasLength(1));
    expect(
      info.single,
      matches(
        'INFO  \\[expense\\] expense updated id=${expense.id} '
        'budgetId=${expense.budgetId} fields=amount,date in \\d+ms\$',
      ),
    );
    expect(info.single, isNot(contains('1250')));
    expect(info.single, isNot(contains('125000')));
  });

  test('трату удалили до сохранения — missing и warn, в базе надгробие не '
      'тронуто', () async {
    final (h, expense) = await _start();
    final controller = h.read(
      editExpenseControllerProvider(expense.id).notifier,
    );
    await h.read(expensesRepositoryProvider).delete(expense.id);
    controller.setAmount(const Money.rubles(1));

    expect(await controller.save(expense), EditExpenseSave.missing);
    expect(
      h.lines('expense', Level.WARNING).single,
      contains('expense update failed id=${expense.id} fields=amount after'),
    );
    expect(
      h.lines('expense', Level.WARNING).single,
      contains('expense is deleted or missing, nothing saved'),
    );
    final row = await (h.db.select(
      h.db.expenses,
    )..where((e) => e.id.equals(expense.id))).getSingle();
    expect(row.deletedAt, isNotNull);
    expect(row.amountKopecks, 64000);
  });
}
