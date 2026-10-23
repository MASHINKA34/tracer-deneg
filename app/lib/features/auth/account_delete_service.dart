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
import 'sign_in_notice.dart';

final _log = Logger('auth');

sealed class AccountDeleteOutcome {
  const AccountDeleteOutcome();
}

final class AccountDeleted extends AccountDeleteOutcome {
  const AccountDeleted({
    required this.requestId,
    required this.removal,
    required this.elapsed,
  });

  final String requestId;
  final AccountDataRemoval? removal;
  final Duration elapsed;

  bool get phoneCleared => removal != null;
}

final class AccountDeleteFailed extends AccountDeleteOutcome {
  const AccountDeleteFailed(this.error);

  final Object error;

  ApiErrorCode? get code => switch (error) {
    ApiErrorResponse(:final code) => code,
    _ => null,
  };
}

class AccountDeleteService {
  AccountDeleteService(this._ref);

  final Ref _ref;

  Future<AccountDeleteOutcome> deleteAccount({required String password}) async {
    final sw = Stopwatch()..start();
    final userId = _ref.read(sessionProvider).userId ?? '-';
    final queue = await _queueSize();
    _log.info(
      'account delete started userId=$userId queue=$queue → '
      'DELETE $accountPath',
    );
    await _waitForPull();

    final String rid;
    try {
      rid = await _ref.read(authApiProvider).deleteAccount(password: password);
    } on ApiException catch (e, st) {
      _rejected(e, st, userId: userId, ms: sw.elapsedMilliseconds);
      return AccountDeleteFailed(e);
    } catch (e, st) {
      _log.severe(
        'account delete crashed before the server answered after '
        '${sw.elapsedMilliseconds}ms userId=$userId → snackbar, nothing '
        'deleted: ${describeError(e)}',
        e,
        st,
      );
      return AccountDeleteFailed(e);
    }
    _log.info(
      'account deleted on server userId=$userId rid=$rid '
      'in ${sw.elapsedMilliseconds}ms → clearing phone data',
    );
    _ref.read(signInNoticeProvider.notifier).post(SignInNotice.accountDeleted);

    final AccountDataRemoval removal;
    try {
      removal = await _ref
          .read(accountDataCleanerProvider)
          .clearAccountData('account-delete');
    } catch (e, st) {
      final error = redactDbError(e);
      _log.severe(
        'account delete: account deleted on server rid=$rid, but phone data '
        'not cleared after ${sw.elapsedMilliseconds}ms → session marked '
        'ended, data stays until the next sign-in clears it: '
        '${describeError(error)}',
        error,
        st,
      );
      _ref
          .read(sessionProvider.notifier)
          .ended(SessionEndReason.sessionRejected);
      return AccountDeleted(requestId: rid, removal: null, elapsed: sw.elapsed);
    }

    try {
      await _ref.read(sessionProvider.notifier).clear();
    } catch (e, st) {
      _log.severe(
        'account delete: phone data cleared, but session tokens not removed '
        'after ${sw.elapsedMilliseconds}ms → session marked ended, the server '
        'already revoked them: ${describeError(e)}',
        e,
        st,
      );
      _ref
          .read(sessionProvider.notifier)
          .ended(SessionEndReason.sessionRejected);
      return AccountDeleted(
        requestId: rid,
        removal: removal,
        elapsed: sw.elapsed,
      );
    }
    _log.info(
      'account delete done userId=$userId rid=$rid queue=$queue cleared: '
      '${removal.total} rows, tokens, account prefs '
      '[${removal.prefs.join(',')}] in ${sw.elapsedMilliseconds}ms → '
      'sign-in screen with "account deleted" snackbar',
    );
    return AccountDeleted(
      requestId: rid,
      removal: removal,
      elapsed: sw.elapsed,
    );
  }

  void _rejected(
    ApiException e,
    StackTrace st, {
    required String userId,
    required int ms,
  }) {
    switch (e) {
      case ApiErrorResponse(
        code: ApiErrorCode.badCredentials,
        :final statusCode,
      ):
        _log.warning(
          'account delete rejected: wrong password '
          'code=${ApiErrorCode.badCredentials.code} status=$statusCode '
          'userId=$userId rid=${e.requestId} in ${ms}ms → error under the '
          'field, nothing deleted',
        );
      case ApiErrorResponse(:final statusCode, :final error):
        _log.warning(
          'account delete rejected code=${error.code} status=$statusCode '
          'userId=$userId rid=${e.requestId} in ${ms}ms → snackbar, nothing '
          'deleted',
        );
      case ApiSessionExpired(:final reason):
        _log.info(
          'account delete not sent through: session ended '
          'reason=${reason.name} userId=$userId rid=${e.requestId} in ${ms}ms '
          '→ sign-in screen, phone data kept',
        );
      case ApiTimeout():
        _log.warning(
          'account delete failed ${e.runtimeType}: ${e.details} '
          'userId=$userId rid=${e.requestId} in ${ms}ms → snackbar, nothing '
          'deleted on the phone; the server may still have deleted it, the '
          'next request will end the session then',
          e,
          st,
        );
      default:
        _log.warning(
          'account delete failed ${e.runtimeType}: ${e.details} '
          'userId=$userId rid=${e.requestId} in ${ms}ms → snackbar, nothing '
          'deleted',
          e,
          st,
        );
    }
  }

  Future<String> _queueSize() async {
    try {
      return '${await _ref.read(outboxQueueProvider).count()}';
    } catch (e, st) {
      final error = redactDbError(e);
      _log.warning(
        'account delete: queue size not read, going on without it: '
        '${describeError(error)}',
        error,
        st,
      );
      return '?';
    }
  }

  Future<void> _waitForPull() async {
    final status = _ref.read(pullControllerProvider);
    if (status is! PullRunning) return;
    final sw = Stopwatch()..start();
    _log.info(
      'account delete waits for running pull reason=${status.reason.name} '
      'before asking the server',
    );
    await _ref.read(pullControllerProvider.notifier).run(status.reason);
    _log.info(
      'account delete: pull finished after ${sw.elapsedMilliseconds}ms',
    );
  }
}

final accountDeleteServiceProvider = Provider<AccountDeleteService>(
  AccountDeleteService.new,
  name: 'accountDeleteService',
);
