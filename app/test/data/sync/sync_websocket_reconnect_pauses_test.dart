import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/sync/sync_websocket.dart';

import '../api/fake_api_adapter.dart';
import 'sync_websocket_fixture.dart';

const _s = Duration(seconds: 1);

List<int> _ms(List<Duration> pauses) => [
  for (final p in pauses) p.inMilliseconds,
];

List<String> _heads(List<String> lines) => [
  for (final line in lines) line.split('\n').first,
];

void main() {
  late LogCapture logs;

  setUp(() => logs = LogCapture());
  tearDown(() => logs.dispose());

  test(
    'обрыв и сервер недоступен: паузы 2 → 4 → … → 300 с (как у push), '
    'потолок 300 с; после подключения - одна синхронизация вдогонку',
    () async {
      final rig = SocketRig();
      await rig.start();
      await rig.time.elapse(_s * 40);
      rig.connector.last.pong();
      rig.connector.failNext(refusedConnection(), times: 9);

      rig.connector.last.drop();
      await rig.settle();
      expect(rig.socket.phase, WsPhase.waiting);
      expect(rig.socket.reconnectDelay, _s * 2);

      await rig.time.elapse(_s * 1109);
      expect(rig.connector.calls, 10);
      expect(rig.socket.phase, WsPhase.waiting);
      await rig.time.elapse(_s);

      expect(rig.connector.calls, 11);
      expect(rig.socket.phase, WsPhase.open);
      expect(_ms(rig.reconnectPauses), [
        2000,
        4000,
        8000,
        16000,
        32000,
        64000,
        128000,
        256000,
        300000,
        300000,
      ]);
      expect(rig.syncs, 1);

      final warnings = _heads(logs.linesOf('ws', Level.WARNING));
      expect(
        warnings.first,
        allOf(
          contains('ws connection lost code=- reason=- after 40000ms'),
          endsWith('→ reconnect attempt=2 in 2000ms'),
        ),
      );
      expect(
        warnings[1],
        allOf(
          contains(
            'ws connect failed url=ws://10.0.2.2:8080/api/v1/ws attempt=2 in ',
          ),
          contains('SocketException: Connection refused'),
          endsWith('→ reconnect attempt=3 in 4000ms'),
        ),
      );
      expect(warnings.last, endsWith('→ reconnect attempt=11 in 300000ms'));
      final info = logs.linesOf('ws', Level.INFO);
      expect(
        info,
        contains(
          endsWith(
            'ws reconnect pause of 2000ms elapsed → connecting attempt=2',
          ),
        ),
      );
      expect(
        info.last,
        endsWith(
          'ws reconnected after a drop → sync reason=websocket to catch up on '
          'changes missed while disconnected',
        ),
      );
      expect(
        info,
        contains(
          endsWith(
            'ws connected in 0ms url=ws://10.0.2.2:8080/api/v1/ws attempt=11',
          ),
        ),
      );
      rig.socket.dispose();
    },
  );

  test('недолгое соединение (< 30 с) паузу не сбрасывает, проживший 30 с - '
      'сбрасывает до 2 с', () async {
    final rig = SocketRig();
    await rig.start();

    await rig.time.elapse(_s * 5);
    rig.connector.last.drop();
    await rig.settle();
    expect(rig.socket.reconnectDelay, _s * 2);
    await rig.time.elapse(_s * 2);
    expect(rig.socket.phase, WsPhase.open);

    await rig.time.elapse(_s * 5);
    rig.connector.last.drop();
    await rig.settle();
    expect(rig.socket.reconnectDelay, _s * 4);
    await rig.time.elapse(_s * 4);
    expect(rig.socket.phase, WsPhase.open);

    await rig.time.elapse(_s * 31);
    rig.connector.last.drop();
    await rig.settle();
    expect(rig.socket.reconnectDelay, _s * 2);
    expect(_ms(rig.reconnectPauses), [2000, 4000]);
    rig.socket.dispose();
  });

  test('сервер закрыл с 4503 (остановка) - info, с 4408 (не было ping) - warn; '
      'оба с паузой и переподключением', () async {
    final rig = SocketRig();
    await rig.start();
    await rig.time.elapse(_s * 40);
    rig.connector.last.pong();

    rig.connector.last.serverCloses(4503, 'server_shutdown');
    await rig.settle();
    expect(
      logs.linesOf('ws', Level.INFO).last,
      allOf(
        contains(
          'ws closed by server code=4503 reason=server_shutdown after 40000ms: '
          'server shutting down',
        ),
        endsWith('→ reconnect attempt=2 in 2000ms'),
      ),
    );
    await rig.time.elapse(_s * 2);
    expect(rig.connector.calls, 2);

    rig.connector.last.serverCloses(4408, 'idle_timeout');
    await rig.settle();
    expect(
      _heads(logs.linesOf('ws', Level.WARNING)).single,
      allOf(
        contains(
          'ws closed by server code=4408 reason=idle_timeout after 0ms: our '
          'pings did not reach the server',
        ),
        endsWith('→ reconnect attempt=3 in 4000ms'),
      ),
    );
    await rig.time.elapse(_s * 4);
    expect(rig.connector.calls, 3);
    expect(rig.socket.phase, WsPhase.open);
    rig.socket.dispose();
  });

  test('сеть появилась во время паузы - подключение сразу, не дожидаясь '
      'таймера', () async {
    final rig = SocketRig();
    await rig.start();
    rig.socket.networkChanged(const [ConnectivityResult.wifi]);
    rig.connector.failNext(refusedConnection(), times: 3);
    rig.connector.last.drop();
    await rig.settle();
    await rig.time.elapse(_s * 14);
    expect(rig.connector.calls, 4);
    expect(rig.socket.reconnectDelay, _s * 16);

    rig.socket.networkChanged(const [ConnectivityResult.none]);
    await rig.settle();
    expect(rig.connector.calls, 4);
    rig.socket.networkChanged(const [ConnectivityResult.mobile]);
    await rig.settle();

    expect(rig.connector.calls, 5);
    expect(rig.socket.phase, WsPhase.open);
    expect(rig.socket.reconnectScheduled, isFalse);
    expect(
      logs.linesOf('ws', Level.INFO),
      contains(
        allOf(
          contains(
            'ws network appeared types=mobile → reconnecting now '
            'instead of waiting ',
          ),
          endsWith('ms more, attempt=5'),
        ),
      ),
    );
    await rig.time.elapse(_s * 16);
    expect(rig.connector.calls, 5);
    rig.socket.dispose();
  });

  test('ушло в фон во время паузы - таймер отменён, в фоне не подключается; '
      'возврат - сразу подключение, счётчик попыток с нуля', () async {
    final rig = SocketRig();
    await rig.start();
    rig.connector.failNext(refusedConnection(), times: 2);
    rig.connector.last.drop();
    await rig.settle();
    await rig.time.elapse(_s * 6);
    expect(rig.connector.calls, 3);
    expect(rig.socket.reconnectScheduled, isTrue);

    rig.socket.paused();
    await rig.settle();
    expect(rig.socket.reconnectScheduled, isFalse);
    expect(rig.socket.phase, WsPhase.off);
    expect(
      logs.linesOf('ws', Level.INFO).last,
      endsWith(
        'ws off: app in background while waiting → reconnect pause '
        'cancelled',
      ),
    );
    await rig.time.elapse(const Duration(minutes: 10));
    expect(rig.connector.calls, 3);

    rig.socket.resumed();
    await rig.settle();
    expect(rig.connector.calls, 4);
    expect(rig.socket.phase, WsPhase.open);
    expect(rig.socket.failures, 0);
    expect(
      logs.linesOf('ws', Level.INFO),
      contains(
        endsWith(
          'ws connecting url=ws://10.0.2.2:8080/api/v1/ws attempt=1 (app back '
          'from background)',
        ),
      ),
    );
    rig.socket.dispose();
  });
}
