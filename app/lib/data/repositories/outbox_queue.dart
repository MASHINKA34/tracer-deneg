import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../db/app_database.dart';
import '../db/redact_db_error.dart';

final _log = Logger('repo');

typedef Now = DateTime Function();

final class PendingChange {
  const PendingChange({
    required this.outboxId,
    required this.change,
    required this.createdAt,
    required this.attempts,
    this.notBefore,
    this.lastError,
  });

  final int outboxId;
  final SyncChange change;
  final DateTime createdAt;
  final DateTime? notBefore;
  final int attempts;
  final String? lastError;

  @override
  String toString() =>
      'PendingChange($outboxId ${change.entity.name} ${change.op.name} '
      '${change.id} attempts=$attempts)';
}

abstract interface class OutboxQueue {
  Future<int> enqueueUpsert(SyncRecord record);

  Future<int> enqueueDelete(
    SyncEntity entity,
    String entityId, {
    required DateTime at,
    DateTime? notBefore,
  });

  Future<bool> cancelPendingDelete(
    SyncEntity entity,
    String entityId, {
    required DateTime now,
  });

  Future<List<PendingChange>> pending({int limit = maxPushBatchSize});

  Future<int> remove(Iterable<int> outboxIds);

  Future<int> count();

  Stream<int> watchCount();

  Future<void> reportSize(String reason);
}

final class DriftOutboxQueue implements OutboxQueue {
  DriftOutboxQueue(this._db, {this._now = DateTime.now});

  final AppDatabase _db;
  final Now _now;
  int? _lastSize;

  @override
  Future<int> enqueueUpsert(SyncRecord record) {
    final payload = jsonEncode(record.toJson());
    return _db
        .into(_db.outbox)
        .insert(
          OutboxCompanion.insert(
            entity: record.syncEntity,
            entityId: record.id,
            op: SyncOp.upsert,
            payload: Value(payload),
            createdAt: record.updatedAt,
          ),
        );
  }

  @override
  Future<int> enqueueDelete(
    SyncEntity entity,
    String entityId, {
    required DateTime at,
    DateTime? notBefore,
  }) => _db
      .into(_db.outbox)
      .insert(
        OutboxCompanion.insert(
          entity: entity,
          entityId: entityId,
          op: SyncOp.delete,
          createdAt: normalizeInstant(at),
          notBefore: Value(
            notBefore == null ? null : normalizeInstant(notBefore),
          ),
        ),
      );

  @override
  Future<bool> cancelPendingDelete(
    SyncEntity entity,
    String entityId, {
    required DateTime now,
  }) async {
    final moment = encodeInstant(now);
    final entry =
        await (_db.select(_db.outbox)
              ..where(
                (o) =>
                    o.entity.equalsValue(entity) &
                    o.entityId.equals(entityId) &
                    o.op.equalsValue(SyncOp.delete) &
                    o.notBefore.isBiggerThanValue(moment),
              )
              ..orderBy([(o) => OrderingTerm.desc(o.id)])
              ..limit(1))
            .getSingleOrNull();
    if (entry == null) return false;
    await (_db.delete(_db.outbox)..where((o) => o.id.equals(entry.id))).go();
    return true;
  }

  @override
  Future<List<PendingChange>> pending({int limit = maxPushBatchSize}) async {
    final sw = Stopwatch()..start();
    final moment = encodeInstant(_now());
    try {
      final rows =
          await (_db.select(_db.outbox)
                ..where(
                  (o) =>
                      o.notBefore.isNull() |
                      o.notBefore.isSmallerOrEqualValue(moment),
                )
                ..orderBy([(o) => OrderingTerm.asc(o.id)])
                ..limit(limit))
              .get();
      final changes = [for (final row in rows) _toPending(row)];
      _log.fine(
        'outbox pending taken count=${changes.length} limit=$limit '
        'now=$moment in ${sw.elapsedMilliseconds}ms',
      );
      return changes;
    } catch (e, st) {
      final error = redactDbError(e);
      _log.severe(
        'outbox pending failed limit=$limit now=$moment '
        'after ${sw.elapsedMilliseconds}ms: ${describeError(error)}',
        error,
        st,
      );
      rethrow;
    }
  }

  PendingChange _toPending(OutboxEntry row) {
    try {
      final payload = row.payload;
      final data = payload == null ? null : jsonDecode(payload);
      final updatedAt = data is Map<String, Object?>
          ? data['updatedAt']
          : encodeInstant(row.createdAt);
      return PendingChange(
        outboxId: row.id,
        change: SyncChange.fromJson({
          'entity': row.entity.name,
          'op': row.op.name,
          'id': row.entityId,
          'data': ?data,
          'updatedAt': updatedAt,
        }),
        createdAt: row.createdAt,
        notBefore: row.notBefore,
        attempts: row.attempts,
        lastError: row.lastError,
      );
    } catch (e, st) {
      _log.severe(
        'outbox entry unreadable outboxId=${row.id} entity=${row.entity.name} '
        'id=${row.entityId} op=${row.op.name} '
        'payloadLength=${row.payload?.length ?? 0}: ${describeError(e)}',
        e,
        st,
      );
      rethrow;
    }
  }

  @override
  Future<int> remove(Iterable<int> outboxIds) async {
    final ids = outboxIds.toList();
    final sw = Stopwatch()..start();
    try {
      final removed = await (_db.delete(
        _db.outbox,
      )..where((o) => o.id.isIn(ids))).go();
      _log.fine(
        'outbox remove requested=${ids.length} removed=$removed '
        'in ${sw.elapsedMilliseconds}ms',
      );
      await reportSize('outbox.remove');
      return removed;
    } catch (e, st) {
      final error = redactDbError(e);
      _log.severe(
        'outbox remove failed requested=${ids.length} '
        'after ${sw.elapsedMilliseconds}ms: ${describeError(error)}',
        error,
        st,
      );
      rethrow;
    }
  }

  @override
  Future<int> count() => _db.outbox.count().getSingle();

  @override
  Stream<int> watchCount() => _db.outbox.count().watchSingle();

  @override
  Future<void> reportSize(String reason) async {
    try {
      final size = await count();
      final previous = _lastSize;
      if (previous == size) return;
      _lastSize = size;
      _log.info('outbox size=$size was=${previous ?? '-'} after=$reason');
    } catch (e, st) {
      final error = redactDbError(e);
      _log.warning(
        'outbox size check failed after=$reason: ${describeError(error)}',
        error,
        st,
      );
    }
  }
}
