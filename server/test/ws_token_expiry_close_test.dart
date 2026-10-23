import 'dart:async';

import 'package:server/auth/auth_middleware.dart';
import 'package:server/auth/tokens.dart';
import 'package:server/ws/ws_hub.dart';
import 'package:server/ws/ws_protocol.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/auth_support.dart';
import 'support/shared_budget_support.dart';
import 'support/test_support.dart';
import 'support/ws_support.dart';

const _ttl = Duration(seconds: 3);

void main() {
  late LogCapture logs;
  late WsHarness ws;

  setUp(() async {
    logs = LogCapture();
    ws = await WsHarness.start(
      accessTokens: AccessTokens(testJwtSecret, ttl: _ttl),
    );
  });

  test('код закрытия «токен истёк» — 4401 token_expired', () {
    expect(WsClose.tokenExpired.code, 4401);
    expect(WsClose.tokenExpired.reason, 'token_expired');
  });

  test('истёк access-токен подключения — сервер закрывает 4401, после '
      'refresh клиент подключается снова', () async {
    final anna = await registerTestUser(ws.api, 'ws.expiring');
    final client = await ws.connect(anna);
    final sw = Stopwatch()..start();
    var pongs = 0;
    final pinger = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!client.isClosed) client.ping();
      pongs = client.ofType(WsMessageType.pong).length;
    });
    addTearDown(pinger.cancel);

    await client.done.timeout(_ttl + const Duration(seconds: 2));
    pinger.cancel();

    expect(sw.elapsed, lessThanOrEqualTo(_ttl + const Duration(seconds: 1)));
    expect(pongs, greaterThan(0));
    expect(client.closeCode, 4401);
    expect(client.closeReason, 'token_expired');
    expect(ws.hub.connectionsOf(anna.id), 0);
    expect(logs.text, contains('ws access token expired, closing'));
    final line = logs.lines.singleWhere((l) => l.contains('ws disconnected'));
    expect(line, contains('INFO'));
    expect(line, contains('userId=${anna.id}'));
    expect(line, contains('reason=token_expired code=4401'));
    expect(line, matches(RegExp(r'duration=\d+ms')));

    final refreshed = await ws.api.post(
      '/auth/refresh',
      body: {'refreshToken': anna.refreshToken},
    );
    expect(refreshed.status, 200);
    final token = refreshed.json['accessToken']! as String;
    await ws.connectWith('Bearer $token');
    await waitUntil(() => ws.hub.connectionsOf(anna.id) == 1);

    expect(logs.text, isNot(contains(anna.accessToken)));
    expect(logs.text, isNot(contains(token)));
    expect(logs.text, isNot(contains(anna.refreshToken)));
  });

  test('токен уже истёк к моменту подключения — сразу 4401', () async {
    final closed = Completer<(int, String)>();
    final incoming = StreamController<Object?>();
    addTearDown(incoming.close);
    final userId = newId();

    ws.hub.accept(
      AuthContext(
        userId: userId,
        sessionId: newId(),
        expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
      ),
      WsPeer(
        messages: incoming.stream,
        send: (_) {},
        close: (code, reason) async {
          closed.complete((code, reason));
          await incoming.close();
        },
        remoteCloseCode: () => null,
        remoteCloseReason: () => null,
      ),
    );

    expect(await closed.future, (4401, 'token_expired'));
    await waitUntil(() => ws.hub.connectionsOf(userId) == 0);
    expect(logs.text, contains('ws access token already expired on connect'));
  });
}
