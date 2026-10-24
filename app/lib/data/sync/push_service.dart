import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../api/api_exception.dart';
import '../api/sync_api.dart';
import '../db/redact_db_error.dart';
import '../repositories/outbox_queue.dart';
import 'pull_service.dart';

final _log = Logger('sync');

final class PushRejected {
  const PushRejected({
    required this.entity,
    required this.id,
    required this.code,
  });

  final SyncEntity entity;
  final String id;
  final String code;

  RejectedEntity get target => (entity: entity, id: id);

  @override
  String toString() => 'PushRejected(${entity.name} $id $code)';
}

final class PushOutcome {
  const PushOutcome({
    required this.sent,
    required this.applied,
    required this.rejected,
    required this.batches,
    required this.remaining,
    required this.elapsed,
  });

  final int sent;
  final int applied;
  final List<PushRejected> rejected;
  final int batches;
  final int remaining;
  final Duration elapsed;

  @override
  String toString() =>
      'PushOutcome(sent=$sent applied=$applied rejected=${rejected.length} '
      'batches=$batches remaining=$remaining '
      'in ${elapsed.inMilliseconds}ms)';
}

final class PushFailure implements Exception {
  const PushFailure({
    required this.error,
    required this.batch,
    required this.applied,
    required this.rejected,
    required this.batches,
    this.batchId,
    this.requestId,
  });

  final Object error;
  final int batch;
  final String? batchId;
  final String? requestId;
  final int applied;
  final List<PushRejected> rejected;
  final int batches;

  String get description => switch (error) {
    final ApiException e => '${e.runtimeType}: ${e.details}',
    final Object e => describeError(e),
  };

  @override
  String toString() =>
      'PushFailure(batch=$batch batchId=${batchId ?? '-'} $description '
      'rid=${requestId ?? '-'} applied=$applied rejected=${rejected.length})';
}

bool keepsBatchForRetry(Object error) => switch (error) {
  ApiNetworkFailure() ||
  ApiTimeout() ||
  ApiServerFailure() ||
  ApiSessionExpired() => true,
  ApiErrorResponse(:final statusCode) => statusCode == 429,
  _ => false,
};

final class _InFlight {
  _InFlight(this.request, this.pending);

  final SyncPushRequest request;
  final List<PendingChange> pending;
  int sends = 1;
}

class PushService {
  PushService({
    required this._api,
    required this._outbox,
    String Function()? newBatchId,
  }) : _newBatchId = newBatchId ?? newId;

  final SyncApi Function() _api;
  final OutboxQueue Function() _outbox;
  final String Function() _newBatchId;
  _InFlight? _inflight;

  String? get inflightBatchId => _inflight?.request.batchId;

  void forget(String why) {
    final inflight = _inflight;
    if (inflight == null) return;
    _inflight = null;
    _log.info(
      'push batch batchId=${inflight.request.batchId} '
      'changes=${inflight.request.changes.length} forgotten: $why → the '
      'next push builds a new batch',
    );
  }

  Future<PushOutcome> push(String trigger) async {
    final sw = Stopwatch()..start();
    final outbox = _outbox();
    var sent = 0;
    var applied = 0;
    var batches = 0;
    final rejected = <PushRejected>[];
    while (true) {
      final batch = batches + 1;
      final List<PendingChange> due;
      try {
        due = await outbox.pending();
      } catch (e, st) {
        final error = redactDbError(e);
        _log.severe(
          'push trigger=$trigger batch=$batch: queue not read '
          'after ${sw.elapsedMilliseconds}ms: ${describeError(error)}',
          error,
          st,
        );
        throw PushFailure(
          error: error,
          batch: batch,
          applied: applied,
          rejected: List.unmodifiable(rejected),
          batches: batches,
        );
      }
      if (due.isEmpty) break;
      final inflight = _batchFor(due, batch, trigger);
      final request = inflight.request;
      final batchSw = Stopwatch()..start();
      final reply = await _send(inflight, batch, trigger, (
        applied: applied,
        rejected: rejected,
        batches: batches,
      ));
      _inflight = null;
      final answered = await _answer(inflight, reply, batch, batchSw);
      batches = batch;
      sent += request.changes.length;
      applied += reply.response.applied.length;
      rejected.addAll(answered.rejected);
      if (answered.removed == 0) {
        _log.warning(
          'push batch=$batch batchId=${request.batchId} removed nothing from '
          'the queue (server answered none of ${request.changes.length} '
          'changes) → stopping this push rid=${reply.requestId}',
        );
        break;
      }
    }
    final int remaining;
    try {
      remaining = await outbox.count();
    } catch (e, st) {
      final error = redactDbError(e);
      _log.severe(
        'push trigger=$trigger: queue size not read after '
        '${sw.elapsedMilliseconds}ms: ${describeError(error)}',
        error,
        st,
      );
      throw PushFailure(
        error: error,
        batch: batches + 1,
        applied: applied,
        rejected: List.unmodifiable(rejected),
        batches: batches,
      );
    }
    final outcome = PushOutcome(
      sent: sent,
      applied: applied,
      rejected: List.unmodifiable(rejected),
      batches: batches,
      remaining: remaining,
      elapsed: sw.elapsed,
    );
    _log.fine('push trigger=$trigger finished $outcome');
    return outcome;
  }

  _InFlight _batchFor(List<PendingChange> due, int batch, String trigger) {
    final inflight = _inflight;
    if (inflight != null) {
      final present = {for (final p in due) p.outboxId};
      final missing = inflight.pending
          .where((p) => !present.contains(p.outboxId))
          .length;
      if (missing == 0) {
        inflight.sends++;
        _log.info(
          'push batch=$batch trigger=$trigger resends batchId='
          '${inflight.request.batchId} changes=${inflight.request.changes.length} '
          'send=${inflight.sends}: the previous send broke off without an '
          'answer → the server answers a known batch with its stored result',
        );
        return inflight;
      }
      _log.warning(
        'push batch=$batch trigger=$trigger: unanswered batchId='
        '${inflight.request.batchId} dropped, $missing of '
        '${inflight.pending.length} changes left the queue meanwhile '
        '(budget removed or data cleared) → new batch',
      );
      _inflight = null;
    }
    final fresh = _InFlight(
      SyncPushRequest(
        batchId: _newBatchId(),
        changes: [for (final p in due) p.change],
      ),
      due,
    );
    _inflight = fresh;
    _log.fine(
      'push batch=$batch trigger=$trigger batchId=${fresh.request.batchId} '
      'changes=${due.length} ${_entities(due)}',
    );
    return fresh;
  }

  Future<PushReply> _send(
    _InFlight inflight,
    int batch,
    String trigger,
    ({int applied, List<PushRejected> rejected, int batches}) progress,
  ) async {
    final request = inflight.request;
    final started = Stopwatch()..start();
    try {
      return await _api().push(request);
    } on ApiException catch (e, st) {
      final keep = keepsBatchForRetry(e);
      if (!keep) _inflight = null;
      final expected = switch (e) {
        ApiNetworkFailure() || ApiTimeout() || ApiSessionExpired() => true,
        _ => false,
      };
      _log.log(
        expected ? Level.WARNING : Level.SEVERE,
        'push batch=$batch trigger=$trigger batchId=${request.batchId} '
        'changes=${request.changes.length} failed ${e.runtimeType}: '
        '${e.details} rid=${e.requestId ?? '-'} '
        'after ${started.elapsedMilliseconds}ms → '
        '${keep ? 'same batchId on the next send' : 'batch forgotten'}, '
        'changes kept in the queue',
        e,
        st,
      );
      throw PushFailure(
        error: e,
        batch: batch,
        batchId: request.batchId,
        requestId: e.requestId,
        applied: progress.applied,
        rejected: List.unmodifiable(progress.rejected),
        batches: progress.batches,
      );
    }
  }

  Future<({int removed, List<PushRejected> rejected})> _answer(
    _InFlight inflight,
    PushReply reply,
    int batch,
    Stopwatch sw,
  ) async {
    final started = Stopwatch()..start();
    final request = inflight.request;
    final response = reply.response;
    final rejected = <PushRejected>[];
    for (final rejection in response.rejected) {
      final entities = {
        for (final p in inflight.pending)
          if (p.change.id == rejection.id) p.change.entity,
      };
      for (final entity in entities) {
        rejected.add(
          PushRejected(entity: entity, id: rejection.id, code: rejection.code),
        );
      }
      _log.warning(
        'push change rejected '
        'entity=${entities.isEmpty ? '?' : entities.map((e) => e.name).join(',')} '
        'id=${rejection.id} code=${rejection.code} batchId=${request.batchId} '
        '→ dropped from the queue, re-read from the server '
        'rid=${reply.requestId}',
      );
    }
    final answeredIds = {
      ...response.applied,
      for (final r in response.rejected) r.id,
    };
    final answered = [
      for (final p in inflight.pending)
        if (answeredIds.contains(p.change.id)) p.outboxId,
    ];
    final missing = inflight.pending.length - answered.length;
    if (missing > 0) {
      _log.warning(
        'push batch=$batch batchId=${request.batchId}: $missing change(s) '
        'not in applied or rejected → kept in the queue rid=${reply.requestId}',
      );
    }
    final int removed;
    try {
      removed = answered.isEmpty ? 0 : await _outbox().remove(answered);
    } catch (e, st) {
      final error = redactDbError(e);
      _log.severe(
        'push batch=$batch batchId=${request.batchId}: server answered, but '
        'the answered changes were not removed from the queue: '
        '${describeError(error)} → the next push sends them again with a new '
        'batchId, the server keeps the same result',
        error,
        st,
      );
      throw PushFailure(
        error: error,
        batch: batch,
        batchId: request.batchId,
        requestId: reply.requestId,
        applied: 0,
        rejected: List.unmodifiable(rejected),
        batches: batch - 1,
      );
    }
    _log.info(
      'push batch=$batch batchId=${request.batchId} '
      'changes=${request.changes.length} applied=${response.applied.length} '
      'rejected=${response.rejected.length} '
      'codes=${_codes(response.rejected)} removed=$removed '
      'cursor=${response.cursor} rid=${reply.requestId} '
      'in ${sw.elapsedMilliseconds}ms (answer applied in '
      '${started.elapsedMilliseconds}ms)',
    );
    return (removed: removed, rejected: rejected);
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
