import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/data/api/api_client.dart';
import 'package:milionchik/data/api/api_config.dart';
import 'package:milionchik/data/api/api_exception.dart';
import 'package:milionchik/data/api/auth_api.dart';
import 'package:milionchik/data/api/token_store.dart';
import 'package:shared/shared.dart';

import 'fake_api_adapter.dart';

const _login = 'anyalogin';
const _password = 'Pass-Word-Recover-Api-Thirty-Two';
const _access = 'access-token-recover-api-eeeeeeeeeeee';
const _refresh = 'refresh-token-recover-api-ffffffffffff';
const _oldCode = 'QWTYZXCVRSTK';
const _newCode = 'MNPQ-RSTV-WXYZ';

Map<String, Object?> _user() => {
  'id': 'user-server-42',
  'login': _login,
  'displayName': 'Аня',
  'birthdayMonth': null,
  'birthdayDay': null,
  'holidaysEnabled': true,
  'holidaysDisabled': <String>[],
  'createdAt': '2026-10-19T15:40:00.000Z',
};

void main() {
  late LogCapture logs;
  final config = ApiConfig.resolve(define: '', debugBuild: true);

  setUp(() => logs = LogCapture());
  tearDown(() => logs.dispose());

  AuthApi api(FakeApiAdapter adapter) => AuthApi(
    ApiClient(
      config: config,
      tokens: MemoryTokenStore(),
      adapter: adapter,
      newRequestId: () => 'ridrecoverapi001',
    ),
  );

  Future<Object?> recover(FakeApiAdapter adapter) => api(adapter)
      .recover(
        login: _login,
        recoveryCode: _oldCode,
        newPassword: _password,
        deviceName: 'Pixel 7',
      )
      .then<Object?>((r) => r, onError: (Object e) => e);

  test('POST /auth/recover без Authorization: login, recoveryCode, '
      'newPassword, deviceName; ответ - сессия и новый код группами', () async {
    final adapter = FakeApiAdapter(
      (call) => FakeReply.json(200, {
        'user': _user(),
        'accessToken': _access,
        'refreshToken': _refresh,
        'recoveryCode': 'mnpqrstvwxyz',
      }),
    );

    final result = await recover(adapter) as AuthResult;

    final call = adapter.calls.single;
    expect(call.method, 'POST');
    expect(call.path, '/api/v1/auth/recover');
    expect(call.header('Authorization'), isNull);
    expect(call.json, {
      'login': _login,
      'recoveryCode': _oldCode,
      'newPassword': _password,
      'deviceName': 'Pixel 7',
    });
    expect(result.recoveryCode, _newCode);
    expect(result.session.user.userId, 'user-server-42');
    expect(result.session.tokens.accessToken, _access);
    expect(result.requestId, 'ridrecoverapi001');
    expect(result.toString(), isNot(contains(_newCode)));
  });

  test('ответ без кода или с кодом не по формату - ApiBadResponse, кода нет '
      'ни в причине, ни в логе', () async {
    for (final code in [null, '', 'MNPQ-RSTV', 'MNPQ-RSTV-WXYU']) {
      final adapter = FakeApiAdapter(
        (call) => FakeReply.json(200, {
          'user': _user(),
          'accessToken': _access,
          'refreshToken': _refresh,
          'recoveryCode': ?code,
        }),
      );

      final error = await recover(adapter);

      expect(error, isA<ApiBadResponse>(), reason: '$code');
      final reason = (error! as ApiBadResponse).reason;
      expect(reason, contains('AuthResponse.recoveryCode'), reason: '$code');
      if (code != null && code.isNotEmpty) {
        expect(reason, isNot(contains(code)));
        expect(logs.text, isNot(contains(code)));
      }
    }
  });

  test('401 bad_credentials - ApiErrorResponse с кодом, refresh не '
      'вызывается', () async {
    final adapter = FakeApiAdapter(
      (call) => FakeReply.error(
        401,
        'bad_credentials',
        'Неверный логин или код восстановления',
      ),
    );

    final error = await recover(adapter);

    expect(error, isA<ApiErrorResponse>());
    expect((error! as ApiErrorResponse).code, ApiErrorCode.badCredentials);
    expect(adapter.calls, hasLength(1));
  });

  test('debug-лог восстановления: ни пароля, ни токенов, ни старого и нового '
      'кода, ни логина целиком', () async {
    final adapter = FakeApiAdapter(
      (call) => FakeReply.json(200, {
        'user': _user(),
        'accessToken': _access,
        'refreshToken': _refresh,
        'recoveryCode': _newCode,
      }),
    );

    await recover(adapter);

    final text = logs.text;
    expect(text, contains('POST /api/v1/auth/recover 200'));
    expect(text, contains('recoveryCode'));
    for (final secret in [
      _password,
      _access,
      _refresh,
      _oldCode,
      _newCode,
      _newCode.replaceAll('-', ''),
      _login,
    ]) {
      expect(text, isNot(contains(secret)), reason: '$secret leaked:\n$text');
    }
  });
}
