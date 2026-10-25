import 'package:test/test.dart';

import 'support/auth_support.dart';
import 'support/limits_support.dart';
import 'support/test_support.dart';

const _wrong = 'Wrong-Pass-Zeta-Kappa';

void main() {
  late LogCapture logs;
  late LimitsHarness api;
  late String annaToken;
  late String annaId;
  late String borisToken;

  setUp(() async {
    logs = LogCapture();
    api = await LimitsHarness.start();
    final anna = await api.register('anna');
    expect(anna.status, 201);
    annaToken = anna.json['accessToken']! as String;
    annaId = (anna.json['user']! as Map<String, Object?>)['id']! as String;
    final boris = await api.register('boris');
    expect(boris.status, 201);
    borisToken = boris.json['accessToken']! as String;
    logs.clear();
  });

  Future<ApiResponse> deleteAccount(
    String password, {
    String? token,
    String? ip,
  }) => api.send(
    'DELETE',
    '/account',
    body: {'password': password},
    headers: {'authorization': 'Bearer ${token ?? annaToken}'},
    ip: ip ?? defaultTestIp,
  );

  Future<void> failDeletes(int times, {String? token}) async {
    for (var i = 0; i < times; i++) {
      final response = await deleteAccount(_wrong, token: token);
      expect(response.status, 401, reason: 'attempt ${i + 1}: $response');
      expect(response.errorCode, 'bad_credentials');
    }
  }

  void expectBlocked(ApiResponse response, String retryAfter) {
    expect(response.status, 429, reason: '$response');
    expect(response.errorCode, 'too_many_attempts');
    expect(response.headers['retry-after'], retryAfter);
  }

  Future<bool> alive(String login) async =>
      await api.count(
        r'SELECT count(*)::int FROM users WHERE login = $1 '
        'AND deleted_at IS NULL',
        [login],
      ) ==
      1;

  group('неверные пароли при удалении аккаунта: 5 за 15 минут', () {
    test('пять неверных → 401, шестая попытка → 429 с Retry-After 900, '
        'верный пароль тоже 429, аккаунт жив', () async {
      await failDeletes(5);

      final sixth = await deleteAccount(_wrong);
      expectBlocked(sixth, '900');
      final message =
          (sixth.json['error']! as Map<String, Object?>)['message']! as String;
      expect(message, contains('15 мин'));

      expectBlocked(await deleteAccount('right-pass-anna'), '900');
      expect(await alive('anna'), isTrue);
      expect(
        (await api.send(
          'GET',
          '/me',
          headers: {'authorization': 'Bearer $annaToken'},
        )).status,
        200,
      );

      api.clock.advance(const Duration(minutes: 15));
      final afterWindow = await deleteAccount(_wrong);
      expect(afterWindow.status, 401);
      expect(afterWindow.errorCode, 'bad_credentials');
    });

    test('счётчик общий со входом: неудачи удаления блокируют вход', () async {
      await failDeletes(5);

      expectBlocked(await api.login('anna', 'right-pass-anna'), '900');
      final borisLogin = await api.login('boris', 'right-pass-boris');
      expect(borisLogin.status, 200);
    });

    test('и наоборот: неудачи входа блокируют удаление', () async {
      for (var i = 0; i < 5; i++) {
        expect((await api.login('boris', _wrong)).status, 401);
      }

      expectBlocked(
        await deleteAccount('right-pass-boris', token: borisToken),
        '900',
      );
      expect(await alive('boris'), isTrue);
    });

    test(
      'верный пароль после неудач удаляет аккаунт и обнуляет счётчик',
      () async {
        await failDeletes(4);
        expect(api.limits.loginFailures.count('anna'), 4);

        final response = await deleteAccount('right-pass-anna');

        expect(response.status, 204);
        expect(await alive('anna'), isFalse);
        expect(api.limits.loginFailures.count('anna'), 0);
      },
    );

    test('запрос без пароля в теле не считается неудачей', () async {
      for (var i = 0; i < 6; i++) {
        final response = await api.send(
          'DELETE',
          '/account',
          body: <String, Object?>{},
          headers: {'authorization': 'Bearer $annaToken'},
        );
        expect(response.status, 400);
      }
      expect(api.limits.loginFailures.count('anna'), 0);
      expect((await deleteAccount('right-pass-anna')).status, 204);
    });

    test('в логе: счёт неудач и блокировка, без пароля и с маской логина', () async {
      await failDeletes(5);
      expectBlocked(await deleteAccount(_wrong), '900');

      expect(
        logs.text,
        contains(
          'DEBUG [account] account deletion failure recorded '
          'userId=$annaId login=an*** failures=1/5',
        ),
      );
      expect(
        logs.text,
        contains(
          'WARN  [account] account deletion attempts exhausted '
          'userId=$annaId login=an*** failures=5/5 window=15m '
          '→ next attempts blocked for 900s',
        ),
      );
      expect(
        logs.text,
        contains(
          'WARN  [account] account deletion blocked: login attempts limit hit '
          'userId=$annaId login=an*** failures=5/5 window=15m '
          'retryAfter=900s',
        ),
      );
      expect(logs.text, isNot(contains(_wrong)));
      expect(logs.text, isNot(contains('right-pass-anna')));
      expect(logs.text, isNot(contains('login=anna')));
    });
  });

  group('IP-лимит: общий с /auth/*, 30 запросов в минуту', () {
    test('31-й запрос на удаление с IP → 429 с Retry-After 60, '
        'другой IP не затронут', () async {
      for (var i = 0; i < 30; i++) {
        final response = await api.send('DELETE', '/account', body: const {});
        expect(response.status, 401, reason: 'request ${i + 1}');
      }

      expectBlocked(await api.send('DELETE', '/account', body: const {}), '60');
      final other = await api.send(
        'DELETE',
        '/account',
        body: const {},
        ip: '198.51.100.7',
      );
      expect(other.status, 401);
    });

    test('удаление и /auth/* тратят один счётчик IP', () async {
      for (var i = 0; i < 15; i++) {
        expect(
          (await api.send('DELETE', '/account', body: const {})).status,
          401,
        );
        expect((await api.post('/auth/refresh', body: const {})).status, 400);
      }

      expectBlocked(await api.post('/auth/refresh', body: const {}), '60');
      expectBlocked(await deleteAccount('right-pass-anna'), '60');
      expect(await alive('anna'), isTrue);
      expect(
        logs.text,
        contains(
          'WARN  [limits] ip rate limit hit limiter=auth-ip '
          'ip=$defaultTestIp DELETE /api/v1/account limit=30/60s '
          'retryAfter=60s',
        ),
      );
    });
  });
}
