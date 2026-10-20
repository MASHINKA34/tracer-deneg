import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/repositories/expenses_repository.dart';
import 'package:shared/shared.dart';

import 'repository_harness.dart';

void main() {
  late RepositoryHarness h;
  late SeededBudget b;

  setUp(() async {
    h = RepositoryHarness();
    b = await h.seedBudget();
  });

  tearDown(() => h.dispose());

  Future<Expense> create() => h.expenses.create(
    budgetId: b.id,
    categoryId: b.byName('Кафе').id,
    amount: const Money.rubles(640),
    spentOn: LocalDate(2026, 10, 20),
  );

  List<String> undoLogs() => [
    for (final r in h.repoLogs(Level.INFO))
      if (r.message.startsWith('expense undo delete')) r.message,
  ];

  test('окно отмены — 5 секунд', () {
    expect(expenseUndoWindow, const Duration(seconds: 5));
  });

  test(
    'отмена через 4,999 с: трата на месте, снята именно запись delete',
    () async {
      final expense = await create();
      await h.expenses.delete(expense.id);
      h.advance(const Duration(seconds: 4, milliseconds: 999));

      expect(await h.expenses.undoDelete(expense.id), isTrue);

      final restored = await h.expenses.watchById(expense.id).first;
      expect(restored, isNotNull);
      expect(restored!.deletedAt, isNull);
      expect(restored.amount, expense.amount);
      expect(restored.updatedAt, h.clock);
      expect(restored.updatedBy, meId);

      final rows = await h.outboxRows();
      expect(rows, hasLength(1));
      expect(rows.single.op, SyncOp.upsert);
      expect(payloadOf(rows.single), expense.toJson());
      expect(undoLogs(), [
        'expense undo delete id=${expense.id} undone=true reason=in-window',
      ]);
    },
  );

  test('ровно через 5 с отмена не срабатывает: трата удалена, очередь та же', () async {
    final expense = await create();
    await h.expenses.delete(expense.id);
    final before = await h.outboxRows();
    h.advance(expenseUndoWindow);

    expect(await h.expenses.undoDelete(expense.id), isFalse);

    expect(await h.expenses.watchById(expense.id).first, isNull);
    final stored = await h.db.select(h.db.expenses).getSingle();
    expect(stored.deletedAt, isNotNull);
    final after = await h.outboxRows();
    expect(after.map((r) => r.id), before.map((r) => r.id));
    expect(after.last.op, SyncOp.delete);
    expect(undoLogs(), [
      'expense undo delete id=${expense.id} undone=false reason=window-expired',
    ]);
  });

  test('через минуту отмена тоже ничего не делает', () async {
    final expense = await create();
    await h.expenses.delete(expense.id);
    h.advance(const Duration(minutes: 1));

    expect(await h.expenses.undoDelete(expense.id), isFalse);
    expect(await h.expenses.watchById(expense.id).first, isNull);
    expect((await h.outboxRows()).map((r) => r.op), [
      SyncOp.upsert,
      SyncOp.delete,
    ]);
  });

  test('отмена снимает только запись удаления этой траты', () async {
    final first = await create();
    final second = await create();
    await h.expenses.delete(first.id);
    await h.expenses.delete(second.id);
    h.advance(const Duration(seconds: 1));

    expect(await h.expenses.undoDelete(first.id), isTrue);

    final rows = await h.outboxRows();
    expect(
      [for (final r in rows) '${r.op.name}:${r.entityId}'],
      ['upsert:${first.id}', 'upsert:${second.id}', 'delete:${second.id}'],
    );
    expect(await h.expenses.watchById(second.id).first, isNull);
  });

  test('отмена живой или неизвестной траты возвращает false', () async {
    final expense = await create();
    expect(await h.expenses.undoDelete(expense.id), isFalse);
    expect(await h.expenses.undoDelete('missing'), isFalse);
    expect(undoLogs(), [
      'expense undo delete id=${expense.id} undone=false reason=not-deleted',
      'expense undo delete id=missing undone=false reason=not-found',
    ]);
    expect(await h.outboxRows(), hasLength(1));
  });

  test(
    'отложенное удаление не уходит в очередь отправки до конца окна',
    () async {
      final expense = await create();
      await h.expenses.delete(expense.id);

      final early = await h.outbox.pending();
      expect(early.map((p) => p.change.op), [SyncOp.upsert]);

      h.advance(expenseUndoWindow);
      final ready = await h.outbox.pending();
      expect(ready.map((p) => p.change.op), [SyncOp.upsert, SyncOp.delete]);
      expect(ready.last.change.id, expense.id);
    },
  );

  test(
    'запись удаления уже снята из очереди — отмена не срабатывает',
    () async {
      final expense = await create();
      await h.expenses.delete(expense.id);
      final rows = await h.outboxRows();
      await h.outbox.remove(rows.map((r) => r.id));
      h.advance(const Duration(seconds: 1));

      expect(await h.expenses.undoDelete(expense.id), isFalse);
      expect(await h.expenses.watchById(expense.id).first, isNull);
    },
  );
}
