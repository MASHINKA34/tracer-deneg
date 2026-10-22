import 'package:test/test.dart';

import 'support/auth_support.dart';
import 'support/limits_support.dart';
import 'support/test_support.dart';

const _wrong = 'Wrong-Pass-Zeta-Kappa';

void main() {
  late LogCapture logs;
  late LimitsHarness api;

  setUp(() async {
    logs = LogCapture();
    api = await LimitsHarness.start();
    expect((await api.register('anna')).status, 201);
    expect((await api.register('boris')).status, 201);
    logs.clear();
  });

  Future<void> failTimes(String login, int times) async {
    for (var i = 0; i < times; i++) {
      final response = await api.login(login, _wrong);
      expect(response.status, 401, reason: 'attempt ${i + 1}: $response');
      expect(response.errorCode, 'bad_credentials');
    }
  }

  void expectBlocked(ApiResponse response, String retryAfter) {
    expect(response.status, 429, reason: '$response');
    expect(response.errorCode, 'too_many_attempts');
    expect(response.headers['retry-after'], retryAfter);
  }

  group('5 неудач входа на логин за 15 минут', () {
    test('пять неверных паролей → 401, шестая попытка → 429 с Retry-After 900, '
        'верный пароль тоже 429 и сессия не создаётся', () async {
      for (final login in ['anna', 'ANNA', ' Anna ', 'anna', 'aNNa']) {
        final response = await api.login(login, _wrong);
        expect(response.status, 401);
        expect(response.errorCode, 'bad_credentials');
      }

      final sixth = await api.login('anna', _wrong);
      expectBlocked(sixth, '900');
      final message =
          (sixth.json['error']! as Map<String, Object?>)['message']! as String;
      expect(message, contains('15 мин'));

      final sessionsBefore = await api.count(
        "SELECT count(*)::int FROM sessions s JOIN users u ON u.id = s.user_id "
        "WHERE u.login = 'anna'",
      );
      final right = await api.login('anna', 'right-pass-anna');
      expectBlocked(right, '900');
      final sessionsAfter = await api.count(
        "SELECT count(*)::int FROM sessions s JOIN users u ON u.id = s.user_id "
        "WHERE u.login = 'anna'",
      );
      expect(sessionsAfter, sessionsBefore);
    });

    test('через 15 минут (подмена часов) снова можно; за секунду до — 429 '
        'с Retry-After 1', () async {
      await failTimes('anna', 5);

      api.clock.advance(const Duration(minutes: 14, seconds: 59));
      expectBlocked(await api.login('anna', 'right-pass-anna'), '1');

      api.clock.advance(const Duration(seconds: 1));
      final ok = await api.login('anna', 'right-pass-anna');
      expect(ok.status, 200, reason: '$ok');
    });

    test('окно скользящее: Retry-After считается от самой старой неудачи '
        'в окне', () async {
      await failTimes('anna', 1);
      api.clock.advance(const Duration(minutes: 5));
      await failTimes('anna', 4);
      expectBlocked(await api.login('anna', _wrong), '600');

      api.clock.advance(const Duration(minutes: 10));
      await failTimes('anna', 1);
      expectBlocked(await api.login('anna', _wrong), '300');
    });

    test('успешный вход другого логина не сбрасывает чужой счётчик', () async {
      await failTimes('anna', 4);
      final boris = await api.login('boris', 'right-pass-boris');
      expect(boris.status, 200);
      await failTimes('anna', 1);
      expectBlocked(await api.login('anna', 'right-pass-anna'), '900');

      final borisAgain = await api.login('boris', 'right-pass-boris');
      expect(borisAgain.status, 200, reason: 'у boris своих неудач нет');
    });

    test('успешный вход сбрасывает свой счётчик', () async {
      await failTimes('anna', 4);
      expect((await api.login('anna', 'right-pass-anna')).status, 200);
      await failTimes('anna', 5);
      expectBlocked(await api.login('anna', _wrong), '900');
    });

    test('неудачи восстановления и входа считаются вместе', () async {
      for (var i = 0; i < 3; i++) {
        final response = await api.recover('anna', 'AAAA-BBBB-CCCC');
        expect(response.status, 401, reason: '$response');
      }
      await failTimes('anna', 2);
      expectBlocked(await api.recover('anna', 'AAAA-BBBB-CCCC'), '900');
      expectBlocked(await api.login('anna', 'right-pass-anna'), '900');
    });

    test('несуществующий логин блокируется так же, как существующий', () async {
      await failTimes('nobody', 5);
      await failTimes('anna', 5);
      final ghost = await api.login('nobody', _wrong);
      final real = await api.login('anna', _wrong);
      expectBlocked(ghost, '900');
      expectBlocked(real, '900');
      expect(ghost.text, real.text);
    });

    test('одновременные попытки не обходят лимит: из 10 разом 5 → 401, '
        '5 → 429', () async {
      final results = await Future.wait([
        for (var i = 0; i < 10; i++) api.login('anna', _wrong),
      ]);
      final statuses = results.map((r) => r.status).toList()..sort();
      expect(statuses, [...List.filled(5, 401), ...List.filled(5, 429)]);
      expectBlocked(await api.login('anna', 'right-pass-anna'), '900');
    });

    test('неверный запрос (400) не считается неудачей', () async {
      for (var i = 0; i < 6; i++) {
        final response = await api.post(
          '/auth/login',
          body: {'login': 'anna', 'deviceName': 'Pixel 7'},
        );
        expect(response.status, 400);
      }
      for (var i = 0; i < 6; i++) {
        final response = await api.post(
          '/auth/recover',
          body: {
            'login': 'anna',
            'recoveryCode': 'AAAA-BBBB-CCCC',
            'newPassword': '123',
            'deviceName': 'Pixel 7',
          },
        );
        expect(response.status, 400);
        expect(response.errorCode, 'password_too_short');
      }
      expect((await api.login('anna', 'right-pass-anna')).status, 200);
    });
  });

  test('лог: срабатывание лимита на warn с маской логина и временем ожидания, '
      'без логина и пароля открытым текстом', () async {
    await failTimes('anna', 5);
    await api.login('anna', _wrong);

    final limitLines = logs.lines.where((l) => l.contains('[limits]')).toList();
    expect(
      limitLines,
      contains(
        allOf(
          contains('WARN'),
          contains(
            'login attempts exhausted operation=login login=an*** '
            'failures=5/5 window=15m → next attempts blocked for 900s',
          ),
        ),
      ),
    );
    expect(
      limitLines,
      contains(
        allOf(
          contains('WARN'),
          contains(
            'login attempts limit hit operation=login login=an*** '
            'failures=5/5 window=15m retryAfter=900s',
          ),
        ),
      ),
    );
    expect(
      limitLines,
      contains(contains('login failure recorded login=an*** failures=1/5')),
    );
    for (final line in limitLines) {
      expect(line, isNot(contains('anna')));
    }
    expect(logs.text, isNot(contains(_wrong)));
    expect(logs.text, isNot(contains('right-pass-anna')));
  });
}
