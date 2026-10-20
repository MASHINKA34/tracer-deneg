import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:shared/shared.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.memory());
  tearDown(() => db.close());

  final now = DateTime.utc(2026, 10, 20, 9);

  Future<int> enqueue(String entityId, {SyncOp op = SyncOp.upsert}) => db
      .into(db.outbox)
      .insert(
        OutboxCompanion.insert(
          entity: SyncEntity.expense,
          entityId: entityId,
          op: op,
          payload: Value(op == SyncOp.upsert ? '{"id":"$entityId"}' : null),
          createdAt: now,
        ),
      );

  test('id растёт по порядку вставки', () async {
    final ids = [
      for (final e in ['e3', 'e1', 'e2', 'e1']) await enqueue(e),
    ];
    expect(ids, [1, 2, 3, 4]);
    final rows = await (db.select(
      db.outbox,
    )..orderBy([(o) => OrderingTerm.asc(o.id)])).get();
    expect(rows.map((r) => r.entityId), ['e3', 'e1', 'e2', 'e1']);
  });

  test('id не переиспользуется после снятия записей из очереди', () async {
    await enqueue('e1');
    await enqueue('e2');
    await db.delete(db.outbox).go();
    expect(await enqueue('e3'), 3);
  });

  test('значения по умолчанию новой записи', () async {
    await enqueue('e1', op: SyncOp.delete);
    final row = await db.select(db.outbox).getSingle();
    expect(row.entity, SyncEntity.expense);
    expect(row.op, SyncOp.delete);
    expect(row.payload, isNull);
    expect(row.createdAt, now);
    expect(row.notBefore, isNull);
    expect(row.attempts, 0);
    expect(row.lastError, isNull);
  });
}
