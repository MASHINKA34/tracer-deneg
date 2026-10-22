import 'package:server/auth/tokens.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/auth_support.dart';
import 'support/test_support.dart';

const _login = 'tainyilogin.zz';
const _displayName = 'Тайное Имя Пользователя';
const _password = 'Пароль-Тайный-Длинный-77';
const _wrongPassword = 'Неверный-Тайный-Пароль-88';

void main() {
  late LogCapture logs;
  late AuthHarness api;

  setUp(() async {
    logs = LogCapture();
    api = await AuthHarness.start();
  });

  void expectNoSecrets(Iterable<String> secrets) {
    for (final secret in secrets) {
      expect(
        logs.text,
        isNot(contains(secret)),
        reason: 'secret in log: $secret',
      );
    }
    expect(logs.text, isNot(contains(r'$argon2id$')));
    expect(logs.text.toLowerCase(), isNot(contains(_login)));
    expect(logs.text, isNot(contains(_displayName)));
    expect(logs.text, isNot(contains(_password)));
    expect(logs.text, isNot(contains(_wrongPassword)));
  }

  Future<List<String>> storedHashes() async {
    final rows = await api.db.execute(
      'SELECT password_hash, recovery_hash FROM users',
    );
    return [
      for (final row in rows)
        for (final hash in row) (hash! as String).split(r'$').last,
    ];
  }

  test('полный цикл на debug: ни пароля, ни кода, ни токенов, ни хешей, логин маской', () async {
    final registered = await api.register(
      login: _login,
      displayName: _displayName,
      password: _password,
    );
    expect(registered.status, 201);
    final recoveryCode = registered.json['recoveryCode']! as String;
    final firstAccess = registered.json['accessToken']! as String;
    final firstRefresh = registered.json['refreshToken']! as String;

    expect(
      (await api.login(login: _login, password: _wrongPassword)).status,
      401,
    );
    expect(
      (await api.login(
        login: 'nobody.$_login',
        password: _wrongPassword,
      )).status,
      401,
    );
    final login = await api.login(
      login: _login.toUpperCase(),
      password: _password,
    );
    expect(login.status, 200);

    final rotated = await api.post(
      '/auth/refresh',
      body: {'refreshToken': firstRefresh},
    );
    expect(rotated.status, 200);
    final replay = await api.post(
      '/auth/refresh',
      body: {'refreshToken': firstRefresh},
    );
    expect(replay.status, 401);
    final loginAccess = login.json['accessToken']! as String;
    expect((await api.post('/auth/logout', bearer: loginAccess)).status, 204);
    expect((await api.post('/auth/logout', bearer: firstAccess)).status, 401);

    expect(logs.text, contains('login=ta***'));
    expect(logs.text, contains('register ok userId='));
    expect(logs.text, contains('reason=token_reused'));
    expectNoSecrets([
      recoveryCode,
      normalizeRecoveryCode(recoveryCode)!,
      firstAccess,
      firstRefresh,
      hashRefreshToken(firstRefresh),
      loginAccess,
      login.json['refreshToken']! as String,
      rotated.json['accessToken']! as String,
      rotated.json['refreshToken']! as String,
      hashRefreshToken(rotated.json['refreshToken']! as String),
      ...await storedHashes(),
    ]);
  });

  test('ошибка Postgres при записи пользователя: в логе SQLSTATE и ограничение, без хешей, логина и имени', () async {
    await api.db.execute(
      'ALTER TABLE users ADD CONSTRAINT test_reject_users CHECK (length(display_name) > 100)',
    );

    final response = await api.register(
      login: _login,
      displayName: _displayName,
      password: _password,
    );

    expect(response.status, 500);
    expect(response.errorCode, 'internal');
    expect(logs.text, contains('sqlState=23514'));
    expect(logs.text, contains('constraint test_reject_users'));
    expect(
      logs.text,
      contains('ERROR [http] unhandled error in POST /api/v1/auth/register'),
    );
    expectNoSecrets(const []);
  });

  test(
    'ошибка Postgres при ротации refresh: в логе нет ни токена, ни его хеша',
    () async {
      final registered = await api.register(
        login: _login,
        displayName: _displayName,
        password: _password,
      );
      final refresh = registered.json['refreshToken']! as String;
      await api.db.execute(
        'ALTER TABLE used_refresh_tokens ADD CONSTRAINT test_reject_used CHECK (length(refresh_hash) < 10)',
      );
      logs.clear();

      final response = await api.post(
        '/auth/refresh',
        body: {'refreshToken': refresh},
      );

      expect(response.status, 500);
      expect(logs.text, contains('sqlState=23514'));
      expect(logs.text, contains('constraint test_reject_used'));
      expect(logs.text, contains('transaction refresh rolled back'));
      expectNoSecrets([refresh, hashRefreshToken(refresh)]);
      final session = await api.db.execute('SELECT refresh_hash FROM sessions');
      expect(session.single.single, hashRefreshToken(refresh));
    },
  );
}
