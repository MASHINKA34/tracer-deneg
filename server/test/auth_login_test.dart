import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/auth_support.dart';
import 'support/test_support.dart';

void main() {
  late LogCapture logs;
  late AuthHarness api;
  late String userId;

  setUp(() async {
    logs = LogCapture();
    api = await AuthHarness.start();
    final registered = await api.register(login: 'anna');
    userId =
        (registered.json['user']! as Map<String, Object?>)['id']! as String;
    logs.clear();
  });

  group('POST /auth/login', () {
    test('верный пароль → 200: пользователь, новая сессия и пара токенов', () async {
      final response = await api.login(
        login: ' ANNA ',
        deviceName: 'Galaxy S24',
      );

      expect(response.status, 200);
      expect(response.headers['cache-control'], 'no-store');
      final body = response.json;
      expect(
        body.keys,
        unorderedEquals(['user', 'accessToken', 'refreshToken']),
      );
      final user = User.fromJson(body['user']);
      expect(user.id, userId);
      expect(user.login, 'anna');
      expect(user.displayName, 'Аня');

      final claims = api.auth.accessTokens
          .verify(body['accessToken']! as String)
          .claims!;
      expect(claims.userId, userId);
      final sessions = await api.db.execute(
        r'SELECT id, device_name FROM sessions WHERE user_id = $1::uuid ORDER BY created_at',
        parameters: [userId],
      );
      expect(sessions, hasLength(2));
      expect(sessions.last.toList(), [claims.sessionId, 'Galaxy S24']);
      expect(
        logs.text,
        contains(
          RegExp(
            'INFO  \\[auth\\] login ok userId=$userId sessionId=${claims.sessionId} in \\d+ms',
          ),
        ),
      );
    });

    test('неверный пароль и несуществующий логин — одинаковый ответ 401 bad_credentials', () async {
      final wrongPassword = await api.login(password: 'wrong-pass-1');
      final noSuchLogin = await api.login(
        login: 'nobody',
        password: 'wrong-pass-1',
      );

      expect(wrongPassword.status, 401);
      expect(noSuchLogin.status, 401);
      expect(wrongPassword.json, {
        'error': {
          'code': 'bad_credentials',
          'message': 'Неверный логин или пароль',
        },
      });
      expect(noSuchLogin.text, wrongPassword.text);
      expect(
        noSuchLogin.headers['content-type'],
        wrongPassword.headers['content-type'],
      );
      expect(await api.count('SELECT count(*)::int FROM sessions'), 1);

      expect(
        logs.text,
        contains(
          'WARN  [auth] login rejected reason=bad_credentials login=an*** userId=$userId',
        ),
      );
      expect(
        logs.text,
        contains(
          'WARN  [auth] login rejected reason=bad_credentials login=no*** userFound=false',
        ),
      );
      expect(
        RegExp(
          r'DEBUG \[auth\] argon2id verify purpose=password m=19456,t=2,p=1 match=false',
        ).allMatches(logs.text),
        hasLength(2),
      );
    });

    test('удалённый аккаунт не входит: 401 bad_credentials', () async {
      await api.db.execute(
        r'UPDATE users SET deleted_at = now() WHERE id = $1::uuid',
        parameters: [userId],
      );
      final response = await api.login();
      expect(response.status, 401);
      expect(response.errorCode, 'bad_credentials');
    });

    test('нет пароля в теле → 400 bad_request', () async {
      final response = await api.post(
        '/auth/login',
        body: {'login': 'anna', 'deviceName': 'Pixel'},
      );
      expect(response.status, 400);
      expect(response.errorCode, 'bad_request');
      expect(
        logs.text,
        contains('login rejected reason=bad_request fields=password'),
      );
    });
  });
}
