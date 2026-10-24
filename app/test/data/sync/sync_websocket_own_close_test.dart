import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/sync/sync_websocket.dart';

import '../api/fake_api_adapter.dart';
import 'sync_websocket_fixture.dart';

const _s = Duration(seconds: 1);

void main() {
  late LogCapture logs;

  setUp(() => logs = LogCapture());
  tearDown(() => logs.dispose());

  test(
    'приложение само закрыло сокет в фоне - это не обрыв: нет warn '
    '«connection lost», нет таймера переподключения, возврат - attempt=1',
    () async {
      final rig = SocketRig();
      await rig.start();
      await rig.time.elapse(_s * 18);
      final first = rig.connector.last;

      rig.socket.paused();
      await rig.settle();

      expect(first.clientCloseCode, WsCloseCode.normal);
      expect(first.clientCloseReason, WsCloseReason.background);
      expect(first.serverDone, isTrue);
      expect(rig.socket.phase, WsPhase.off);
      expect(rig.socket.reconnectScheduled, isFalse);
      expect(rig.time.active, isEmpty);
      expect(logs.linesOf('ws', Level.WARNING), isEmpty);
      expect(
        logs.linesOf('ws', Level.INFO).last,
        endsWith(
          'ws closed: app in background after 18000ms → code=1000 '
          'reason=app_in_background',
        ),
      );

      rig.socket.resumed();
      await rig.settle();
      expect(rig.connector.calls, 2);
      expect(rig.syncs, 0);
      expect(
        logs.linesOf('ws', Level.INFO),
        contains(endsWith('attempt=1 (app back from background)')),
      );
      rig.socket.dispose();
    },
  );

  test('сессия закончилась и dispose - тоже без warn и без таймеров', () async {
    final rig = SocketRig();
    await rig.start();
    rig.socket.sessionChanged(active: false, change: 'active→ended');
    await rig.settle();
    expect(rig.connector.last.clientCloseReason, WsCloseReason.signedOut);
    expect(rig.time.active, isEmpty);

    rig.socket.sessionChanged(active: true, change: 'ended→active');
    await rig.settle();
    expect(rig.connector.calls, 2);
    rig.socket.dispose();
    await rig.settle();
    expect(rig.connector.last.clientCloseReason, WsCloseReason.stopped);
    expect(rig.time.active, isEmpty);
    expect(logs.linesOf('ws', Level.WARNING), isEmpty);
  });

  test('без pong сокет закрыт кодом 4000 - один warn и одна пауза, без '
      'второго «connection lost» от собственного закрытия', () async {
    final rig = SocketRig();
    await rig.start();
    await rig.time.elapse(_s * 60);

    expect(rig.connector.last.clientCloseCode, WsCloseCode.noPong);
    final warnings = [
      for (final line in logs.linesOf('ws', Level.WARNING))
        line.split('\n').first,
    ];
    expect(warnings, hasLength(1));
    expect(warnings.single, contains('ws connection considered dead'));
    expect(rig.time.active.where((t) => t.delay == _s * 2), hasLength(1));
    rig.socket.dispose();
  });
}
