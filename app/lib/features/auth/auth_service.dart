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

final _log = Logger('auth');

enum AuthAction { login, register }

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
    await _rememberSignIn(action, userId);
    try {
      await _ref.read(sessionProvider.notifier).save(result.session);
    } catch (e, st) {
      _log.severe(
        '${action.name} accepted by server but session not saved on the '
        'phone userId=$userId login=$masked rid=${result.requestId} '
        'after ${sw.elapsedMilliseconds}ms → staying on the ${action.name} '
        'screen: ${describeError(e)}',
        e,
        st,
      );
      return AuthNotSaved(e);
    }
    _log.info(
      '${action.name} ok userId=$userId login=$masked '
      '${action == AuthAction.register ? 'recoveryCode=issued ' : ''}'
      'rid=${result.requestId} in ${sw.elapsedMilliseconds}ms',
    );
    return AuthSignedIn(result);
  }

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
