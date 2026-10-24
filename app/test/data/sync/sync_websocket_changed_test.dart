import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/api/api_config.dart';
import 'package:milionchik/data/sync/sync_engine.dart';
import 'package:milionchik/data/sync/sync_websocket.dart';

import '../api/fake_api_adapter.dart';
import 'sync_websocket_fixture.dart';

void main() {
  late LogCapture logs;

  setUp(() => logs = LogCapture());
  tearDown(() => logs.dispose());

  test('адрес /ws на том же хосте: http → ws, https → wss', () {
    expect(
      webSocketUrl(ApiConfig.resolve(define: '', debugBuild: true)).toString(),
      'ws://10.0.2.2:8080/api/v1/ws',
    );
    expect(
      webSocketUrl(
        ApiConfig.resolve(
          define: 'https://milionchik.example/api/v1/',
          debugBuild: false,
        ),
      ).toString(),
      'wss://milionchik.example/api/v1/ws',
    );
  });

  test(
    'подключение с заголовком Authorization; changed → синхронизация '
    'reason=websocket на каждое сообщение, в логе debug - тип и budgetIds',
    () async {
      final rig = SocketRig();
      await rig.start();

      expect(rig.connector.calls, 1);
      expect(rig.connector.urls.single, testWsUrl);
      expect(rig.connector.bearers.single, rig.tokens!.accessToken);
      expect(rig.socket.phase, WsPhase.open);
      expect(rig.syncs, 0);

      rig.connector.last.changed(['budget-b', 'budget-a'], 1234);
      await rig.settle();
      expect(rig.syncs, 1);

      rig.connector.last.changed(['budget-a'], 1240);
      await rig.settle();
      expect(rig.syncs, 2);

      final debug = logs.linesOf('ws', Level.FINE);
      expect(
        debug,
        contains(
          endsWith(
            'ws message type=changed budgetIds=[budget-b,budget-a] '
            'cursor=1234 → sync reason=websocket',
          ),
        ),
      );
      expect(
        logs.linesOf('ws', Level.INFO),
        contains(contains('ws connected in ')),
      );
      expect(
        logs.records
            .where((r) => r.message.startsWith('ws message type=changed'))
            .map((r) => r.level)
            .toSet(),
        {Level.FINE},
      );
      rig.socket.dispose();
    },
  );

  test('ping {"type":"ping"} раз в 30 с, pong снимает ожидание; без pong '
      'за 30 с соединение считается мёртвым и переподключается', () async {
    final rig = SocketRig();
    await rig.start();
    final first = rig.connector.last;

    await rig.time.elapse(const Duration(seconds: 29));
    expect(first.pings, 0);
    await rig.time.elapse(const Duration(seconds: 1));
    expect(first.sent, ['{"type":"ping"}']);
    first.pong();
    await rig.settle();

    await rig.time.elapse(const Duration(seconds: 30));
    expect(first.pings, 2);
    first.pong();
    await rig.settle();
    await rig.time.elapse(const Duration(seconds: 30));
    expect(first.pings, 3);
    expect(rig.connector.calls, 1);
    expect(
      logs.linesOf('ws', Level.FINE),
      contains(contains('ws message type=pong in ')),
    );

    await rig.time.elapse(const Duration(seconds: 30));
    expect(first.closedByClient, isTrue);
    expect(first.clientCloseCode, WsCloseCode.noPong);
    expect(rig.socket.phase, WsPhase.waiting);
    expect(
      logs.linesOf('ws', Level.WARNING),
      contains(
        contains(
          'ws connection considered dead: no pong within 30000ms of the last '
          'ping, after ',
        ),
      ),
    );
    expect(
      logs.linesOf('ws', Level.WARNING).last,
      endsWith('→ reconnect attempt=2 in 2000ms'),
    );

    await rig.time.elapse(const Duration(seconds: 2));
    expect(rig.connector.calls, 2);
    expect(rig.socket.phase, WsPhase.open);
    expect(rig.syncs, 1, reason: 'catch-up pull after the reconnect');
    rig.socket.dispose();
  });

  test('неизвестное и битое сообщение - warn без синхронизации, '
      'соединение остаётся', () async {
    final rig = SocketRig();
    await rig.start();
    rig.connector.last
      ..serverSends({'type': 'hello'})
      ..serverSendsRaw('not json')
      ..serverSendsRaw([1, 2, 3]);
    await rig.settle();

    expect(rig.syncs, 0);
    expect(rig.socket.phase, WsPhase.open);
    expect(logs.linesOf('ws', Level.WARNING), [
      contains('ws message ignored kind=text type=hello size=16'),
      contains('ws message ignored kind=text type=none size=8'),
      contains('ws message ignored kind=binary size=3'),
    ]);
    rig.socket.dispose();
  });

  test('синхронизация по changed упала - severe в лог, сокет живёт и '
      'реагирует на следующее changed', () async {
    var calls = 0;
    final rig = SocketRig();
    rig.changedResult = () {
      calls++;
      if (calls == 1) return Future.error(StateError('engine exploded'));
      return Future.value(
        const SyncCycleSkipped(
          reason: SyncReason.websocket,
          elapsed: Duration.zero,
          why: 'fake engine',
        ),
      );
    };
    await rig.start();
    rig.connector.last.changed(['budget-a'], 7);
    await rig.settle();
    rig.connector.last.changed(['budget-a'], 8);
    await rig.settle();

    expect(rig.syncs, 2);
    expect(rig.socket.phase, WsPhase.open);
    expect(
      logs.linesOf('ws', Level.SEVERE).single,
      contains(
        'ws changed cursor=7: sync cycle reason=websocket crashed: '
        'StateError: Bad state: engine exploded',
      ),
    );
    rig.socket.dispose();
  });

  test('без токенов не подключается и ждёт входа; адрес сервера не задан - '
      'severe, без повторов', () async {
    final rig = SocketRig()..tokens = null;
    await rig.start();
    expect(rig.connector.calls, 0);
    expect(rig.socket.phase, WsPhase.off);
    expect(rig.socket.reconnectScheduled, isFalse);
    expect(
      logs.linesOf('ws', Level.INFO),
      contains(endsWith('no session tokens → waits for sign-in')),
    );

    final broken = SyncWebSocket(
      url: () => throw const ApiConfigException(
        ApiConfigProblem.missing,
        'API_URL is not set',
      ),
      readTokens: () async => rig.tokens,
      refresh: (_) async {},
      changed: () => Completer<Never>().future,
      connect: rig.connector.call,
      timer: rig.time.start,
    );
    broken.start(signedIn: true, foreground: true);
    await rig.settle();
    expect(rig.connector.calls, 0);
    expect(broken.phase, WsPhase.off);
    expect(rig.time.active, isEmpty);
    expect(
      logs.linesOf('ws', Level.SEVERE).single,
      contains('ws not connecting: server address not configured'),
    );
    broken.dispose();
    rig.socket.dispose();
  });
}
