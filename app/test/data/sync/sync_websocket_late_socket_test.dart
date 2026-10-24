import 'dart:async';
import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/sync/sync_websocket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../api/fake_api_adapter.dart';
import 'sync_websocket_fixture.dart';

final class _FakeIoSocket implements io.WebSocket {
  final StreamController<dynamic> _incoming = StreamController<dynamic>();
  int? closedCode;
  String? closedReason;
  int closes = 0;

  @override
  StreamSubscription<dynamic> listen(
    void Function(dynamic event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _incoming.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  Future<void> close([int? code, String? reason]) async {
    closes++;
    closedCode = code;
    closedReason = reason;
    if (!_incoming.isClosed) await _incoming.close();
  }

  @override
  String? get protocol => null;

  @override
  int? get closeCode => closedCode;

  @override
  String? get closeReason => closedReason;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late LogCapture logs;

  setUp(() => logs = LogCapture());
  tearDown(() => logs.dispose());

  testWidgets('рукопожатие дольше 10 с: TimeoutException, а опоздавший '
      'сокет закрывается кодом 1000 not_needed и не остаётся сиротой', (
    tester,
  ) async {
    final pending = Completer<io.WebSocket>();
    final headers = <String, String>{};
    Object? failure;
    unawaited(
      connectWebSocket(
        testWsUrl,
        const {'Authorization': 'Bearer secret-late-token-alpha'},
        connect: (url, sent) {
          headers.addAll(sent);
          expect(url, 'ws://10.0.2.2:8080/api/v1/ws');
          return pending.future;
        },
      ).then<void>((_) {}, onError: (Object e) => failure = e),
    );

    await tester.pump(wsConnectTimeout - const Duration(milliseconds: 1));
    expect(failure, isNull);
    await tester.pump(const Duration(milliseconds: 1));
    expect(failure, isA<TimeoutException>());
    expect(headers['Authorization'], 'Bearer secret-late-token-alpha');

    final late = _FakeIoSocket();
    pending.complete(late);
    await tester.pump();

    expect(late.closes, 1);
    expect(late.closedCode, WsCloseCode.normal);
    expect(late.closedReason, WsCloseReason.notNeeded);
    expect(
      logs.linesOf('ws', Level.INFO).single,
      endsWith(
        'ws late socket arrived after the 10000ms connect timeout '
        'url=ws://10.0.2.2:8080/api/v1/ws → closing it code=1000 '
        'reason=not_needed',
      ),
    );
    expect(logs.text, isNot(contains('secret-late-token-alpha')));
  });

  testWidgets('подключение, упавшее уже после таймаута, - только debug, без '
      'необработанной ошибки', (tester) async {
    final pending = Completer<io.WebSocket>();
    Object? failure;
    unawaited(
      connectWebSocket(
        testWsUrl,
        const {},
        connect: (_, _) => pending.future,
      ).then<void>((_) {}, onError: (Object e) => failure = e),
    );
    await tester.pump(wsConnectTimeout);
    expect(failure, isA<TimeoutException>());

    pending.completeError(
      const io.SocketException('Connection refused'),
      StackTrace.current,
    );
    await tester.pump();

    expect(logs.linesOf('ws', Level.INFO), isEmpty);
    expect(
      logs.linesOf('ws', Level.FINE).single,
      contains(
        'ws connect that timed out after 10000ms failed later '
        'url=ws://10.0.2.2:8080/api/v1/ws: SocketException: Connection '
        'refused → no socket to close',
      ),
    );
  });

  testWidgets('сокет пришёл вовремя - канал отдан и не закрыт', (tester) async {
    final socket = _FakeIoSocket();
    WebSocketChannel? channel;
    unawaited(
      connectWebSocket(
        testWsUrl,
        const {},
        connect: (_, _) async => socket,
      ).then((c) => channel = c),
    );
    await tester.pump();
    expect(channel, isNotNull);
    await tester.pump(wsConnectTimeout * 2);
    expect(socket.closes, 0);
    expect(logs.linesOf('ws'), isEmpty);
  });

  test('подключение пришло после ухода в фон - закрыто кодом 1000 '
      'not_needed, сокет не становится текущим', () async {
    final rig = SocketRig();
    final pending = Completer<FakeWebSocketChannel>();
    rig.connector.plan((_, _) => pending.future);
    await rig.start();
    expect(rig.socket.phase, WsPhase.connecting);

    rig.socket.paused();
    await rig.settle();
    expect(rig.socket.phase, WsPhase.off);

    final late = FakeWebSocketChannel(const {});
    pending.complete(late);
    await rig.settle();

    expect(late.closedByClient, isTrue);
    expect(late.clientCloseCode, WsCloseCode.normal);
    expect(late.clientCloseReason, WsCloseReason.notNeeded);
    expect(rig.socket.phase, WsPhase.off);
    expect(rig.time.active, isEmpty);
    expect(late.serverDone, isTrue);
    expect(rig.syncs, 0);
    expect(
      logs.linesOf('ws', Level.FINE),
      contains(contains('after it stopped being needed → closing it')),
    );
    rig.socket.dispose();
  });

  test('подключение пришло после выхода из сессии - тоже закрыто '
      'not_needed', () async {
    final rig = SocketRig();
    final pending = Completer<FakeWebSocketChannel>();
    rig.connector.plan((_, _) => pending.future);
    await rig.start();

    rig.socket.sessionChanged(active: false, change: 'active→ended');
    final late = FakeWebSocketChannel(const {});
    pending.complete(late);
    await rig.settle();

    expect(late.clientCloseReason, WsCloseReason.notNeeded);
    expect(rig.socket.phase, WsPhase.off);
    expect(rig.time.active, isEmpty);
    rig.socket.dispose();
  });
}
