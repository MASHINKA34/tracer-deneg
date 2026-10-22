import 'package:test/test.dart';

import 'support/auth_support.dart';
import 'support/test_support.dart';

void main() {
  late LogCapture logs;
  late AuthHarness api;
  late String userId;
  late String sessionId;
  late String accessToken;
  late String refreshToken;

  setUp(() async {
    logs = LogCapture();
    api = await AuthHarness.start();
    final registered = await api.register();
    userId =
        (registered.json['user']! as Map<String, Object?>)['id']! as String;
    accessToken = registered.json['accessToken']! as String;
    refreshToken = registered.json['refreshToken']! as String;
    sessionId = api.auth.accessTokens.verify(accessToken).claims!.sessionId;
    logs.clear();
  });

  Future<bool> revoked(String id) async {
    final rows = await api.db.execute(
      r'SELECT revoked_at IS NOT NULL FROM sessions WHERE id = $1::uuid',
      parameters: [id],
    );
    return rows.single.single! as bool;
  }

  group('POST /auth/logout', () {
    test('204 без тела, текущая сессия отозвана', () async {
      final response = await api.post('/auth/logout', bearer: accessToken);
      expect(response.status, 204);
      expect(response.text, isEmpty);
      expect(await revoked(sessionId), isTrue);
      expect(
        logs.text,
        contains(
          RegExp(
            'INFO  \\[auth\\] logout ok userId=$userId sessionId=$sessionId revoked=true in \\d+ms',
          ),
        ),
      );
    });

    test('refresh после logout → 401 session_expired', () async {
      await api.post('/auth/logout', bearer: accessToken);
      final response = await api.post(
        '/auth/refresh',
        body: {'refreshToken': refreshToken},
      );
      expect(response.status, 401);
      expect(response.errorCode, 'session_expired');
    });

    test('access после logout больше не пускает: повторный logout → 401 unauthorized', () async {
      await api.post('/auth/logout', bearer: accessToken);
      final again = await api.post('/auth/logout', bearer: accessToken);
      expect(again.status, 401);
      expect(again.errorCode, 'unauthorized');
      expect(
        logs.text,
        contains(
          'unauthorized POST /api/v1/auth/logout reason=session_revoked',
        ),
      );
    });

    test('без токена → 401 unauthorized, ничего не отозвано', () async {
      final response = await api.post('/auth/logout');
      expect(response.status, 401);
      expect(response.errorCode, 'unauthorized');
      expect(await revoked(sessionId), isFalse);
    });

    test('выход отзывает только текущую сессию', () async {
      final other = await api.login(deviceName: 'Tablet');
      final otherRefresh = other.json['refreshToken']! as String;
      final otherSession = api.auth.accessTokens
          .verify(other.json['accessToken']! as String)
          .claims!
          .sessionId;

      await api.post('/auth/logout', bearer: accessToken);

      expect(await revoked(sessionId), isTrue);
      expect(await revoked(otherSession), isFalse);
      final response = await api.post(
        '/auth/refresh',
        body: {'refreshToken': otherRefresh},
      );
      expect(response.status, 200);
    });
  });
}
