import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../core/clock.dart';
import '../api/api_exception.dart';
import '../api/sync_api.dart';
import '../db/redact_db_error.dart';
import '../providers.dart';
import '../repositories/outbox_queue.dart';
import '../session/session_providers.dart';
import '../session/session_state.dart';
import 'budget_removed_notice.dart';
import 'pull_controller.dart';
import 'pull_service.dart';
import 'push_service.dart';
import 'sync_service.dart';

final _log = Logger('sync');

const Duration syncRetryFirst = Duration(seconds: 2);

const Duration syncRetryMax = Duration(seconds: 300);

const double syncRetryJitter = 0.2;

Duration syncRetryDelay(int attempt, double random) {
  final step = math.min(math.max(attempt, 1), 20) - 1;
  final base = math.min(
    syncRetryFirst.inMilliseconds * math.pow(2, step),
    syncRetryMax.inMilliseconds.toDouble(),
  );
  final factor = 1 - syncRetryJitter + 2 * syncRetryJitter * random;
  final ms = (base * factor).round();
  return Duration(milliseconds: math.min(ms, syncRetryMax.inMilliseconds));
}

typedef StartTimer = Timer Function(Duration delay, void Function() callback);

typedef BudgetRemovedListener = void Function(
  RemovedBudget budget,
  BudgetRemovalKind kind,
);

Timer _realTimer(Duration delay, void Function() callback) =>
    Timer(delay, callback);

enum SyncReason {
  manual,
  retry,
  startup,
  resume,
  network,
  outbox,
  periodic,
  websocket,
}

enum SyncPhase { idle, sending, waitingNetwork, error }

enum SyncStage { push, pull }

enum _Failure { network, transient, session, fatal }

final class SyncEngineState {
  const SyncEngineState({
    this.phase = SyncPhase.idle,
    this.queueSize = 0,
    this.lastSyncAt,
    this.lastError,
    this.retryAt,
    this.failures = 0,
  });

  final SyncPhase phase;
  final int queueSize;
  final DateTime? lastSyncAt;
  final String? lastError;
  final DateTime? retryAt;
  final int failures;

  SyncEngineState copyWith({
    SyncPhase? phase,
    int? queueSize,
    Object? lastSyncAt = keep,
    Object? lastError = keep,
    Object? retryAt = keep,
    int? failures,
  }) => SyncEngineState(
    phase: phase ?? this.phase,
    queueSize: queueSize ?? this.queueSize,
    lastSyncAt: identical(lastSyncAt, keep)
        ? this.lastSyncAt
        : lastSyncAt as DateTime?,
    lastError: identical(lastError, keep)
        ? this.lastError
        : lastError as String?,
    retryAt: identical(retryAt, keep) ? this.retryAt : retryAt as DateTime?,
    failures: failures ?? this.failures,
  );

  @override
  bool operator ==(Object other) =>
      other is SyncEngineState &&
      other.phase == phase &&
      other.queueSize == queueSize &&
      other.lastSyncAt == lastSyncAt &&
      other.lastError == lastError &&
      other.retryAt == retryAt &&
      other.failures == failures;

  @override
  int get hashCode =>
      Object.hash(phase, queueSize, lastSyncAt, lastError, retryAt, failures);

  @override
  String toString() =>
      'SyncEngineState(${phase.name} queue=$queueSize '
      'lastSyncAt=${lastSyncAt == null ? '-' : encodeInstant(lastSyncAt!)} '
      'failures=$failures '
      'retryAt=${retryAt == null ? '-' : encodeInstant(retryAt!)}'
      '${lastError == null ? '' : ' lastError=$lastError'})';
}

sealed class SyncCycleResult {
  const SyncCycleResult({required this.reason, required this.elapsed});

  final SyncReason reason;
  final Duration elapsed;
}

final class SyncCycleDone extends SyncCycleResult {
  const SyncCycleDone({
    required super.reason,
    required super.elapsed,
    required this.push,
    required this.pull,
  });

  final PushOutcome push;
  final PullResult pull;

  @override
  String toString() =>
      'SyncCycleDone(${reason.name} $push $pull in ${elapsed.inMilliseconds}ms)';
}

final class SyncCycleFailed extends SyncCycleResult {
  const SyncCycleFailed({
    required super.reason,
    required super.elapsed,
    required this.stage,
    required this.error,
    required this.attempt,
    this.retryIn,
    this.push,
    this.pullFailure,
  });

  final SyncStage stage;
  final Object error;
  final int attempt;
  final Duration? retryIn;
  final PushOutcome? push;
  final PullFailure? pullFailure;

  @override
  String toString() =>
      'SyncCycleFailed(${reason.name} ${stage.name} attempt=$attempt '
      '${_describe(error)} retryIn=${retryIn?.inMilliseconds ?? '-'}ms)';
}

final class SyncCycleSkipped extends SyncCycleResult {
  const SyncCycleSkipped({
    required super.reason,
    required super.elapsed,
    required this.why,
  });

  final String why;

  @override
  String toString() => 'SyncCycleSkipped(${reason.name} $why)';
}

final class SyncHeld implements Exception {
  const SyncHeld(this.why);

  final String why;

  @override
  String toString() => 'SyncHeld: $why';
}

final class _QueuedCycle {
  _QueuedCycle(this.reason);

  final SyncReason reason;
  final List<SyncReason> joined = [];
  late final Future<SyncCycleResult> future;
}

class SyncEngine implements SyncService {
  SyncEngine({
    required this._api,
    required this._outbox,
    required this._pullService,
    required this._signedInUserId,
    this._selectedBudgetId,
    this._onNotice,
    this._watchLastSyncAt,
    this._now = DateTime.now,
    math.Random? random,
    StartTimer? startTimer,
    String Function()? newBatchId,
  }) : _random = random ?? math.Random(),
       _startTimer = startTimer ?? _realTimer {
    _push = PushService(api: _api, outbox: _outbox, newBatchId: newBatchId);
  }

  final SyncApi Function() _api;
  final OutboxQueue Function() _outbox;
  final PullService Function() _pullService;
  final String? Function() _signedInUserId;
  final SelectedBudgetReader? _selectedBudgetId;
  final BudgetRemovedListener? _onNotice;
  final Stream<DateTime?> Function()? _watchLastSyncAt;
  final DateTime Function() _now;
  final math.Random _random;
  final StartTimer _startTimer;
  late final PushService _push;

  late final StreamController<SyncEngineState> _states =
      StreamController<SyncEngineState>.broadcast(
        onListen: _watch,
        onCancel: _unwatch,
      );
  SyncEngineState _state = const SyncEngineState();
  StreamSubscription<int>? _queueWatch;
  StreamSubscription<DateTime?>? _lastSyncWatch;

  Future<void> _tail = Future<void>.value();
  String? _running;
  _QueuedCycle? _queued;
  Future<SyncNowResult>? _syncNow;
  Timer? _retryTimer;
  int _failures = 0;
  int? _reread;
  String? _heldBy;
  bool _disposed = false;

  SyncEngineState get state => _state;

  Stream<SyncEngineState> get states => _states.stream;

  bool get isRunning => _running != null;

  String? get heldBy => _heldBy;

  bool get retryScheduled => _retryTimer != null;

  Future<void> whenIdle() => _tail;

  Future<SyncCycleResult> sync(SyncReason reason) {
    final queued = _queued;
    if (queued != null) {
      queued.joined.add(reason);
      _log.fine(
        'sync reason=${reason.name} joins the cycle queued for '
        'reason=${queued.reason.name}',
      );
      return queued.future;
    }
    final cycle = _QueuedCycle(reason);
    _queued = cycle;
    final running = _running;
    if (running != null) {
      _log.fine(
        'sync reason=${reason.name} requested while $running runs → one '
        'more cycle after it',
      );
    }
    cycle.future = _exclusive('cycle ${reason.name}', () {
      if (identical(_queued, cycle)) _queued = null;
      return _cycle(cycle);
    });
    return cycle.future;
  }

  @override
  Future<SyncNowResult> syncNow() {
    final running = _syncNow;
    if (running != null) {
      _log.fine('sync now joins the push already queued in the sync engine');
      return running;
    }
    final future = _exclusive('sync now', _pushOnly);
    _syncNow = future;
    future.whenComplete(() {
      if (identical(_syncNow, future)) _syncNow = null;
    }).ignore();
    return future;
  }

  Future<PullResult?> pullNow(PullReason reason, {int attempt = 1}) {
    final running = _running;
    if (running != null) {
      _log.fine(
        'pull reason=${reason.name} waits for $running in the sync engine',
      );
    }
    return _exclusive('pull ${reason.name}', () => _pullOnly(reason, attempt));
  }

  Future<void> hold(String why) async {
    final sw = Stopwatch()..start();
    _heldBy = why;
    final cancelled = _cancelRetry();
    final running = _running;
    _log.info(
      'sync held by $why: retry timer ${cancelled ? 'cancelled' : 'none'}, '
      'running=${running ?? '-'} queuedCycle=${_queued != null} → waiting '
      'until the engine is idle',
    );
    await _tail;
    _setState(_state.copyWith(retryAt: null));
    _log.info(
      'sync held by $why: engine idle after ${sw.elapsedMilliseconds}ms, '
      'new runs are skipped until the session changes',
    );
  }

  void release(String why) {
    final held = _heldBy;
    if (held == null) return;
    _heldBy = null;
    _log.info('sync hold by $held released: $why');
  }

  void sessionChanged(SessionState? previous, SessionState next) {
    final before = previous?.userId;
    final after = next.userId;
    final cancelled = _cancelRetry();
    _failures = 0;
    if (before != after) {
      _push.forget('session user changed ${before ?? '-'}→${after ?? '-'}');
      _reread = null;
    }
    _log.fine(
      'sync engine sees session ${previous?.name ?? '-'}→${next.name} '
      'userId=${after ?? '-'}: retry timer '
      '${cancelled ? 'cancelled' : 'none'}, failures reset',
    );
    release('session ${previous?.name ?? '-'}→${next.name}');
    _setState(
      _state.copyWith(
        phase: SyncPhase.idle,
        retryAt: null,
        failures: 0,
        lastError: null,
      ),
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final cancelled = _cancelRetry();
    _unwatch();
    unawaited(_states.close());
    _log.fine(
      'sync engine disposed running=${_running ?? '-'} retry timer '
      '${cancelled ? 'cancelled' : 'none'}',
    );
  }

  Future<T> _exclusive<T>(String what, Future<T> Function() body) {
    final run = _tail.then((_) async {
      _running = what;
      try {
        return await body();
      } finally {
        _running = null;
      }
    });
    _tail = run.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return run;
  }

  String? _blocked({bool needsSession = true}) {
    if (_disposed) return 'engine disposed';
    final held = _heldBy;
    if (held != null) return 'held by $held';
    if (needsSession && _signedInUserId() == null) return 'no active session';
    return null;
  }

  Future<SyncCycleResult> _cycle(_QueuedCycle cycle) async {
    final reason = cycle.reason;
    final sw = Stopwatch()..start();
    final blocked = _blocked();
    if (blocked != null) {
      _log.info('sync cycle skipped reason=${reason.name}: $blocked');
      return SyncCycleSkipped(
        reason: reason,
        elapsed: sw.elapsed,
        why: blocked,
      );
    }
    if (_cancelRetry()) {
      _log.fine(
        'sync cycle reason=${reason.name} starts before the retry timer → '
        'timer cancelled',
      );
    }
    final attempt = _failures + 1;
    final queue = await _queueSize();
    final joined = cycle.joined.isEmpty
        ? ''
        : ' joined=[${cycle.joined.map((r) => r.name).join(',')}]';
    _log.info(
      'sync cycle start reason=${reason.name}$joined attempt=$attempt '
      'queue=${queue ?? '?'}',
    );
    _setState(
      _state.copyWith(
        phase: SyncPhase.sending,
        queueSize: queue,
        retryAt: null,
      ),
    );

    final PushOutcome push;
    try {
      push = await _push.push(reason.name);
    } on PushFailure catch (f) {
      await _rememberRejected(f.rejected);
      return _cycleFailed(
        reason,
        SyncStage.push,
        f.error,
        attempt,
        sw,
        requestId: f.requestId,
        detail: 'batch=${f.batch} batchId=${f.batchId ?? '-'}',
      );
    } catch (e, st) {
      final error = redactDbError(e);
      _log.severe(
        'sync cycle reason=${reason.name}: push crashed before it could '
        'report: ${describeError(error)}',
        error,
        st,
      );
      return _cycleFailed(reason, SyncStage.push, error, attempt, sw);
    }
    await _rememberRejected(push.rejected);

    final PullResult pull;
    final from = _reread;
    try {
      pull = await _pullService().pull(
        _pullReasonOf(reason),
        attempt: attempt,
        from: from,
        selectedBudget: _selectedBudgetId,
        onRemoved: _budgetsRemoved,
      );
    } on PullFailure catch (f) {
      return _cycleFailed(
        reason,
        SyncStage.pull,
        f.error,
        attempt,
        sw,
        requestId: f.requestId,
        detail: 'page=${f.page} cursor=${f.cursor}',
        push: push,
        pullFailure: f,
      );
    } catch (e, st) {
      final error = redactDbError(e);
      _log.severe(
        'sync cycle reason=${reason.name}: pull crashed before it could '
        'report: ${describeError(error)}',
        error,
        st,
      );
      return _cycleFailed(
        reason,
        SyncStage.pull,
        error,
        attempt,
        sw,
        push: push,
      );
    }
    if (from != null) _reread = null;
    _failures = 0;
    final remaining = await _queueSize();
    _setState(
      _state.copyWith(
        phase: SyncPhase.idle,
        queueSize: remaining,
        lastSyncAt: pull.syncedAt,
        lastError: null,
        retryAt: null,
        failures: 0,
      ),
    );
    _log.info(
      'sync cycle done reason=${reason.name} attempt=$attempt '
      'push: sent=${push.sent} applied=${push.applied} '
      'rejected=${push.rejected.length} batches=${push.batches} '
      'in ${push.elapsed.inMilliseconds}ms; '
      'pull: pages=${pull.pages} entities=${pull.counts.total} '
      'cursor=${pull.cursorBefore}→${pull.cursorAfter} kept=${pull.kept} '
      'removedBudgets=${pull.removedBudgets.length} '
      'apply=${pull.applyElapsed.inMilliseconds}ms '
      'in ${pull.elapsed.inMilliseconds}ms; '
      'queue=${queue ?? '?'}→${remaining ?? '?'} in ${sw.elapsedMilliseconds}ms',
    );
    return SyncCycleDone(
      reason: reason,
      elapsed: sw.elapsed,
      push: push,
      pull: pull,
    );
  }

  Future<SyncCycleResult> _cycleFailed(
    SyncReason reason,
    SyncStage stage,
    Object error,
    int attempt,
    Stopwatch sw, {
    String? requestId,
    String detail = '',
    PushOutcome? push,
    PullFailure? pullFailure,
  }) async {
    final failure = _classify(error);
    final remaining = await _queueSize();
    final description = _describe(error);
    final rid = requestId ?? '-';
    final where =
        'reason=${reason.name} stage=${stage.name}'
        '${detail.isEmpty ? '' : ' $detail'} attempt=$attempt';
    Duration? retryIn;
    switch (failure) {
      case _Failure.network || _Failure.transient:
        _failures = attempt;
        retryIn = syncRetryDelay(attempt, _random.nextDouble());
        _scheduleRetry(retryIn, attempt);
        _log.warning(
          'sync cycle failed $where $description rid=$rid after '
          '${sw.elapsedMilliseconds}ms → retry attempt=${attempt + 1} in '
          '${retryIn.inMilliseconds}ms, queue=${remaining ?? '?'} kept',
        );
      case _Failure.session:
        _failures = 0;
        _log.info(
          'sync cycle stopped $where $description rid=$rid after '
          '${sw.elapsedMilliseconds}ms → session ended, no retry until the '
          'next sign-in, queue=${remaining ?? '?'} kept',
        );
      case _Failure.fatal:
        _failures = attempt;
        _log.severe(
          'sync cycle failed $where $description rid=$rid after '
          '${sw.elapsedMilliseconds}ms → no automatic retry (not a network '
          'error), the next sync call tries again, '
          'queue=${remaining ?? '?'} kept',
          error,
        );
    }
    _setState(
      _state.copyWith(
        phase: failure == _Failure.network
            ? SyncPhase.waitingNetwork
            : SyncPhase.error,
        queueSize: remaining,
        lastError: _short('${stage.name} $description rid=$rid'),
        retryAt: retryIn == null ? null : _now().add(retryIn),
        failures: _failures,
      ),
    );
    return SyncCycleFailed(
      reason: reason,
      elapsed: sw.elapsed,
      stage: stage,
      error: error,
      attempt: attempt,
      retryIn: retryIn,
      push: push,
      pullFailure: pullFailure,
    );
  }

  Future<SyncNowResult> _pushOnly() async {
    final sw = Stopwatch()..start();
    final blocked = _blocked(needsSession: false);
    if (blocked != null) {
      final remaining = await _queueSize() ?? -1;
      _log.warning(
        'sync now not sent: $blocked → queue=$remaining stays on the phone',
      );
      return SyncNowFailed(
        remaining: remaining,
        applied: 0,
        rejected: 0,
        batches: 0,
        error: SyncHeld(blocked),
      );
    }
    final before = await _queueSize();
    _log.info(
      'sync now: push through the sync engine queue=${before ?? '?'} '
      'batch up to $maxPushBatchSize',
    );
    final phase = _state.phase;
    _setState(_state.copyWith(phase: SyncPhase.sending, queueSize: before));
    try {
      final push = await _push.push('sync-now');
      await _rememberRejected(push.rejected);
      _setState(
        _state.copyWith(
          phase: _retryTimer == null ? SyncPhase.idle : phase,
          queueSize: push.remaining,
          lastError: null,
        ),
      );
      if (push.remaining == 0) {
        _log.info(
          'sync now done applied=${push.applied} '
          'rejected=${push.rejected.length} batches=${push.batches} '
          'queue=${before ?? '?'}→0 in ${sw.elapsedMilliseconds}ms',
        );
        return SyncNowDone(
          applied: push.applied,
          rejected: push.rejected.length,
          batches: push.batches,
        );
      }
      _log.warning(
        'sync now incomplete applied=${push.applied} '
        'rejected=${push.rejected.length} batches=${push.batches} '
        'queue=${before ?? '?'}→${push.remaining}: the rest is not due yet '
        '(delete in its undo window) or was not answered, '
        'in ${sw.elapsedMilliseconds}ms',
      );
      return SyncNowFailed(
        remaining: push.remaining,
        applied: push.applied,
        rejected: push.rejected.length,
        batches: push.batches,
      );
    } on PushFailure catch (f) {
      await _rememberRejected(f.rejected);
      final remaining = await _queueSize();
      final failure = _classify(f.error);
      _log.log(
        failure == _Failure.fatal || failure == _Failure.transient
            ? Level.SEVERE
            : Level.WARNING,
        'sync now failed at batch=${f.batch} ${f.description} '
        'rid=${f.requestId ?? '-'} applied=${f.applied} '
        'rejected=${f.rejected.length} '
        'queue=${before ?? '?'}→${remaining ?? '?'} '
        'after ${sw.elapsedMilliseconds}ms → changes kept in the queue',
        f.error,
      );
      _setState(
        _state.copyWith(
          phase: failure == _Failure.network
              ? SyncPhase.waitingNetwork
              : SyncPhase.error,
          queueSize: remaining,
          lastError: _short('push ${f.description} rid=${f.requestId ?? '-'}'),
        ),
      );
      return SyncNowFailed(
        remaining: remaining ?? before ?? -1,
        applied: f.applied,
        rejected: f.rejected.length,
        batches: f.batches,
        error: f.error,
      );
    } catch (e, st) {
      final error = redactDbError(e);
      final remaining = await _queueSize();
      _log.severe(
        'sync now crashed queue=${before ?? '?'}→${remaining ?? '?'} '
        'after ${sw.elapsedMilliseconds}ms → changes kept in the queue: '
        '${describeError(error)}',
        error,
        st,
      );
      _setState(
        _state.copyWith(
          phase: SyncPhase.error,
          queueSize: remaining,
          lastError: _short('push ${_describe(error)}'),
        ),
      );
      return SyncNowFailed(
        remaining: remaining ?? before ?? -1,
        applied: 0,
        rejected: 0,
        batches: 0,
        error: error,
      );
    }
  }

  Future<PullResult?> _pullOnly(PullReason reason, int attempt) async {
    final blocked = _blocked();
    if (blocked != null) {
      _log.info(
        'pull reason=${reason.name} skipped by the sync engine: $blocked',
      );
      return null;
    }
    final from = _reread;
    final phase = _state.phase;
    _setState(_state.copyWith(phase: SyncPhase.sending));
    try {
      final result = await _pullService().pull(
        reason,
        attempt: attempt,
        from: from,
        selectedBudget: _selectedBudgetId,
        onRemoved: _budgetsRemoved,
      );
      if (from != null) _reread = null;
      final queue = await _queueSize();
      _setState(
        _state.copyWith(
          phase: _retryTimer == null ? SyncPhase.idle : phase,
          queueSize: queue,
          lastSyncAt: result.syncedAt,
          lastError: _retryTimer == null ? null : _state.lastError,
        ),
      );
      return result;
    } on PullFailure catch (f) {
      final failure = _classify(f.error);
      _setState(
        _state.copyWith(
          phase: failure == _Failure.network
              ? SyncPhase.waitingNetwork
              : SyncPhase.error,
          lastError: _short('pull ${f.description} rid=${f.requestId ?? '-'}'),
        ),
      );
      rethrow;
    }
  }

  Future<void> _rememberRejected(List<PushRejected> rejected) async {
    if (rejected.isEmpty) return;
    try {
      final from = await _pullService().rereadCursor([
        for (final r in rejected) r.target,
      ]);
      if (from == null) {
        _log.info(
          'push rejected ${rejected.length} change(s) of entities the server '
          'never sent → nothing to re-read, local rows stay as they are',
        );
        return;
      }
      final current = _reread;
      _reread = current == null || from < current ? from : current;
      _log.info(
        'push rejected ${rejected.length} change(s) → next pull re-reads from '
        'cursor=$_reread',
      );
    } catch (e, st) {
      final error = redactDbError(e);
      _log.warning(
        'push rejected ${rejected.length} change(s), re-read cursor not '
        'found: ${describeError(error)} → rows fixed by later server changes',
        error,
        st,
      );
    }
  }

  void _budgetsRemoved(List<RemovedBudget> removed) {
    final userId = _signedInUserId();
    for (final budget in removed) {
      final kind = budget.ownerId == userId
          ? BudgetRemovalKind.deleted
          : BudgetRemovalKind.excluded;
      if (!budget.wasSelected) {
        _log.info(
          'budget removed budgetId=${budget.budgetId} '
          'kind=${budget.kind.name} as=${kind.name}: not the selected '
          'budget → data removed, no snackbar',
        );
        continue;
      }
      _log.info(
        'selected budget removed budgetId=${budget.budgetId} '
        'kind=${budget.kind.name} as=${kind.name} → personal budget is '
        'shown, snackbar notice',
      );
      _onNotice?.call(budget, kind);
    }
  }

  void _scheduleRetry(Duration delay, int attempt) {
    _retryTimer?.cancel();
    _retryTimer = _startTimer(delay, () {
      _retryTimer = null;
      _log.info(
        'sync retry timer fired after ${delay.inMilliseconds}ms → cycle '
        'reason=retry attempt=${attempt + 1}',
      );
      unawaited(sync(SyncReason.retry));
    });
  }

  bool _cancelRetry() {
    final timer = _retryTimer;
    if (timer == null) return false;
    timer.cancel();
    _retryTimer = null;
    return true;
  }

  Future<int?> _queueSize() async {
    try {
      return await _outbox().count();
    } catch (e, st) {
      final error = redactDbError(e);
      _log.warning(
        'sync engine: queue size not read: ${describeError(error)}',
        error,
        st,
      );
      return null;
    }
  }

  void _setState(SyncEngineState next) {
    final previous = _state;
    if (previous == next) return;
    _state = next;
    if (previous.phase != next.phase) {
      _log.fine('sync state ${previous.phase.name} → ${next.phase.name} $next');
    }
    if (!_states.isClosed) _states.add(next);
  }

  void _watch() {
    _queueWatch ??= _outbox().watchCount().listen(
      (size) => _setState(_state.copyWith(queueSize: size)),
      onError: (Object e, StackTrace st) {
        final error = redactDbError(e);
        _log.warning(
          'sync engine: queue size watch failed: ${describeError(error)}',
          error,
          st,
        );
      },
    );
    final watchLast = _watchLastSyncAt;
    if (watchLast != null) {
      _lastSyncWatch ??= watchLast().listen(
        (at) => _setState(_state.copyWith(lastSyncAt: at)),
        onError: (Object e, StackTrace st) {
          final error = redactDbError(e);
          _log.warning(
            'sync engine: last sync time watch failed: '
            '${describeError(error)}',
            error,
            st,
          );
        },
      );
    }
    _log.fine('sync engine state stream listened → watching queue size');
  }

  void _unwatch() {
    final queue = _queueWatch;
    final last = _lastSyncWatch;
    _queueWatch = null;
    _lastSyncWatch = null;
    if (queue != null) unawaited(queue.cancel());
    if (last != null) unawaited(last.cancel());
  }
}

PullReason _pullReasonOf(SyncReason reason) => switch (reason) {
  SyncReason.manual => PullReason.manual,
  SyncReason.retry => PullReason.retry,
  SyncReason.startup => PullReason.startup,
  SyncReason.resume => PullReason.resume,
  SyncReason.network => PullReason.network,
  SyncReason.outbox => PullReason.outbox,
  SyncReason.periodic => PullReason.periodic,
  SyncReason.websocket => PullReason.websocket,
};

_Failure _classify(Object error) => switch (error) {
  ApiNetworkFailure() || ApiTimeout() => _Failure.network,
  ApiServerFailure() => _Failure.transient,
  ApiErrorResponse(:final statusCode) when statusCode == 429 =>
    _Failure.transient,
  ApiSessionExpired() => _Failure.session,
  ApiErrorResponse(:final statusCode) when statusCode == 401 =>
    _Failure.session,
  _ => _Failure.fatal,
};

String _describe(Object error) => switch (error) {
  final ApiException e => '${e.runtimeType}: ${e.details}',
  final PullStalled e => e.toString(),
  final Object e => describeError(e),
};

const int _lastErrorLength = 300;

String _short(String text) => text.length > _lastErrorLength
    ? '${text.substring(0, _lastErrorLength)}…'
    : text;

final syncEngineProvider = Provider<SyncEngine>((ref) {
  final engine = SyncEngine(
    api: () => ref.read(syncApiProvider),
    outbox: () => ref.read(outboxQueueProvider),
    pullService: () => ref.read(pullServiceProvider),
    signedInUserId: () {
      final session = ref.read(sessionProvider);
      return session is SessionActive ? session.user.userId : null;
    },
    selectedBudgetId: () async => ref.read(selectedBudgetIdProvider).value,
    onNotice: (budget, kind) => ref
        .read(budgetRemovedNoticeProvider.notifier)
        .post(budgetId: budget.budgetId, name: budget.name, kind: kind),
    watchLastSyncAt: () => ref.read(syncStateQueriesProvider).watchLastSyncAt(),
    now: () => ref.read(clockProvider).now(),
  );
  ref.listen<SessionState>(
    sessionProvider,
    (previous, next) => engine.sessionChanged(previous, next),
  );
  ref.onDispose(engine.dispose);
  return engine;
}, name: 'syncEngine');
