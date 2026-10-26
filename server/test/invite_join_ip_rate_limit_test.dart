import 'package:test/test.dart';

import 'support/auth_support.dart';
import 'support/limits_support.dart';
import 'support/test_support.dart';

void main() {
  late LogCapture logs;
  late LimitsHarness api;

  setUp(() async {
    logs = LogCapture();
    api = await LimitsHarness.start();
  });

  Future<ApiResponse> join({String ip = defaultTestIp, String? token}) =>
      api.post(
        '/invites/join',
        body: const {'code': 'MLN-0000'},
        ip: ip,
        headers: {'authorization': ?(token == null ? null : 'Bearer $token')},
      );

  Future<ApiResponse> refresh({String ip = defaultTestIp}) =>
      api.post('/auth/refresh', body: const {}, ip: ip);

  void expectBlocked(ApiResponse response, String retryAfter) {
    expect(response.status, 429, reason: '$response');
    expect(response.errorCode, 'too_many_attempts');
    expect(response.headers['retry-after'], retryAfter);
  }

  test('30 запросов в минуту с IP проходят, 31-й → 429 с Retry-After; '
      'другой IP не затронут; через минуту снова можно', () async {
    final anna = await api.register('anna');
    expect(anna.status, 201, reason: '$anna');
    final token = anna.json['accessToken']! as String;
    logs.clear();

    for (var i = 0; i < 30; i++) {
      final response = await join();
      expect(response.status, 401, reason: 'request ${i + 1}: $response');
    }
    expectBlocked(await join(), '60');
    expectBlocked(await join(token: token), '60');
    expect(
      logs.text,
      contains(
        'WARN  [limits] ip rate limit hit limiter=invite-join-ip '
        'ip=$defaultTestIp POST /api/v1/invites/join limit=30/60s '
        'retryAfter=60s',
      ),
    );

    final other = await join(ip: '198.51.100.2', token: token);
    expect(other.status, 404, reason: '$other');
    expect(other.errorCode, 'invite_not_found');

    api.clock.advance(const Duration(seconds: 60));
    final later = await join(token: token);
    expect(later.status, 404, reason: '$later');
  });

  test(
    'свой счётчик: /auth/* не тратит лимит /invites/join и наоборот',
    () async {
      for (var i = 0; i < 30; i++) {
        final response = await refresh();
        expect(response.status, 400, reason: 'refresh ${i + 1}: $response');
      }
      expectBlocked(await refresh(), '60');
      final joinAfterAuth = await join();
      expect(joinAfterAuth.status, 401, reason: '$joinAfterAuth');

      const ip = '198.51.100.3';
      for (var i = 0; i < 30; i++) {
        final response = await join(ip: ip);
        expect(response.status, 401, reason: 'join ${i + 1}: $response');
      }
      expectBlocked(await join(ip: ip), '60');
      final authAfterJoin = await refresh(ip: ip);
      expect(authAfterJoin.status, 400, reason: '$authAfterJoin');
    },
  );
}
