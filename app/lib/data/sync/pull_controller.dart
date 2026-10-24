import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../core/clock.dart';
import '../api/sync_api.dart';
import '../db/redact_db_error.dart';
import '../providers.dart';
import '../session/session_providers.dart';
import '../session/session_state.dart';
import 'pull_service.dart';
import 'sync_engine.dart';

final _log = Logger('sync');

sealed class PullStatus {
  const PullStatus();

  bool get showsIndicator => false;
}

final class PullIdle extends PullStatus {
  const PullIdle({this.last});

  final PullResult? last;

  @override
  String toString() => 'PullIdle(${last ?? 'never'})';
}

final class PullPending extends PullStatus {
  const PullPending(this.reason);

  final PullReason reason;

  @override
  bool get showsIndicator => true;

  @override
  String toString() => 'PullPending(${reason.name})';
}

final class PullRunning extends PullStatus {
  const PullRunning(this.reason);

  final PullReason reason;

  @override
  bool get showsIndicator => reason != PullReason.manual;

  @override
  String toString() => 'PullRunning(${reason.name})';
}

final class PullFailed extends PullStatus {
  const PullFailed(this.failure, this.id);

  final PullFailure failure;
  final int id;

  @override
  String toString() => 'PullFailed(#$id $failure)';
}

final pullServiceProvider = Provider<PullService>(
  (ref) => PullService(
    api: ref.watch(syncApiProvider),
    db: ref.watch(appDatabaseProvider),
    budgets: ref.watch(budgetsRepositoryProvider),
    members: ref.watch(membersRepositoryProvider),
    categories: ref.watch(categoriesRepositoryProvider),
    recurring: ref.watch(recurringRepositoryProvider),
    expenses: ref.watch(expensesRepositoryProvider),
    now: ref.watch(clockProvider).now,
  ),
  name: 'pullService',
);

final pullControllerProvider = NotifierProvider<PullController, PullStatus>(
  PullController.new,
  name: 'pull',
);

final class PullController extends Notifier<PullStatus> {
  Future<PullResult?>? _running;
  PullReason? _runningReason;
  int _failures = 0;
  int _failureId = 0;
  int _noticed = 0;

  @override
  PullStatus build() => const PullIdle();

  void requestAfterSignIn(PullReason reason) {
    final running = _runningReason;
    if (running != null) {
      _log.info(
        'initial pull requested reason=${reason.name} while pull '
        'reason=${running.name} is running → that pull covers it',
      );
      return;
    }
    state = PullPending(reason);
    _log.info(
      'initial pull requested reason=${reason.name} → starts when the main '
      'screen opens',
    );
  }

  Future<PullResult?> startRequested() {
    final current = state;
    if (current is! PullPending) return Future.value();
    _log.fine(
      'main screen opened → starting requested pull '
      'reason=${current.reason.name}',
    );
    return run(current.reason);
  }

  Future<PullResult?> run(PullReason reason) {
    final running = _running;
    if (running != null) {
      _log.fine(
        'pull reason=${reason.name} joins the running pull '
        'reason=${_runningReason?.name}',
      );
      return running;
    }
    final session = ref.read(sessionProvider);
    if (session is! SessionActive) {
      _log.info(
        'pull skipped reason=${reason.name}: session ${session.name}, '
        'nothing to load from the server',
      );
      if (state is PullPending) state = const PullIdle();
      return Future.value();
    }
    _runningReason = reason;
    final future = _run(reason, session.user.userId);
    _running = future;
    unawaited(
      future.whenComplete(() {
        if (!identical(_running, future)) return;
        _running = null;
        _runningReason = null;
      }),
    );
    return future;
  }

  bool claimFailureNotice(int id) {
    if (id <= _noticed) return false;
    _noticed = id;
    return true;
  }

  Future<PullResult?> _run(PullReason reason, String userId) async {
    final attempt = _failures + 1;
    _setState(PullRunning(reason));
    _log.fine(
      'pull status → running reason=${reason.name} userId=$userId '
      'attempt=$attempt',
    );
    try {
      final result = await ref
          .read(syncEngineProvider)
          .pullNow(reason, attempt: attempt);
      if (result == null) {
        _setState(const PullIdle());
        _log.fine(
          'pull status → idle: sync engine skipped pull reason=${reason.name}',
        );
        return null;
      }
      _failures = 0;
      _setState(PullIdle(last: result));
      _log.fine('pull status → idle after ${result.pages} page(s)');
      return result;
    } on PullFailure catch (failure) {
      _failures = attempt;
      _setState(PullFailed(failure, ++_failureId));
      _log.fine(
        'pull status → failed #$_failureId reason=${reason.name} '
        'attempt=$attempt',
      );
      return null;
    } catch (e, st) {
      _failures = attempt;
      final error = redactDbError(e);
      _log.severe(
        'pull crashed before it could start reason=${reason.name} '
        'attempt=$attempt: ${describeError(error)}',
        error,
        st,
      );
      _setState(
        PullFailed(
          PullFailure(
            reason: reason,
            stage: PullStage.prepare,
            page: 1,
            cursor: -1,
            pagesApplied: 0,
            attempt: attempt,
            error: error,
          ),
          ++_failureId,
        ),
      );
      return null;
    }
  }

  void _setState(PullStatus next) {
    if (!ref.mounted) {
      _log.fine('pull status $next not shown: app scope is gone');
      return;
    }
    state = next;
  }
}
