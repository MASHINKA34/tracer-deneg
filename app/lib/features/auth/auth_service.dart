import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../data/api/api_exception.dart';
import '../../data/api/auth_api.dart';
import '../../data/db/redact_db_error.dart';
import '../../data/providers.dart';
import '../../data/repositories/prefs_repository.dart';
import '../../data/session/device_name.dart';
import '../../data/session/session_providers.dart';
import '../../data/sync/pull_controller.dart';
import '../../data/sync/pull_service.dart';
import 'recovery_code_state.dart';
import 'session_end_service.dart';

final _log = Logger('auth');

enum AuthAction { login, register, recover }

sealed class AuthOutcome {
  const AuthOutcome();
}

final class AuthSignedIn extends AuthOutcome {
  const AuthSignedIn(this.result);

  final AuthResult result;
}

final class AuthApiFailed extends AuthOutcome {
  const AuthApiFailed(this.error);

  final ApiException error;

  ApiErrorCode? get code => switch (error) {
    ApiErrorResponse(:final code) => code,
    _ => null,
  };

  ValidationError? get validation => switch (error) {
    ApiErrorResponse(:final error) => ValidationError.fromCode(error.code),
    _ => null,
  };
}

final class AuthNotSaved extends AuthOutcome {
  const AuthNotSaved(this.error);

  final Object error;
}

class AuthService {
  AuthService(this._ref);

  final Ref _ref;

  Future<AuthOutcome> login({required String login, required String password}) {
    final normalized = normalizeLogin(login);
    return _run(
      AuthAction.login,
      normalized,
      (deviceName) => _ref
          .read(authApiProvider)
          .login(login: normalized, password: password, deviceName: deviceName),
    );
  }

  Future<AuthOutcome> register({
    required String displayName,
    required String login,
    required String password,
  }) {
    final normalized = normalizeLogin(login);
    final name = normalizeText(displayName);
    return _run(
      AuthAction.register,
      normalized,
      (deviceName) => _ref
          .read(authApiProvider)
          .register(
            login: normalized,
            displayName: name,
            password: password,
            deviceName: deviceName,
          ),
    );
  }

  Future<AuthOutcome> recover({
    required String login,
    required String recoveryCode,
    required String newPassword,
  }) {
    final normalized = normalizeLogin(login);
    final code = normalizeRecoveryCode(recoveryCode);
    if (code == null) {
      _log.fine(
        'recover: code does not normalize (length=${recoveryCode.length}) → '
        'sending as typed, the server will reject it',
      );
    }
    return _run(
      AuthAction.recover,
      normalized,
      (deviceName) => _ref
          .read(authApiProvider)
          .recover(
            login: normalized,
            recoveryCode: code ?? recoveryCode,
            newPassword: newPassword,
            deviceName: deviceName,
          ),
    );
  }

  Future<AuthOutcome> _run(
    AuthAction action,
    String login,
    Future<AuthResult> Function(String deviceName) call,
  ) async {
    final sw = Stopwatch()..start();
    final masked = maskLogin(login);
    final deviceName = _ref.read(deviceNameProvider);
    _log.fine(
      '${action.name} request login=$masked '
      'deviceNameLength=${deviceName.length}',
    );
    final AuthResult result;
    try {
      result = await call(deviceName);
    } on ApiException catch (e, st) {
      final ms = sw.elapsedMilliseconds;
      switch (e) {
        case ApiErrorResponse(:final statusCode, :final error):
          _log.info(
            '${action.name} rejected code=${error.code} status=$statusCode '
            'login=$masked rid=${e.requestId} in ${ms}ms',
          );
        default:
          _log.warning(
            '${action.name} failed ${e.runtimeType}: ${e.details} '
            'login=$masked rid=${e.requestId} in ${ms}ms',
            e,
            st,
          );
      }
      return AuthApiFailed(e);
    }

    final userId = result.session.user.userId;
    final code = result.recoveryCode;
    try {
      await _ref
          .read(sessionEndServiceProvider)
          .clearIfAnotherAccount(action: action.name, userId: userId);
    } catch (e, st) {
      final error = redactDbError(e);
      _log.severe(
        '${action.name} accepted by server userId=$userId login=$masked '
        'rid=${result.requestId}, but previous account data not cleared '
        'after ${sw.elapsedMilliseconds}ms → not signed in, staying on the '
        '${action.name} screen, previous account data and queue kept: '
        '${describeError(error)}',
        error,
        st,
      );
      return AuthNotSaved(error);
    }
    await _rememberSignIn(action, userId);
    if (code != null) {
      _ref
          .read(pendingRecoveryCodeProvider.notifier)
          .show(code, _reasonOf(action));
    }
    try {
      await _ref.read(sessionProvider.notifier).save(result.session);
    } catch (e, st) {
      _log.severe(
        '${action.name} accepted by server but session not saved on the '
        'phone userId=$userId login=$masked rid=${result.requestId} '
        'after ${sw.elapsedMilliseconds}ms → '
        '${code == null ? 'staying on the ${action.name} screen' : 'showing the recovery code, then the sign-in screen'}: '
        '${describeError(e)}',
        e,
        st,
      );
      return AuthNotSaved(e);
    }
    _log.info(
      '${action.name} ok userId=$userId login=$masked '
      '${code == null ? '' : 'recoveryCode=issued '}'
      'rid=${result.requestId} in ${sw.elapsedMilliseconds}ms',
    );
    _ref.read(pullControllerProvider.notifier).requestAfterSignIn(
      switch (action) {
        AuthAction.login => PullReason.login,
        AuthAction.register => PullReason.register,
        AuthAction.recover => PullReason.recover,
      },
    );
    return AuthSignedIn(result);
  }

  RecoveryCodeReason _reasonOf(AuthAction action) => switch (action) {
    AuthAction.recover => RecoveryCodeReason.recover,
    AuthAction.register || AuthAction.login => RecoveryCodeReason.register,
  };

  Future<void> _rememberSignIn(AuthAction action, String userId) async {
    final sw = Stopwatch()..start();
    try {
      await _ref
          .read(prefsRepositoryProvider)
          .setBool(PrefKeys.signedInBefore, true);
      _log.fine(
        '${action.name}: ${PrefKeys.signedInBefore}=true saved userId=$userId '
        'in ${sw.elapsedMilliseconds}ms → DEV_SEED stays off on this phone',
      );
    } catch (e, st) {
      final error = redactDbError(e);
      _log.warning(
        '${action.name}: ${PrefKeys.signedInBefore} not saved userId=$userId '
        'after ${sw.elapsedMilliseconds}ms → continuing sign-in: '
        '${describeError(error)}',
        error,
        st,
      );
    }
  }
}

final authServiceProvider = Provider<AuthService>(
  AuthService.new,
  name: 'authService',
);
