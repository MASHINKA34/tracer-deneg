import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/logging/log_secrets.dart';
import 'package:milionchik/data/api/api_client.dart';
import 'package:milionchik/data/api/api_config.dart';
import 'package:milionchik/data/api/api_exception.dart';
import 'package:milionchik/data/api/auth_interceptor.dart';
import 'package:milionchik/data/api/token_store.dart';
import 'package:milionchik/data/sync/sync_engine.dart';
import 'package:milionchik/data/sync/sync_websocket.dart';

import '../api/fake_api_adapter.dart';
import 'sync_triggers_fixture.dart';
import 'sync_websocket_fixture.dart';

const _s = Duration(seconds: 1);

String _access(int n) =>
    'eyJhbGciOiJIUzI1NiJ9.ws-access-$n-QXlwaGFCcmF2bw.c2lnbmF0dXJl';

String _refresh(int n) => 'ws-refresh-$n-Kq7Zr9Lm3Pd8Tx2Wb6Nc4Hv1Jy5Fg0Sa';

final class _AuthServer {
  int rotation = 1;
  int refreshCalls = 0;
  final List<String?> refreshBodies = [];
  FakeReply? refreshReply;
  Completer<void>? refreshGate;
  final Set<String> expired = {};

  String get access => _access(rotation);

  String get refresh => _refresh(rotation);

  Future<FakeReply> handle(FakeCall call) async {
    if (call.path.endsWith('/auth/refresh')) {
      refreshCalls++;
      refreshBodies.add(call.json['refreshToken'] as String?);
      final gate = refreshGate;
      if (gate != null) await gate.future;
      final reply = refreshReply;
      if (reply != null) return reply;
      if (call.json['refreshToken'] != refresh) {
        return FakeReply.error(401, 'session_expired');
      }
      rotation++;
      return FakeReply.json(200, {
        'accessToken': access,
        'refreshToken': refresh,
      });
    }
    final bearer = call.header('Authorization');
    if (bearer != 'Bearer $access' ||
        expired.contains(bearer!.substring('Bearer '.length))) {
      return FakeReply.error(401, 'unauthorized');
    }
    return FakeReply.json(200, {'ok': true});
  }
}

final class _Rig {
  _Rig() {
    store = MemoryTokenStore(
      AuthTokens(accessToken: server.access, refreshToken: server.refresh),
    );
    var n = 0;
    api = ApiClient(
      config: ApiConfig.resolve(define: '', debugBuild: true),
      tokens: store,
      adapter: FakeApiAdapter(server.handle),
      newRequestId: () => 'ridws${(++n).toString().padLeft(11, '0')}',
    );
    ended = api.sessionExpired.listen(events.add);
    socket = SyncWebSocket(
      url: () => testWsUrl,
      readTokens: store.readTokens,
      refresh: (accessToken) => api.refreshRejectedToken(
        path: syncWebSocketPath,
        accessToken: accessToken,
      ),
      changed: () {
        syncs++;
        return Future.value(
          const SyncCycleSkipped(
            reason: SyncReason.websocket,
            elapsed: Duration.zero,
            why: 'fake engine',
          ),
        );
      },
      connect: connector.call,
      timer: time.start,
      random: FixedRandom(),
      clock: () => time.now,
    );
  }

  final _AuthServer server = _AuthServer();
  final VirtualTime time = VirtualTime();
  final FakeConnector connector = FakeConnector();
  final List<SessionExpired> events = [];
  late final MemoryTokenStore store;
  late final ApiClient api;
  late final SyncWebSocket socket;
  late final StreamSubscription<SessionExpired> ended;
  int syncs = 0;

  Future<void> settle() => time.elapse(Duration.zero);

  Future<void> start() async {
    socket.start(signedIn: true, foreground: true);
    await settle();
  }

  Future<void> dispose() async {
    socket.dispose();
    await ended.cancel();
    api.close();
  }
}

void main() {
  late LogCapture logs;

  setUp(() => logs = LogCapture());
  tearDown(() => logs.dispose());

  test('сервер закрыл с 4401 (токен истёк): один refresh, новое подключение '
      'сразу с новым токеном, синхронизация вдогонку', () async {
    final rig = _Rig();
    rig.connector.autoPong = true;
    await rig.start();
    expect(rig.connector.bearers, [_access(1)]);

    await rig.time.elapse(const Duration(minutes: 15));
    rig.connector.last.serverCloses(4401, 'token_expired');
    await rig.settle();
    await rig.settle();

    expect(rig.server.refreshCalls, 1);
    expect(rig.server.refreshBodies, [_refresh(1)]);
    expect((await rig.store.readTokens())!.accessToken, _access(2));
    expect(rig.connector.bearers, [_access(1), _access(2)]);
    expect(rig.socket.phase, WsPhase.open);
    expect(rig.socket.reconnectScheduled, isFalse);
    expect(rig.syncs, 1);
    expect(rig.events, isEmpty);

    final info = logs.linesOf('ws', Level.INFO);
    expect(
      info,
      contains(
        endsWith(
          'ws access token rejected (closed by server code=4401 '
          'reason=token_expired after 900000ms) → refreshing session, then '
          'reconnecting',
        ),
      ),
    );
    expect(info, contains(contains('ws session refreshed in ')));
    expect(
      logs.linesOf('api', Level.INFO),
      contains(contains('access token rejected on /ws → refreshing session')),
    );
    await rig.dispose();
  });

  test('рукопожатие 401 (токен истёк за время в фоне): refresh и сразу '
      'подключение с новым токеном, без синхронизации вдогонку', () async {
    final rig = _Rig();
    rig.connector.failNext(handshakeStatus(401));
    await rig.start();
    await rig.settle();

    expect(rig.server.refreshCalls, 1);
    expect(rig.connector.bearers, [_access(1), _access(2)]);
    expect(rig.socket.phase, WsPhase.open);
    expect(rig.syncs, 0);
    expect(
      logs.linesOf('ws', Level.INFO),
      contains(
        endsWith(
          'ws access token rejected (handshake answered 401 attempt=1 in 0ms) '
          '→ refreshing session, then reconnecting',
        ),
      ),
    );
    await rig.dispose();
  });

  test('HTTP-запрос и сокет одновременно упёрлись в истёкший токен - '
      'refresh ровно один (single-flight), оба продолжают с новым', () async {
    final rig = _Rig();
    await rig.start();
    rig.server.refreshGate = Completer<void>();
    rig.server.expired.add(_access(1));

    final me = rig.api.get('/me');
    await rig.settle();
    expect(rig.server.refreshCalls, 1);
    rig.connector.last.serverCloses(4401, 'token_expired');
    await rig.settle();
    expect(rig.server.refreshCalls, 1);
    expect(rig.socket.phase, WsPhase.refreshing);

    rig.server.refreshGate!.complete();
    final response = await me;
    await rig.settle();
    await rig.settle();

    expect(response.statusCode, 200);
    expect(rig.server.refreshCalls, 1);
    expect(rig.connector.bearers, [_access(1), _access(2)]);
    expect(rig.socket.phase, WsPhase.open);
    await rig.dispose();
  });

  test('refresh отклонён (сессия отозвана): сессия закончена, без '
      'переподключения и без таймеров', () async {
    final rig = _Rig();
    await rig.start();
    rig.server.refreshReply = FakeReply.error(401, 'session_expired');
    rig.connector.last.serverCloses(4401, 'token_expired');
    await rig.settle();
    await rig.settle();

    expect(rig.server.refreshCalls, 1);
    expect(rig.events.single.reason, SessionEndReason.refreshRejected);
    expect(rig.socket.phase, WsPhase.off);
    expect(rig.socket.reconnectScheduled, isFalse);
    expect(rig.connector.calls, 1);
    await rig.time.elapse(const Duration(minutes: 10));
    expect(rig.connector.calls, 1);
    expect(
      logs.linesOf('ws', Level.INFO).last,
      contains(
        'ws session ended while refreshing (refreshRejected) in 0ms → not '
        'reconnecting until the next sign-in',
      ),
    );
    await rig.dispose();
  });

  test('refresh не дошёл (5xx) - пауза 2 с и повтор; токен отклонён сразу '
      'после refresh - пауза вместо частых refresh', () async {
    final rig = _Rig();
    await rig.start();
    rig.server.refreshReply = FakeReply.error(503, 'internal');
    rig.connector.last.serverCloses(4401, 'token_expired');
    await rig.settle();
    await rig.settle();
    expect(rig.socket.phase, WsPhase.waiting);
    expect(rig.socket.reconnectDelay, _s * 2);
    expect(
      logs.linesOf('ws', Level.WARNING).single.split('\n').first,
      allOf(
        contains('ws session refresh failed in 0ms: ApiServerFailure: 503'),
        endsWith('→ reconnect attempt=2 in 2000ms'),
      ),
    );

    rig.server.refreshReply = null;
    rig.connector
      ..failNext(handshakeStatus(401))
      ..failNext(handshakeStatus(401))
      ..failNext(handshakeStatus(401));
    await rig.time.elapse(_s * 2);
    await rig.settle();
    expect(rig.server.refreshCalls, 2);
    expect(rig.connector.calls, 3);
    expect(rig.socket.phase, WsPhase.waiting);
    expect(rig.socket.reconnectDelay, _s * 4);
    expect(
      logs.linesOf('ws', Level.WARNING).last.split('\n').first,
      allOf(
        contains(
          'ws access token rejected again right after a session refresh '
          '(handshake answered 401 attempt=2 in 0ms)',
        ),
        endsWith('→ reconnect attempt=3 in 4000ms'),
      ),
    );

    await rig.time.elapse(_s * 4);
    await rig.settle();
    expect(rig.server.refreshCalls, 3);
    expect(rig.connector.calls, 5);
    expect(rig.socket.phase, WsPhase.open);
    await rig.dispose();
  });

  test('токены не попадают в лог: ни access из заголовка, ни refresh - '
      'на всех путях (обрыв, 401, refresh, переподключение)', () async {
    final rig = _Rig();
    rig.connector
      ..autoPong = true
      ..failNext(handshakeStatus(401));
    await rig.start();
    await rig.settle();
    await rig.time.elapse(_s * 40);
    rig.connector.last.serverCloses(4401, 'token_expired');
    await rig.settle();
    await rig.settle();
    rig.connector.failNext(refusedConnection());
    rig.connector.last.drop();
    await rig.settle();
    await rig.time.elapse(_s * 10);
    expect(rig.server.refreshCalls, 2);
    expect(rig.connector.calls, 5);

    final text = logs.text;
    for (var n = 1; n <= 3; n++) {
      expect(text, isNot(contains(_access(n))));
      expect(text, isNot(contains(_refresh(n))));
    }
    expect(text, isNot(contains('Bearer ey')));
    expect(maskLeakedSecrets(text).summary, 'none');
    expect(logs.linesOf('ws'), isNotEmpty);
    await rig.dispose();
  });
}
