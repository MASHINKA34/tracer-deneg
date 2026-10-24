import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:math' as math;

import 'package:milionchik/data/api/token_store.dart';
import 'package:milionchik/data/sync/sync_engine.dart';
import 'package:milionchik/data/sync/sync_websocket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'sync_triggers_fixture.dart';

final Uri testWsUrl = Uri.parse('ws://10.0.2.2:8080/api/v1/ws');

final class FakeWebSocketChannel implements WebSocketChannel {
  FakeWebSocketChannel(this.headers);

  final Map<String, String> headers;
  final StreamController<Object?> _incoming = StreamController<Object?>(
    sync: true,
  );
  final List<Object?> sent = [];
  late final FakeWebSocketSink _sink = FakeWebSocketSink(this);

  @override
  int? closeCode;

  @override
  String? closeReason;

  int? clientCloseCode;
  String? clientCloseReason;
  bool autoPong = false;

  bool get closedByClient => _sink.closed;

  bool get serverDone => _incoming.isClosed;

  String? get bearer {
    final value = headers['Authorization'];
    if (value == null || !value.startsWith('Bearer ')) return null;
    return value.substring('Bearer '.length);
  }

  List<String> get sentTypes => [
    for (final message in sent)
      (jsonDecode(message! as String) as Map<String, Object?>)['type']!
          as String,
  ];

  int get pings => sentTypes.where((t) => t == 'ping').length;

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  WebSocketSink get sink => _sink;

  @override
  Future<void> get ready => Future<void>.value();

  @override
  String? get protocol => null;

  void serverSends(Map<String, Object?> json) =>
      _incoming.add(jsonEncode(json));

  void serverSendsRaw(Object? message) => _incoming.add(message);

  void changed(List<String> budgetIds, int cursor) => serverSends({
    'type': 'changed',
    'budgetIds': budgetIds,
    'cursor': cursor,
  });

  void pong() => serverSends({'type': 'pong'});

  void serverCloses(int code, String reason) {
    closeCode = code;
    closeReason = reason;
    unawaited(_incoming.close());
  }

  void drop() => unawaited(_incoming.close());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class FakeWebSocketSink implements WebSocketSink {
  FakeWebSocketSink(this._channel);

  final FakeWebSocketChannel _channel;
  final Completer<void> _done = Completer<void>();
  bool closed = false;

  @override
  void add(Object? data) {
    if (closed) throw StateError('Cannot add event after closing');
    _channel.sent.add(data);
    if (_channel.autoPong && data == '{"type":"ping"}') {
      scheduleMicrotask(() {
        if (!_channel._incoming.isClosed) _channel.pong();
      });
    }
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<Object?> stream) => stream.forEach(add);

  @override
  Future<void> close([int? closeCode, String? closeReason]) {
    if (!closed) {
      closed = true;
      _channel.clientCloseCode = closeCode;
      _channel.clientCloseReason = closeReason;
      if (!_done.isCompleted) _done.complete();
      if (!_channel._incoming.isClosed) unawaited(_channel._incoming.close());
    }
    return _done.future;
  }

  @override
  Future<void> get done => _done.future;
}

typedef ConnectPlan = FutureOr<FakeWebSocketChannel> Function(
  Uri url,
  Map<String, String> headers,
);

final class FakeConnector {
  final List<FakeWebSocketChannel> channels = [];
  final List<Uri> urls = [];
  final List<String?> bearers = [];
  final List<ConnectPlan> _plans = [];
  int calls = 0;
  bool autoPong = false;

  FakeWebSocketChannel get last => channels.last;

  void failNext(Object error, {int times = 1}) {
    for (var i = 0; i < times; i++) {
      _plans.add((_, _) => throw error);
    }
  }

  void plan(ConnectPlan plan) => _plans.add(plan);

  Future<WebSocketChannel> call(Uri url, Map<String, String> headers) async {
    calls++;
    urls.add(url);
    final value = headers['Authorization'];
    bearers.add(
      value != null && value.startsWith('Bearer ')
          ? value.substring('Bearer '.length)
          : null,
    );
    final channel = _plans.isEmpty
        ? FakeWebSocketChannel(Map.of(headers))
        : await _plans.removeAt(0)(url, Map.of(headers));
    channel.autoPong = autoPong;
    channels.add(channel);
    return channel;
  }
}

WebSocketChannelException refusedConnection() => WebSocketChannelException.from(
  const io.SocketException(
    'Connection refused',
    osError: io.OSError('Connection refused', 111),
  ),
);

WebSocketChannelException handshakeStatus(int status) =>
    WebSocketChannelException.from(
      io.WebSocketException(
        "Connection to 'http://10.0.2.2:8080/api/v1/ws' was not upgraded to "
        'websocket',
        status,
      ),
    );

final class FixedRandom implements math.Random {
  FixedRandom([this.value = 0.5]);

  double value;

  @override
  double nextDouble() => value;

  @override
  int nextInt(int max) => 0;

  @override
  bool nextBool() => false;
}

final class SocketRig {
  SocketRig({
    AuthTokens? tokens,
    RejectedTokenRefresh? refresh,
    this.changedResult,
  }) : tokens =
           tokens ??
           const AuthTokens(
             accessToken: 'ACCESS-socket-alpha-bravo-charlie',
             refreshToken: 'REFRESH-socket-delta-echo-foxtrot',
           ) {
    socket = SyncWebSocket(
      url: () => testWsUrl,
      readTokens: () async => this.tokens,
      refresh: refresh ?? _countRefresh,
      changed: _changed,
      connect: connector.call,
      timer: time.start,
      random: random,
      clock: () => time.now,
    );
  }

  final VirtualTime time = VirtualTime();
  final FakeConnector connector = FakeConnector();
  final FixedRandom random = FixedRandom();
  final List<String> refreshed = [];
  int syncs = 0;
  AuthTokens? tokens;
  Future<SyncCycleResult> Function()? changedResult;
  late final SyncWebSocket socket;

  Future<void> _countRefresh(String accessToken) async {
    refreshed.add(accessToken);
  }

  Future<SyncCycleResult> _changed() {
    syncs++;
    final custom = changedResult;
    if (custom != null) return custom();
    return Future.value(
      const SyncCycleSkipped(
        reason: SyncReason.websocket,
        elapsed: Duration.zero,
        why: 'fake engine',
      ),
    );
  }

  Future<void> settle() => time.elapse(Duration.zero);

  Future<void> start({bool signedIn = true, bool foreground = true}) async {
    socket.start(signedIn: signedIn, foreground: foreground);
    await settle();
  }

  List<Duration> get reconnectPauses => [
    for (final d in time.fired)
      if (d != wsPingInterval) d,
  ];
}
