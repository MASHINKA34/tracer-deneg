import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../data/api/api_exception.dart';
import '../../data/db/redact_db_error.dart';
import '../../data/providers.dart';
import '../../data/repositories/account_data_cleaner.dart';
import '../../data/session/session.dart';
import '../../data/session/session_providers.dart';
import '../../data/session/session_state.dart';
import '../../data/sync/pull_controller.dart';

final _log = Logger('auth');

sealed class SignInCheck {
  const SignInCheck();
}

final class SignInFresh extends SignInCheck {
  const SignInFresh();
}

final class SignInSameAccount extends SignInCheck {
  const SignInSameAccount(this.queueSize);

  final int queueSize;
}

final class SignInOtherAccount extends SignInCheck {
  const SignInOtherAccount(this.previous, this.queueSize);

  final SessionUser previous;
  final int queueSize;
}

final class SignInCheckFailed extends SignInCheck {
  const SignInCheckFailed(this.error);

  final Object error;
}

class SessionEndService {
  SessionEndService(this._ref);

  final Ref _ref;

  Future<void> reportEnded(SessionEnded ended) async {
    final sw = Stopwatch()..start();
    final what = switch (ended.reason) {
      SessionEndReason.refreshRejected => 'refresh token rejected',
      SessionEndReason.sessionRejected => 'session rejected by server',
      SessionEndReason.noSession ||
      SessionEndReason.endedEarlier => 'session ended',
    };
    final String queue;
    try {
      queue = '${await _ref.read(outboxQueueProvider).count()}';
    } catch (e, st) {
      final error = redactDbError(e);
      _log.warning(
        '$what → re-login reason=${ended.reason.name} '
        'userId=${ended.user.userId}: queue size not read after '
        '${sw.elapsedMilliseconds}ms, local data kept anyway: '
        '${describeError(error)}',
        error,
        st,
      );
      return;
    }
    _log.info(
      '$what → re-login reason=${ended.reason.name} '
      'userId=${ended.user.userId} queue=$queue → sign-in screen with '
      '"session ended" notice, local data and queue kept '
      '(counted in ${sw.elapsedMilliseconds}ms)',
    );
  }

  Future<SignInCheck> checkSignIn({
    required String action,
    required String login,
    bool newAccount = false,
  }) async {
    final session = _ref.read(sessionProvider);
    if (session is! SessionEnded) {
      _log.fine(
        '$action: session ${session.name}, no previous account on the phone '
        '→ usual sign-in',
      );
      return const SignInFresh();
    }
    final previous = session.user;
    final typed = normalizeLogin(login);
    final same = !newAccount && typed == normalizeLogin(previous.login);
    final sw = Stopwatch()..start();
    final int queue;
    try {
      queue = await _ref.read(outboxQueueProvider).count();
    } catch (e, st) {
      final error = redactDbError(e);
      _log.severe(
        '$action after session end: queue size not read after '
        '${sw.elapsedMilliseconds}ms → not signing in, nothing cleared: '
        '${describeError(error)}',
        error,
        st,
      );
      return SignInCheckFailed(error);
    }
    final account = newAccount
        ? 'a new account login=${maskLogin(typed)}'
        : '${same ? 'the same' : 'another'} login=${maskLogin(typed)}';
    final next = same
        ? 'usual sign-in, local data and queue kept'
        : queue == 0
        ? 'nothing unsynced, no dialog, previous account data cleared once '
              'the server accepts'
        : 'warning dialog before clearing previous account data';
    _log.info(
      '$action after session end with $account previousUserId='
      '${previous.userId} previousLogin=${maskLogin(previous.login)} '
      'queue=$queue → $next (counted in ${sw.elapsedMilliseconds}ms)',
    );
    return same
        ? SignInSameAccount(queue)
        : SignInOtherAccount(previous, queue);
  }

  Future<AccountDataRemoval?> clearIfAnotherAccount({
    required String action,
    required String userId,
  }) async {
    final session = _ref.read(sessionProvider);
    if (session is! SessionEnded) return null;
    final previousId = session.user.userId;
    if (previousId == userId) {
      _log.info(
        '$action: same account userId=$userId as the ended session → '
        'local data and queue kept, the queue goes to the server as usual',
      );
      return null;
    }
    final sw = Stopwatch()..start();
    _log.info(
      '$action: another account userId=$userId, previous '
      'userId=$previousId → clearing previous account data like sign-out',
    );
    await _waitForPull(action);
    final removal = await _ref
        .read(accountDataCleanerProvider)
        .clearAccountData('account-switch');
    _log.info(
      '$action: previous account userId=$previousId cleared queue='
      '${removal.outbox} rows=${removal.total} account prefs '
      '[${removal.prefs.join(',')}] in ${sw.elapsedMilliseconds}ms → '
      'signing in userId=$userId, first load follows',
    );
    return removal;
  }

  Future<void> _waitForPull(String action) async {
    final status = _ref.read(pullControllerProvider);
    if (status is! PullRunning) return;
    final sw = Stopwatch()..start();
    _log.info(
      '$action: waiting for running pull reason=${status.reason.name} '
      'before clearing previous account data',
    );
    await _ref.read(pullControllerProvider.notifier).run(status.reason);
    _log.info('$action: pull finished after ${sw.elapsedMilliseconds}ms');
  }
}

final sessionEndServiceProvider = Provider<SessionEndService>(
  SessionEndService.new,
  name: 'sessionEndService',
);
