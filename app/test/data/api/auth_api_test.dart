import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/api/api_client.dart';
import 'package:milionchik/data/api/api_config.dart';
import 'package:milionchik/data/api/api_exception.dart';
import 'package:milionchik/data/api/auth_api.dart';
import 'package:milionchik/data/api/token_store.dart';
import 'package:milionchik/data/session/session.dart';
import 'package:shared/shared.dart';

import 'fake_api_adapter.dart';

const _login = 'anyalogin';
const _password = 'Pass-Word-Auth-Api-Ninety-One';
const _access = 'access-token-auth-api-cccccccccccccc';
const _refresh = 'refresh-token-auth-api-dddddddddddddd';
const _recovery = 'RCVR-CODE-AUTHAPI-QWERTY';

Map<String, Object?> _user({String login = _login}) => {
  'id': 'user-server-42',
  'login': login,
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

  AuthApi api(FakeApiAdapter adapter, {AuthTokens? stored}) => AuthApi(
    ApiClient(
      config: config,
      tokens: MemoryTokenStore(stored),
      adapter: adapter,
      newRequestId: () => 'ridauthapi000001',
    ),
  );

  test('вход: POST /auth/login без Authorization, тело login/password/'
      'deviceName, ответ - сессия с пользователем и парой токенов', () async {
    final adapter = FakeApiAdapter(
      (call) => FakeReply.json(200, {
        'user': _user(),
        'accessToken': _access,
        'refreshToken': _refresh,
      }),
    );

    final result = await api(
      adapter,
      stored: const AuthTokens(accessToken: 'old-a', refreshToken: 'old-r'),
    ).login(login: _login, password: _password, deviceName: 'Pixel 7');

    final call = adapter.calls.single;
    expect(call.method, 'POST');
    expect(call.path, '/api/v1/auth/login');
    expect(call.header('Authorization'), isNull);
    expect(call.json, {
      'login': _login,
      'password': _password,
      'deviceName': 'Pixel 7',
    });
    expect(
      result.session.user,
      const SessionUser(
        userId: 'user-server-42',
        login: _login,
        displayName: 'Аня',
      ),
    );
    expect(result.session.tokens.accessToken, _access);
    expect(result.session.tokens.refreshToken, _refresh);
    expect(result.recoveryCode, isNull);
    expect(result.requestId, 'ridauthapi000001');
  });

  test('регистрация: POST /auth/register с именем, ответ 201 с кодом '
      'восстановления', () async {
    final adapter = FakeApiAdapter(
      (call) => FakeReply.json(201, {
        'user': _user(),
        'accessToken': _access,
        'refreshToken': _refresh,
        'recoveryCode': _recovery,
      }),
    );

    final result = await api(adapter).register(
      login: _login,
      displayName: 'Аня',
      password: _password,
      deviceName: 'Pixel 7',
    );

    final call = adapter.calls.single;
    expect(call.path, '/api/v1/auth/register');
    expect(call.header('Authorization'), isNull);
    expect(call.json, {
      'login': _login,
      'displayName': 'Аня',
      'password': _password,
      'deviceName': 'Pixel 7',
    });
    expect(result.recoveryCode, _recovery);
    expect(result.session.user.userId, 'user-server-42');
    expect(result.toString(), isNot(contains(_recovery)));
  });

  test('401 bad_credentials при входе - ApiErrorResponse с кодом, refresh не '
      'вызывается', () async {
    final adapter = FakeApiAdapter(
      (call) => FakeReply.error(401, 'bad_credentials', 'Неверный логин'),
    );

    final error =
        await api(
              adapter,
              stored: const AuthTokens(
                accessToken: 'old-a',
                refreshToken: 'old-r',
              ),
            )
            .login(login: _login, password: _password, deviceName: 'Pixel 7')
            .then<Object?>((_) => null, onError: (Object e) => e);

    expect(error, isA<ApiErrorResponse>());
    expect((error! as ApiErrorResponse).code, ApiErrorCode.badCredentials);
    expect(adapter.callsTo('/auth/refresh'), isEmpty);
    expect(adapter.calls, hasLength(1));
  });

  test(
    '409 login_taken при регистрации - ApiErrorResponse loginTaken',
    () async {
      final adapter = FakeApiAdapter(
        (call) => FakeReply.error(409, 'login_taken', 'Такой логин уже занят'),
      );

      final error = await api(adapter)
          .register(
            login: _login,
            displayName: 'Аня',
            password: _password,
            deviceName: 'Pixel 7',
          )
          .then<Object?>((_) => null, onError: (Object e) => e);

      final response = error! as ApiErrorResponse;
      expect(response.code, ApiErrorCode.loginTaken);
      expect(response.statusCode, 409);
    },
  );

  test('ответ 200 без токенов - ApiBadResponse и warn [auth] без значений '
      'полей', () async {
    final adapter = FakeApiAdapter(
      (call) => FakeReply.json(200, {'user': _user(), 'accessToken': _access}),
    );

    final error = await api(adapter)
        .login(login: _login, password: _password, deviceName: 'Pixel 7')
        .then<Object?>((_) => null, onError: (Object e) => e);

    expect(error, isA<ApiBadResponse>());
    final bad = error! as ApiBadResponse;
    expect(bad.path, '/api/v1/auth/login');
    expect(bad.requestId, 'ridauthapi000001');
    expect(bad.reason, contains('AuthResponse.refreshToken: expected string'));
    final warning = logs.linesOf('auth', Level.WARNING).single;
    expect(
      warning,
      contains(
        'POST /auth/login 200 answered without {user, accessToken, '
        'refreshToken} → bad response',
      ),
    );
    expect(warning, contains('rid=ridauthapi000001'));
    expect(logs.text, isNot(contains(_access)));
  });

  test(
    'регистрация без кода восстановления в ответе - ApiBadResponse',
    () async {
      final adapter = FakeApiAdapter(
        (call) => FakeReply.json(201, {
          'user': _user(),
          'accessToken': _access,
          'refreshToken': _refresh,
        }),
      );

      final error = await api(adapter)
          .register(
            login: _login,
            displayName: 'Аня',
            password: _password,
            deviceName: 'Pixel 7',
          )
          .then<Object?>((_) => null, onError: (Object e) => e);

      expect(error, isA<ApiBadResponse>());
      expect(
        (error! as ApiBadResponse).reason,
        contains('AuthResponse.recoveryCode'),
      );
    },
  );

  test('debug-лог входа и регистрации: ни пароля, ни токенов, ни кода, ни '
      'логина целиком', () async {
    final adapter = FakeApiAdapter(
      (call) => call.path.endsWith('/register')
          ? FakeReply.json(201, {
              'user': _user(),
              'accessToken': _access,
              'refreshToken': _refresh,
              'recoveryCode': _recovery,
            })
          : FakeReply.json(200, {
              'user': _user(),
              'accessToken': _access,
              'refreshToken': _refresh,
            }),
    );
    final client = api(adapter);

    await client.login(login: _login, password: _password, deviceName: 'X');
    await client.register(
      login: _login,
      displayName: 'Аня',
      password: _password,
      deviceName: 'X',
    );

    final text = logs.text;
    expect(text, contains('POST /api/v1/auth/login 200'));
    expect(text, contains('POST /api/v1/auth/register 201'));
    for (final secret in [_password, _access, _refresh, _recovery, _login]) {
      expect(text, isNot(contains(secret)), reason: '$secret leaked:\n$text');
    }
  });
}
