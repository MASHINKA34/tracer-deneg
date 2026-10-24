import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../api/api_exception.dart';
import '../api/sync_api.dart';
import '../db/redact_db_error.dart';
import '../repositories/outbox_queue.dart';
import 'sync_engine.dart';

final _log = Logger('sync');

sealed class SyncNowResult {
  const SyncNowResult({
    required this.applied,
    required this.rejected,
    required this.batches,
  });

  final int applied;
  final int rejected;
  final int batches;
}

final class SyncNowDone extends SyncNowResult {
  const SyncNowDone({
    required super.applied,
    required super.rejected,
    required super.batches,
  });

  @override
  String toString() =>
      'SyncNowDone(applied=$applied rejected=$rejected batches=$batches)';
}

final class SyncNowFailed extends SyncNowResult {
  const SyncNowFailed({
    required this.remaining,
    required super.applied,
    required super.rejected,
    required super.batches,
    this.error,
  });

  final int remaining;
  final Object? error;

  String get description => switch (error) {
    null => 'changes still waiting',
    final ApiException e => '${e.runtimeType}: ${e.details}',
    final Object e => describeError(e),
  };

  @override
  String toString() =>
      'SyncNowFailed(remaining=$remaining $description '
      'applied=$applied rejected=$rejected batches=$batches)';
}

abstract interface class SyncService {
  Future<SyncNowResult> syncNow();
}

final class PushOnceSyncService implements SyncService {
  PushOnceSyncService({
    required this._api,
    required this._outbox,
    String Function()? newBatchId,
  }) : _newBatchId = newBatchId ?? _defaultBatchId;

  static String _defaultBatchId() => newId();

  final SyncApi _api;
  final OutboxQueue _outbox;
  final String Function() _newBatchId;
  Future<SyncNowResult>? _running;

  @override
  Future<SyncNowResult> syncNow() {
    final running = _running;
    if (running != null) {
      _log.fine('sync now joins the push attempt already running');
      return running;
    }
    final future = _run();
    _running = future;
    return future.whenComplete(() {
      if (identical(_running, future)) _running = null;
    });
  }

  Future<SyncNowResult> _run() async {
    final sw = Stopwatch()..start();
    var applied = 0;
    var rejected = 0;
    var batches = 0;
    int? before;
    try {
      before = await _outbox.count();
      _log.info(
        'sync now: one push attempt queue=$before '
        'batch up to $maxPushBatchSize',
      );
      while (true) {
        final pending = await _outbox.pending();
        if (pending.isEmpty) break;
        final batch = batches + 1;
        final answered = await _pushBatch(batch, pending);
        batches = batch;
        applied += answered.applied;
        rejected += answered.rejected;
        if (answered.removed == 0) {
          _log.warning(
            'push batch=$batch removed nothing from the queue '
            '(server answered none of ${pending.length} changes) → stopping '
            'this attempt',
          );
          break;
        }
      }
      final remaining = await _outbox.count();
      if (remaining == 0) {
        _log.info(
          'sync now done applied=$applied rejected=$rejected '
          'batches=$batches queue=$before→0 in ${sw.elapsedMilliseconds}ms',
        );
        return SyncNowDone(
          applied: applied,
          rejected: rejected,
          batches: batches,
        );
      }
      _log.warning(
        'sync now incomplete applied=$applied rejected=$rejected '
        'batches=$batches queue=$before→$remaining: the rest is not due yet '
        '(delete in its undo window) or was not answered, '
        'in ${sw.elapsedMilliseconds}ms',
      );
      return SyncNowFailed(
        remaining: remaining,
        applied: applied,
        rejected: rejected,
        batches: batches,
      );
    } catch (e, st) {
      final error = e is ApiException ? e : redactDbError(e);
      final expected = switch (error) {
        ApiNetworkFailure() || ApiTimeout() || ApiSessionExpired() => true,
        _ => false,
      };
      final remaining = await _remaining();
      final failed = SyncNowFailed(
        remaining: remaining ?? before ?? -1,
        applied: applied,
        rejected: rejected,
        batches: batches,
        error: error,
      );
      _log.log(
        expected ? Level.WARNING : Level.SEVERE,
        'sync now failed at batch=${batches + 1} ${failed.description} '
        'rid=${error is ApiException ? error.requestId ?? '-' : '-'} '
        'applied=$applied rejected=$rejected '
        'queue=${before ?? '?'}→${remaining ?? '?'} '
        'after ${sw.elapsedMilliseconds}ms → changes kept in the queue',
        error,
        st,
      );
      return failed;
    }
  }

  Future<({int applied, int rejected, int removed})> _pushBatch(
    int batch,
    List<PendingChange> pending,
  ) async {
    final sw = Stopwatch()..start();
    final request = SyncPushRequest(
      batchId: _newBatchId(),
      changes: [for (final p in pending) p.change],
    );
    _log.fine(
      'push batch=$batch batchId=${request.batchId} '
      'changes=${request.changes.length} ${_entities(pending)}',
    );
    final reply = await _api.push(request);
    final response = reply.response;
    for (final rejection in response.rejected) {
      final entity = pending
          .where((p) => p.change.id == rejection.id)
          .map((p) => p.change.entity.name)
          .toSet()
          .join(',');
      _log.warning(
        'push change rejected entity=${entity.isEmpty ? '?' : entity} '
        'id=${rejection.id} code=${rejection.code} batchId=${request.batchId} '
        '→ dropped from the queue rid=${reply.requestId}',
      );
    }
    final answeredIds = {
      ...response.applied,
      for (final r in response.rejected) r.id,
    };
    final answered = [
      for (final p in pending)
        if (answeredIds.contains(p.change.id)) p.outboxId,
    ];
    final missing = pending.length - answered.length;
    if (missing > 0) {
      _log.warning(
        'push batch=$batch batchId=${request.batchId}: $missing change(s) '
        'not in applied or rejected → kept in the queue rid=${reply.requestId}',
      );
    }
    final removed = answered.isEmpty ? 0 : await _outbox.remove(answered);
    _log.info(
      'push batch=$batch batchId=${request.batchId} '
      'changes=${request.changes.length} applied=${response.applied.length} '
      'rejected=${response.rejected.length} '
      'codes=${_codes(response.rejected)} removed=$removed '
      'cursor=${response.cursor} rid=${reply.requestId} '
      'in ${sw.elapsedMilliseconds}ms',
    );
    return (
      applied: response.applied.length,
      rejected: response.rejected.length,
      removed: removed,
    );
  }

  Future<int?> _remaining() async {
    try {
      return await _outbox.count();
    } catch (e, st) {
      final error = redactDbError(e);
      _log.warning(
        'sync now: queue size unknown after the failure: '
        '${describeError(error)}',
        error,
        st,
      );
      return null;
    }
  }
}

String _entities(List<PendingChange> pending) {
  final counts = <String, int>{};
  for (final p in pending) {
    final key = '${p.change.entity.name}.${p.change.op.name}';
    counts[key] = (counts[key] ?? 0) + 1;
  }
  return [for (final e in counts.entries) '${e.key}=${e.value}'].join(' ');
}

String _codes(List<SyncRejection> rejected) {
  if (rejected.isEmpty) return '-';
  final counts = <String, int>{};
  for (final r in rejected) {
    counts[r.code] = (counts[r.code] ?? 0) + 1;
  }
  return [for (final e in counts.entries) '${e.key}:${e.value}'].join(',');
}

final syncServiceProvider = Provider<SyncService>(
  (ref) => ref.watch(syncEngineProvider),
  name: 'syncService',
);
