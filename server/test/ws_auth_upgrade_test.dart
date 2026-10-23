import 'dart:io';

import 'package:server/auth/tokens.dart';
import 'package:test/test.dart';

import 'support/auth_support.dart';
import 'support/shared_budget_support.dart';
import 'support/test_support.dart';
import 'support/ws_support.dart';

void main() {
  late LogCapture logs;
  late WsHarness ws;

  setUp(() async {
    logs = LogCapture();
    ws = await WsHarness.start();
  });

  Future<String> sessionOf(TestUser user) async {
    final rows = await ws.api.db.execute(
      r'SELECT id FROM sessions WHERE user_id = $1::uuid',
      parameters: [user.id],
    );
    return rows.single.first! as String;
  }

  group('GET /api/v1/ws: авторизация до апгрейда', () {
    test(
      'без заголовка Authorization → 401 unauthorized, апгрейда нет',
      () async {
        final attempt = await ws.upgrade();

        expect(attempt.status, 401, reason: '$attempt');
        expect(attempt.errorCode, 'unauthorized');
        expect(attempt.wwwAuthenticate, 'Bearer');
        expect(ws.hub.connectionCount, 0);
        expect(
          logs.text,
          contains('unauthorized GET /api/v1/ws reason=missing_token'),
        );
        expect(logs.text, isNot(contains('ws connected')));
        expect(logs.text, isNot(contains('101 upgraded')));
      },
    );

    test('клиент WebSocket без токена получает отказ подключения', () async {
      await expectLater(
        ws.connectWith(null),
        throwsA(isA<WebSocketException>()),
      );
      expect(ws.hub.connectionCount, 0);
    });

    test('не Bearer → 401 malformed_header', () async {
      final attempt = await ws.upgrade(authorization: 'Basic YWJjOmRlZg==');

      expect(attempt.status, 401, reason: '$attempt');
      expect(attempt.errorCode, 'unauthorized');
      expect(logs.text, contains('reason=malformed_header'));
      expect(ws.hub.connectionCount, 0);
    });

    test('просроченный access-токен → 401 expired', () async {
      final user = await registerTestUser(ws.api, 'ws.expired');
      final stale = AccessTokens(
        testJwtSecret,
        now: () => DateTime.now().subtract(const Duration(minutes: 20)),
      ).issue(userId: user.id, sessionId: await sessionOf(user));

      final attempt = await ws.upgrade(authorization: 'Bearer $stale');

      expect(attempt.status, 401, reason: '$attempt');
      expect(attempt.errorCode, 'unauthorized');
      expect(logs.text, contains('unauthorized GET /api/v1/ws reason=expired'));
      expect(ws.hub.connectionCount, 0);
      expect(logs.text, isNot(contains(stale)));
    });

    test('отозванная сессия (logout) → 401 session_revoked', () async {
      final user = await registerTestUser(ws.api, 'ws.revoked');
      final logout = await ws.api.post(
        '/auth/logout',
        bearer: user.accessToken,
      );
      expect(logout.status, 204);

      final attempt = await ws.upgrade(
        authorization: 'Bearer ${user.accessToken}',
      );

      expect(attempt.status, 401, reason: '$attempt');
      expect(logs.text, contains('reason=session_revoked'));
      expect(ws.hub.connectionCount, 0);
    });

    test('с токеном, но без рукопожатия WebSocket → 426 bad_request', () async {
      final user = await registerTestUser(ws.api, 'ws.plain');

      final attempt = await ws.upgrade(
        authorization: 'Bearer ${user.accessToken}',
        handshake: false,
      );

      expect(attempt.status, 426, reason: '$attempt');
      expect(attempt.errorCode, 'bad_request');
      expect(logs.text, contains('ws upgrade refused'));
      expect(ws.hub.connectionCount, 0);
    });
  });

  group('GET /api/v1/ws: подключение', () {
    test('действующий токен → 101, подключение в реестре по userId', () async {
      final anna = await registerTestUser(ws.api, 'ws.anna');
      final boris = await registerTestUser(ws.api, 'ws.boris');

      await ws.connect(anna);
      await ws.connect(anna);
      await ws.connect(boris);

      expect(ws.hub.connectionsOf(anna.id), 2);
      expect(ws.hub.connectionsOf(boris.id), 1);
      expect(ws.hub.connectionCount, 3);
      expect(logs.text, contains('GET /api/v1/ws 101 upgraded to websocket'));
      final connected = logs.lines
          .where((line) => line.contains('ws connected'))
          .toList();
      expect(connected, hasLength(3));
      expect(connected.first, contains('INFO'));
      expect(connected.first, contains('userId=${anna.id}'));
      expect(connected.first, contains('tokenExpiresIn='));
      expect(connected.first, matches(RegExp(r'conn=\S+ ')));
      expect(logs.text, isNot(contains(anna.accessToken)));
      expect(logs.text, isNot(contains(boris.accessToken)));
    });

    test(
      'клиент закрыл → отключение в логе с причиной и длительностью',
      () async {
        final anna = await registerTestUser(ws.api, 'ws.closer');
        final client = await ws.connect(anna);

        await client.close(1000, 'bye');
        await waitUntil(() => ws.hub.connectionsOf(anna.id) == 0);

        final line = logs.lines.singleWhere(
          (line) => line.contains('ws disconnected'),
        );
        expect(line, contains('INFO'));
        expect(line, contains('userId=${anna.id}'));
        expect(line, contains('reason=client_closed'));
        expect(line, contains('code=1000'));
        expect(line, contains('clientReason=bye'));
        expect(line, matches(RegExp(r'duration=\d+ms')));
        expect(ws.hub.connectionCount, 0);
      },
    );

    test('остановка сервера закрывает подключения кодом 4503', () async {
      final anna = await registerTestUser(ws.api, 'ws.shutdown');
      final client = await ws.connect(anna);

      await ws.hub.closeAll('test shutdown');
      await client.done.timeout(const Duration(seconds: 5));

      expect(client.closeCode, 4503);
      expect(client.closeReason, 'server_shutdown');
      expect(ws.hub.connectionCount, 0);
      expect(logs.text, contains('ws closing all connections=1'));
      expect(logs.text, contains('reason=server_shutdown'));
    });
  });
}
