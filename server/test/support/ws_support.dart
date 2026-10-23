import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:server/auth/tokens.dart';
import 'package:server/http/router.dart';
import 'package:server/sync/sync_notifier.dart';
import 'package:server/ws/ws_hub.dart';
import 'package:server/ws/ws_protocol.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

import 'auth_support.dart';
import 'shared_budget_support.dart';
import 'test_support.dart';

class _Relay implements SyncNotifier {
  SyncNotifier? target;

  @override
  void budgetsChanged(BudgetsChanged event) => target?.budgetsChanged(event);
}

class WsHarness {
  WsHarness._(this.api, this.hub, this.server);

  static Future<WsHarness> start({
    AccessTokens? accessTokens,
    Duration idleTimeout = wsIdleTimeout,
  }) async {
    final relay = _Relay();
    final api = await AuthHarness.start(
      accessTokens: accessTokens,
      notifier: relay,
    );
    final hub = WsHub(db: api.db, idleTimeout: idleTimeout);
    relay.target = hub;
    final server = await shelf_io.serve(
      buildHandler(db: api.db, auth: api.auth, notifier: hub, ws: hub),
      '127.0.0.1',
      0,
    );
    addTearDown(() async {
      await hub.closeAll('test done');
      await server.close(force: true);
    });
    return WsHarness._(api, hub, server);
  }

  final AuthHarness api;
  final WsHub hub;
  final HttpServer server;

  String get wsUrl => 'ws://127.0.0.1:${server.port}$wsPath';

  Future<WsTestClient> connect(TestUser user) async {
    final before = hub.connectionsOf(user.id);
    final client = await connectWith('Bearer ${user.accessToken}');
    await waitUntil(() => hub.connectionsOf(user.id) > before);
    return client;
  }

  Future<WsTestClient> connectWith(String? authorization) async {
    final socket = await WebSocket.connect(
      wsUrl,
      headers: {'authorization': ?authorization},
    );
    final client = WsTestClient(socket);
    addTearDown(client.close);
    return client;
  }

  Future<UpgradeAttempt> upgrade({
    String? authorization,
    bool handshake = true,
  }) async {
    final http = HttpClient();
    try {
      final request = await http.get('127.0.0.1', server.port, wsPath);
      if (handshake) {
        request.headers
          ..set('connection', 'Upgrade')
          ..set('upgrade', 'websocket')
          ..set('sec-websocket-version', '13')
          ..set(
            'sec-websocket-key',
            base64.encode(List<int>.generate(16, (i) => i * 7)),
          );
      }
      if (authorization != null) {
        request.headers.set('authorization', authorization);
      }
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      return UpgradeAttempt(
        response.statusCode,
        body,
        response.headers.value('www-authenticate'),
      );
    } finally {
      http.close(force: true);
    }
  }
}

class UpgradeAttempt {
  UpgradeAttempt(this.status, this.body, this.wwwAuthenticate);

  final int status;
  final String body;
  final String? wwwAuthenticate;

  String? get errorCode {
    final json = jsonDecode(body) as Map<String, Object?>;
    return (json['error'] as Map<String, Object?>?)?['code'] as String?;
  }

  @override
  String toString() => 'UpgradeAttempt($status $body)';
}

class WsTestClient {
  WsTestClient(this.socket) {
    socket.listen(
      (data) {
        received.add(data);
        if (data is String) {
          messages.add(jsonDecode(data) as Map<String, Object?>);
        }
      },
      onDone: () {
        if (!_done.isCompleted) _done.complete();
      },
      onError: errors.add,
    );
  }

  final WebSocket socket;
  final List<Object?> received = [];
  final List<Map<String, Object?>> messages = [];
  final List<Object> errors = [];
  final Completer<void> _done = Completer<void>();

  Future<void> get done => _done.future;

  bool get isClosed => _done.isCompleted;

  int? get closeCode => socket.closeCode;

  String? get closeReason => socket.closeReason;

  List<Map<String, Object?>> ofType(String type) => [
    for (final message in messages)
      if (message['type'] == type) message,
  ];

  void sendJson(Object? json) => socket.add(jsonEncode(json));

  void ping() => sendJson({'type': WsMessageType.ping});

  Future<Map<String, Object?>> next(
    String type, {
    int after = 0,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    await waitUntil(() => ofType(type).length > after, timeout: timeout);
    return ofType(type)[after];
  }

  Future<void> close([int code = 1000, String reason = 'test']) async {
    if (isClosed) return;
    await socket.close(code, reason);
    await done.timeout(const Duration(seconds: 5), onTimeout: () {});
  }
}
