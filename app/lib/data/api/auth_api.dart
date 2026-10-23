import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../session/session.dart';
import 'api_client.dart';
import 'api_exception.dart';
import 'api_providers.dart';
import 'token_store.dart';

final _log = Logger('auth');

const String loginPath = '/auth/login';

const String registerPath = '/auth/register';

const String recoverPath = '/auth/recover';

const String recoveryCodePath = '/auth/recovery-code';

const String logoutPath = '/auth/logout';

const String accountPath = '/account';

final class AuthResult {
  const AuthResult({
    required this.session,
    required this.requestId,
    this.recoveryCode,
  });

  final Session session;
  final String requestId;
  final String? recoveryCode;

  @override
  String toString() =>
      'AuthResult(${session.user}, rid=$requestId, '
      'recoveryCode=${recoveryCode == null ? 'none' : maskRecoveryCode(recoveryCode)})';
}

final class ReissuedRecoveryCode {
  const ReissuedRecoveryCode({
    required this.recoveryCode,
    required this.requestId,
  });

  final String recoveryCode;
  final String requestId;

  @override
  String toString() =>
      'ReissuedRecoveryCode(${maskRecoveryCode(recoveryCode)}, '
      'rid=$requestId)';
}

class AuthApi {
  AuthApi(this._client);

  final ApiClient _client;

  Future<AuthResult> login({
    required String login,
    required String password,
    required String deviceName,
  }) async {
    final response = await _client.post(
      loginPath,
      auth: false,
      body: {'login': login, 'password': password, 'deviceName': deviceName},
    );
    return _parse(response, loginPath, recoveryCode: false);
  }

  Future<AuthResult> register({
    required String login,
    required String displayName,
    required String password,
    required String deviceName,
  }) async {
    final response = await _client.post(
      registerPath,
      auth: false,
      body: {
        'login': login,
        'displayName': displayName,
        'password': password,
        'deviceName': deviceName,
      },
    );
    return _parse(response, registerPath, recoveryCode: true);
  }

  Future<AuthResult> recover({
    required String login,
    required String recoveryCode,
    required String newPassword,
    required String deviceName,
  }) async {
    final response = await _client.post(
      recoverPath,
      auth: false,
      body: {
        'login': login,
        'recoveryCode': recoveryCode,
        'newPassword': newPassword,
        'deviceName': deviceName,
      },
    );
    return _parse(response, recoverPath, recoveryCode: true);
  }

  Future<ReissuedRecoveryCode> reissueRecoveryCode({
    required String password,
  }) async {
    final response = await _client.post(
      recoveryCodePath,
      body: {'password': password},
    );
    try {
      final reader = JsonReader.of(response.data, 'RecoveryCodeResponse');
      return ReissuedRecoveryCode(
        recoveryCode: _recoveryCode(reader),
        requestId: response.requestId,
      );
    } on FormatException catch (e) {
      _log.warning(
        'POST $recoveryCodePath ${response.statusCode} answered without '
        '{recoveryCode} → bad response: ${e.message} '
        'rid=${response.requestId}',
      );
      throw ApiBadResponse(
        method: 'POST',
        path: '${_client.config.baseUrl.path}$recoveryCodePath',
        requestId: response.requestId,
        statusCode: response.statusCode,
        reason: 'recovery code: ${e.message}',
      );
    }
  }

  Future<String> logout() async {
    final response = await _client.post(logoutPath);
    return response.requestId;
  }

  Future<String> deleteAccount({required String password}) async {
    final response = await _client.delete(
      accountPath,
      body: {'password': password},
    );
    return response.requestId;
  }

  AuthResult _parse(
    ApiResponse response,
    String path, {
    required bool recoveryCode,
  }) {
    try {
      final reader = JsonReader.of(response.data, 'AuthResponse');
      final user = User.fromJson(reader.json['user']);
      final tokens = AuthTokens(
        accessToken: _nonEmpty(reader, 'accessToken'),
        refreshToken: _nonEmpty(reader, 'refreshToken'),
      );
      return AuthResult(
        session: Session(
          user: SessionUser(
            userId: user.id,
            login: user.login,
            displayName: user.displayName,
          ),
          tokens: tokens,
        ),
        requestId: response.requestId,
        recoveryCode: recoveryCode ? _recoveryCode(reader) : null,
      );
    } on FormatException catch (e) {
      _log.warning(
        'POST $path ${response.statusCode} answered without '
        '{user, accessToken, refreshToken${recoveryCode ? ', recoveryCode' : ''}} '
        '→ bad response: ${e.message} rid=${response.requestId}',
      );
      throw ApiBadResponse(
        method: 'POST',
        path: '${_client.config.baseUrl.path}$path',
        requestId: response.requestId,
        statusCode: response.statusCode,
        reason: 'auth: ${e.message}',
      );
    }
  }
}

String _nonEmpty(JsonReader reader, String key) {
  final value = reader.string(key);
  if (value.isEmpty) {
    throw FormatException('${reader.type}.$key: expected non-empty string');
  }
  return value;
}

String _recoveryCode(JsonReader reader) {
  final value = _nonEmpty(reader, 'recoveryCode');
  if (normalizeRecoveryCode(value) == null) {
    throw FormatException(
      '${reader.type}.recoveryCode: not a recovery code '
      '(length=${value.length})',
    );
  }
  return formatRecoveryCode(value);
}

final authApiProvider = Provider<AuthApi>(
  (ref) => AuthApi(ref.watch(apiClientProvider)),
  name: 'authApi',
);
