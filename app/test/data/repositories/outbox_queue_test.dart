import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
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

  Future<Expense> spend() => h.expenses.create(
    budgetId: b.id,
    categoryId: b.byName('Кафе').id,
    amount: const Money.rubles(640),
    spentOn: LocalDate(2026, 10, 20),
  );

  test('очередь отдаёт изменения по порядку как SyncChange для push', () async {
    final expense = await spend();
    h.advance(const Duration(seconds: 1));
    final rule = await h.recurring.create(
      budgetId: b.id,
      categoryId: b.other.id,
      title: 'Связь',
      amount: const Money.rubles(500),
      dayOfMonth: 10,
      startMonth: YearMonth(2026, 11),
    );
    h.advance(const Duration(seconds: 1));
    await h.recurring.delete(rule.id);
    final deletedAt = h.clock;

    final pending = await h.outbox.pending();

    expect(pending.map((p) => p.outboxId), [1, 2, 3]);
    final upsert = pending[0].change;
    expect(upsert.entity, SyncEntity.expense);
    expect(upsert.op, SyncOp.upsert);
    expect(upsert.id, expense.id);
    expect(upsert.updatedAt, expense.updatedAt);
    expect(upsert.decodeRecord(), expense);
    expect(upsert.toJson(), SyncChange.upsert(expense).toJson());

    final delete = pending[2].change;
    expect(
      delete.toJson(),
      SyncChange.delete(
        entity: SyncEntity.recurring,
        id: rule.id,
        updatedAt: deletedAt,
      ).toJson(),
    );
    expect(pending.every((p) => p.attempts == 0), isTrue);
  });

  test('лимит пачки и снятие отправленных записей', () async {
    for (var i = 0; i < 5; i++) {
      await spend();
    }
    final first = await h.outbox.pending(limit: 2);
    expect(first.map((p) => p.outboxId), [1, 2]);

    expect(await h.outbox.remove(first.map((p) => p.outboxId)), 2);

    expect((await h.outbox.pending()).map((p) => p.outboxId), [3, 4, 5]);
    expect(await h.outbox.count(), 3);
  });

  test('размер очереди: info только когда меняется', () async {
    h.records.clear();
    await spend();
    await spend();
    await h.expenses.undoDelete('missing');
    await h.expenses.applyFromServer(const []);
    await h.outbox.remove([1, 2]);
    await h.outbox.remove([1, 2]);

    final sizes = [
      for (final r in h.repoLogs(Level.INFO))
        if (r.message.startsWith('outbox size')) r.message,
    ];
    expect(sizes, [
      'outbox size=1 was=0 after=expense.create',
      'outbox size=2 was=1 after=expense.create',
      'outbox size=0 was=2 after=outbox.remove',
    ]);
  });

  test('watchCount отдаёт размер очереди после каждого изменения', () async {
    final counts = <int>[];
    final sub = h.outbox.watchCount().listen(counts.add);
    await pumpEventQueue();
    final expense = await spend();
    await pumpEventQueue();
    await h.expenses.delete(expense.id);
    await pumpEventQueue();
    await h.expenses.undoDelete(expense.id);
    await pumpEventQueue();
    await sub.cancel();
    expect(counts, [0, 1, 2, 1]);
  });
}
