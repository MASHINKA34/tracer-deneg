import 'package:server/limits/trusted_proxies.dart';
import 'package:test/test.dart';

import 'support/auth_support.dart';
import 'support/limits_support.dart';
import 'support/test_support.dart';

void main() {
  late LogCapture logs;
  late LimitsHarness api;

  setUp(() async {
    logs = LogCapture();
    api = await LimitsHarness.start(
      trustedProxies: TrustedProxies.parse('10.0.0.2'),
    );
  });

  Future<ApiResponse> refresh({
    String? ip = defaultTestIp,
    Map<String, String> headers = const {},
  }) => api.post('/auth/refresh', body: const {}, ip: ip, headers: headers);

  Future<void> allowedTimes(
    int times,
    Future<ApiResponse> Function() call,
  ) async {
    for (var i = 0; i < times; i++) {
      final response = await call();
      expect(response.status, isNot(429), reason: 'request ${i + 1}');
    }
  }

  void expectBlocked(ApiResponse response, String retryAfter) {
    expect(response.status, 429, reason: '$response');
    expect(response.errorCode, 'too_many_attempts');
    expect(response.headers['retry-after'], retryAfter);
  }

  group('/auth/*: 30 запросов в минуту с IP', () {
    test('30 запросов проходят, 31-й → 429 с Retry-After 60; другой IP '
        'не затронут', () async {
      for (var i = 0; i < 30; i++) {
        final response = i.isEven
            ? await refresh()
            : await api.post('/auth/login', body: const {});
        expect(response.status, 400, reason: 'request ${i + 1}');
      }
      expectBlocked(await refresh(), '60');
      expectBlocked(await api.login('anna', 'whatever-pass'), '60');

      final other = await refresh(ip: '198.51.100.2');
      expect(other.status, 400);
    });

    test(
      'окно скользящее; отклонённые запросы не продлевают блокировку',
      () async {
        await allowedTimes(10, refresh);
        api.clock.advance(const Duration(seconds: 20));
        await allowedTimes(20, refresh);
        expectBlocked(await refresh(), '40');
        for (var i = 0; i < 10; i++) {
          expectBlocked(await refresh(), '40');
        }

        api.clock.advance(const Duration(seconds: 40));
        await allowedTimes(10, refresh);
        expectBlocked(await refresh(), '20');

        api.clock.advance(const Duration(seconds: 20));
        await allowedTimes(20, refresh);
      },
    );

    test('/health и /me не ограничены по IP', () async {
      for (var i = 0; i < 40; i++) {
        expect((await api.send('GET', '/health')).status, 200);
        expect((await api.send('GET', '/me')).status, 401);
      }
    });
  });

  group('/client-errors: 20 запросов в минуту с IP', () {
    test(
      '20 проходят до обработчика, 21-й → 429; лимит /auth отдельный',
      () async {
        await allowedTimes(
          20,
          () => api.post('/client-errors', body: const {'kind': 'crash'}),
        );
        expectBlocked(
          await api.post('/client-errors', body: const {'kind': 'crash'}),
          '60',
        );
        expect((await refresh()).status, 400);
        final otherIp = await api.post(
          '/client-errors',
          body: const {'kind': 'crash'},
          ip: '198.51.100.3',
        );
        expect(otherIp.status, isNot(429));
      },
    );
  });

  group('IP за прокси', () {
    test('от доверенного прокси ключ — адрес из X-Forwarded-For', () async {
      await allowedTimes(
        30,
        () => refresh(
          ip: '10.0.0.2',
          headers: {'x-forwarded-for': '203.0.113.5'},
        ),
      );
      expectBlocked(
        await refresh(
          ip: '10.0.0.2',
          headers: {'x-forwarded-for': '203.0.113.5'},
        ),
        '60',
      );
      final neighbour = await refresh(
        ip: '10.0.0.2',
        headers: {'x-forwarded-for': '203.0.113.6'},
      );
      expect(neighbour.status, 400);
    });

    test(
      'X-Forwarded-For от недоверенного адреса не даёт новый ключ',
      () async {
        for (var i = 0; i < 30; i++) {
          final response = await refresh(
            ip: '198.51.100.7',
            headers: {'x-forwarded-for': '203.0.113.${i + 1}'},
          );
          expect(response.status, 400);
        }
        expectBlocked(
          await refresh(
            ip: '198.51.100.7',
            headers: {'x-forwarded-for': '203.0.113.200'},
          ),
          '60',
        );
      },
    );

    test('без TRUSTED_PROXIES заголовок прокси не учитывается', () async {
      final plain = await LimitsHarness.start();
      for (var i = 0; i < 30; i++) {
        final response = await plain.post(
          '/auth/refresh',
          body: const {},
          ip: '10.0.0.2',
          headers: {'x-forwarded-for': '203.0.113.${i + 1}'},
        );
        expect(response.status, 400);
      }
      final blocked = await plain.post(
        '/auth/refresh',
        body: const {},
        ip: '10.0.0.2',
        headers: {'x-forwarded-for': '203.0.113.99'},
      );
      expectBlocked(blocked, '60');
    });
  });

  test('лог: срабатывание лимита по IP на warn — какой лимит, IP, сколько '
      'ждать', () async {
    await allowedTimes(30, refresh);
    logs.clear();
    await refresh();
    expect(
      logs.lines,
      contains(
        allOf(
          contains('WARN'),
          contains('[limits]'),
          contains(
            'ip rate limit hit limiter=auth-ip ip=$defaultTestIp '
            'POST /api/v1/auth/refresh limit=30/60s retryAfter=60s',
          ),
        ),
      ),
    );
  });

  test('очистка старых счётчиков на debug', () async {
    await allowedTimes(3, refresh);
    await allowedTimes(3, () => refresh(ip: '198.51.100.9'));
    expect(api.limits.authRequests.trackedKeys, 2);

    api.clock.advance(const Duration(minutes: 2));
    await refresh(ip: '198.51.100.10');

    expect(api.limits.authRequests.trackedKeys, 1);
    expect(
      logs.lines,
      contains(
        allOf(
          contains('DEBUG'),
          contains('[limits] cleanup limiter=auth-ip removed=2 kept=0'),
        ),
      ),
    );
  });
}
