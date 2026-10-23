import 'package:server/ws/ws_hub.dart';
import 'package:server/ws/ws_protocol.dart';
import 'package:test/test.dart';

import 'support/shared_budget_support.dart';
import 'support/test_support.dart';
import 'support/ws_support.dart';

const _idle = Duration(milliseconds: 700);

void main() {
  late LogCapture logs;
  late WsHarness ws;
  late TestUser anna;

  setUp(() async {
    logs = LogCapture();
    ws = await WsHarness.start(idleTimeout: _idle);
    anna = await registerTestUser(ws.api, 'ws.pinger');
  });

  test('по умолчанию: клиент шлёт ping раз в 30 с, тишина больше 90 с — '
      'закрытие 4408', () {
    expect(wsClientPingInterval, const Duration(seconds: 30));
    expect(wsIdleTimeout, const Duration(seconds: 90));
    expect(WsHub(db: ws.api.db).idleTimeout, wsIdleTimeout);
    expect(WsClose.idleTimeout.code, 4408);
    expect(WsClose.idleTimeout.reason, 'idle_timeout');
  });

  test('ping → pong', () async {
    final client = await ws.connect(anna);

    client.ping();

    expect(await client.next(WsMessageType.pong), {'type': 'pong'});
    await waitUntil(() => logs.text.contains('ws ping → pong'));
    final line = logs.lines.firstWhere((l) => l.contains('ws ping → pong'));
    expect(line, contains('DEBUG'));
    expect(line, contains('userId=${anna.id}'));
  });

  test('регулярные ping держат подключение дольше лимита тишины', () async {
    final client = await ws.connect(anna);
    final sw = Stopwatch()..start();

    var sent = 0;
    while (sw.elapsed < _idle * 3) {
      client.ping();
      sent++;
      await Future<void>.delayed(_idle ~/ 3);
    }

    expect(client.isClosed, isFalse);
    expect(ws.hub.connectionsOf(anna.id), 1);
    await waitUntil(() => client.ofType(WsMessageType.pong).length == sent);
    expect(logs.text, isNot(contains('reason=idle_timeout')));
  });

  test('тишина больше лимита — сервер закрывает с кодом 4408', () async {
    final client = await ws.connect(anna);
    final sw = Stopwatch()..start();

    await client.done.timeout(_idle * 4);

    expect(
      sw.elapsed,
      greaterThanOrEqualTo(_idle - const Duration(milliseconds: 50)),
    );
    expect(client.closeCode, 4408);
    expect(client.closeReason, 'idle_timeout');
    expect(ws.hub.connectionsOf(anna.id), 0);
    expect(logs.text, contains('ws no messages from client for'));
    final line = logs.lines.singleWhere((l) => l.contains('ws disconnected'));
    expect(line, contains('INFO'));
    expect(line, contains('reason=idle_timeout code=4408'));
    expect(line, matches(RegExp(r'duration=\d+ms')));
  });

  test('неизвестное сообщение — warn, подключение остаётся', () async {
    final client = await ws.connect(anna);

    client.sendJson({'type': 'hello', 'token': 'не-логировать-это'});
    client.socket.add('не json');
    client.ping();

    await client.next(WsMessageType.pong);
    final ignored = logs.lines
        .where((l) => l.contains('ws message ignored'))
        .toList();
    expect(ignored, hasLength(2));
    expect(ignored.first, contains('WARN'));
    expect(ignored.first, contains('type=hello'));
    expect(ignored.last, contains('type=none'));
    expect(logs.text, isNot(contains('не-логировать-это')));
    expect(client.isClosed, isFalse);
  });
}
