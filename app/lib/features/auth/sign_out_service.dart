import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../data/api/api_exception.dart';
import '../../data/api/auth_api.dart';
import '../../data/db/redact_db_error.dart';
import '../../data/providers.dart';
import '../../data/repositories/account_data_cleaner.dart';
import '../../data/session/session_providers.dart';
import '../../data/sync/pull_controller.dart';
import '../../data/sync/sync_engine.dart';
import '../../data/sync/sync_service.dart';
import '../reminders/reminder_scheduler.dart';
import '../widget/widget_updater.dart';

final _log = Logger('auth');

enum SignOutChoice { confirm, sync, discard }

sealed class SignOutOutcome {
  const SignOutOutcome();
}

final class SignedOut extends SignOutOutcome {
  const SignedOut({
    required this.removal,
    required this.serverRevoked,
    required this.elapsed,
  });

  final AccountDataRemoval removal;
  final bool serverRevoked;
  final Duration elapsed;
}

final class SignOutFailed extends SignOutOutcome {
  const SignOutFailed(this.error);

  final Object error;
}

class SignOutService {
  SignOutService(this._ref);

  final Ref _ref;

  Future<int?> queueSize() async {
    final sw = Stopwatch()..start();
    try {
      final size = await _ref.read(outboxQueueProvider).count();
      _log.info(
        'sign-out tap: queue=$size → '
        '${size == 0 ? 'confirm dialog' : 'unsynced changes dialog'} '
        '(counted in ${sw.elapsedMilliseconds}ms)',
      );
      return size;
    } catch (e, st) {
      final error = redactDbError(e);
      _log.severe(
        'sign-out tap: queue size not read after ${sw.elapsedMilliseconds}ms '
        '→ no dialog, staying signed in: ${describeError(error)}',
        error,
        st,
      );
      return null;
    }
  }

  void dialogClosed({required int queueSize, required bool cancelled}) {
    _log.info(
      'sign-out dialog choice=${cancelled ? 'cancel' : 'dismissed'} '
      'queue=$queueSize → staying signed in, nothing cleared',
    );
  }

  Future<SyncNowResult> syncFirst({required int queueSize}) async {
    final sw = Stopwatch()..start();
    _log.info(
      'sign-out dialog choice=${SignOutChoice.sync.name} queue=$queueSize '
      '→ sending the queue before sign-out',
    );
    final result = await _ref.read(syncServiceProvider).syncNow();
    switch (result) {
      case SyncNowDone(:final applied, :final rejected):
        _log.info(
          'sign-out sync ok applied=$applied rejected=$rejected '
          'in ${sw.elapsedMilliseconds}ms → signing out',
        );
      case SyncNowFailed(:final remaining):
        _log.info(
          'sign-out sync failed ${result.description} remaining=$remaining '
          'in ${sw.elapsedMilliseconds}ms → dialog stays, still signed in',
        );
    }
    return result;
  }

  Future<SignOutOutcome> signOut({
    required SignOutChoice choice,
    required int queueSize,
  }) async {
    final sw = Stopwatch()..start();
    final userId = _ref.read(sessionProvider).userId;
    final lost = choice == SignOutChoice.discard
        ? ' → $queueSize unsynced change(s) dropped with the local data'
        : '';
    _log.info(
      'sign-out started choice=${choice.name} queue=$queueSize '
      'userId=${userId ?? '-'}$lost',
    );
    await _waitForPull();
    await _ref.read(syncEngineProvider).hold('sign-out');

    final AccountDataRemoval removal;
    try {
      removal = await _ref
          .read(accountDataCleanerProvider)
          .clearAccountData('sign-out');
    } catch (e, st) {
      final error = redactDbError(e);
      _log.severe(
        'sign-out stopped: local data not cleared after '
        '${sw.elapsedMilliseconds}ms → still signed in, server session kept: '
        '${describeError(error)}',
        error,
        st,
      );
      _ref.read(syncEngineProvider).release('sign-out stopped, data kept');
      return SignOutFailed(error);
    }

    await _ref
        .read(widgetUpdaterProvider)
        .updateImmediately(WidgetUpdateSource.accountCleared);
    await _ref.read(reminderSchedulerProvider).cancelAll('sign-out');

    final serverRevoked = userId != null && await _logoutOnServer();
    if (userId == null) {
      _log.info('sign-out: no session on the phone → server logout skipped');
    }

    try {
      await _ref.read(sessionProvider.notifier).clear();
    } catch (e, st) {
      _log.severe(
        'sign-out: local data cleared, but session tokens not removed after '
        '${sw.elapsedMilliseconds}ms → staying on the screen, retry possible: '
        '${describeError(e)}',
        e,
        st,
      );
      return SignOutFailed(e);
    }
    _log.info(
      'sign-out done choice=${choice.name} queue=$queueSize '
      'userId=${userId ?? '-'} cleared: ${removal.total} rows, tokens, '
      'account prefs [${removal.prefs.join(',')}] '
      'serverSession=${serverRevoked ? 'revoked' : 'not revoked'} '
      'in ${sw.elapsedMilliseconds}ms → sign-in screen',
    );
    return SignedOut(
      removal: removal,
      serverRevoked: serverRevoked,
      elapsed: sw.elapsed,
    );
  }

  Future<void> _waitForPull() async {
    final status = _ref.read(pullControllerProvider);
    if (status is! PullRunning) return;
    final sw = Stopwatch()..start();
    _log.info(
      'sign-out waits for running pull reason=${status.reason.name} '
      'before clearing local data',
    );
    await _ref.read(pullControllerProvider.notifier).run(status.reason);
    _log.info('sign-out: pull finished after ${sw.elapsedMilliseconds}ms');
  }

  Future<bool> _logoutOnServer() async {
    final sw = Stopwatch()..start();
    try {
      final rid = await _ref.read(authApiProvider).logout();
      _log.info(
        'sign-out: server session revoked rid=$rid '
        'in ${sw.elapsedMilliseconds}ms',
      );
      return true;
    } on ApiException catch (e, st) {
      _log.warning(
        'sign-out: server logout failed ${e.runtimeType}: ${e.details} '
        'rid=${e.requestId ?? '-'} after ${sw.elapsedMilliseconds}ms → '
        'continuing, signing out on the phone only',
        e,
        st,
      );
      return false;
    } catch (e, st) {
      _log.warning(
        'sign-out: server logout crashed after ${sw.elapsedMilliseconds}ms → '
        'continuing, signing out on the phone only: ${describeError(e)}',
        e,
        st,
      );
      return false;
    }
  }
}

final signOutServiceProvider = Provider<SignOutService>(
  SignOutService.new,
  name: 'signOutService',
);
