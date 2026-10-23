import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/data/api/api_client.dart';
import 'package:milionchik/data/api/api_config.dart';
import 'package:milionchik/data/api/api_exception.dart';
import 'package:milionchik/data/api/auth_interceptor.dart';
import 'package:milionchik/data/api/token_store.dart';
import 'package:shared/shared.dart';

import 'fake_api_adapter.dart';

const _staleAccess = 'stale-access-token-zzzzzzzzzzzzzzzz';

final class _FakeAuthServer {
  String access = 'live-access-token-1-yyyyyyyyyyyyyyyy';
  String refresh = 'live-refresh-token-1-xxxxxxxxxxxxxxx';
  int refreshCalls = 0;
  int rotations = 1;
  FakeReply? refreshReply;
  Object? refreshThrows;
  Completer<void>? refreshGate;
  String meCode = 'unauthorized';
  bool alwaysUnauthorized = false;

  Future<FakeReply> handle(FakeCall call) async {
    if (call.path.endsWith('/auth/refresh')) {
      refreshCalls++;
      final gate = refreshGate;
      if (gate != null) await gate.future;
      final thrown = refreshThrows;
      if (thrown != null) throw thrown;
      final reply = refreshReply;
      if (reply != null) return reply;
      if (call.json['refreshToken'] != refresh) {
        return FakeReply.error(401, 'session_expired');
      }
      rotations++;
      access = 'live-access-token-$rotations-yyyyyyyyyyyyyyyy';
      refresh = 'live-refresh-token-$rotations-xxxxxxxxxxxxxxx';
      return FakeReply.json(200, {
        'accessToken': access,
        'refreshToken': refresh,
      });
    }
    if (alwaysUnauthorized ||
        call.header('Authorization') != 'Bearer $access') {
      return FakeReply.error(401, meCode);
    }
    return FakeReply.json(200, {'path': call.path});
  }
}

void main() {
  final config = ApiConfig.resolve(define: '', debugBuild: true);
  late _FakeAuthServer server;
  late FakeApiAdapter adapter;
  late MemoryTokenStore store;
  late ApiClient api;
  late List<SessionExpired> events;
  late StreamSubscription<SessionExpired> subscription;
  late LogCapture logs;

  setUp(() {
    logs = LogCapture();
    server = _FakeAuthServer();
    adapter = FakeApiAdapter(server.handle);
    store = MemoryTokenStore(
      AuthTokens(accessToken: _staleAccess, refreshToken: server.refresh),
    );
    var n = 0;
    api = ApiClient(
      config: config,
      tokens: store,
      adapter: adapter,
      newRequestId: () => 'rid${(++n).toString().padLeft(13, '0')}',
    );
    events = [];
    subscription = api.sessionExpired.listen(events.add);
  });

  tearDown(() async {
    await subscription.cancel();
    api.close();
    await logs.dispose();
  });

  List<String> authHeaders(String path) => [
    for (final call in adapter.callsTo(path)) '${call.header('Authorization')}',
  ];

  void expectNoTokensInLogs() {
    for (final secret in [
      _staleAccess,
      'live-access-token',
      'live-refresh-token',
    ]) {
      expect(logs.text, isNot(contains(secret)), reason: secret);
    }
  }

  test('401 → один refresh → повтор с новым токеном, пара сохранена', () async {
    final response = await api.get('/me');

    expect(response.statusCode, 200);
    expect(adapter.calls.map((c) => '${c.method} ${c.path}'), [
      'GET /api/v1/me',
      'POST /api/v1/auth/refresh',
      'GET /api/v1/me',
    ]);
    expect(authHeaders('/me'), [
      'Bearer $_staleAccess',
      'Bearer ${server.access}',
    ]);
    expect(
      adapter.callsTo('/auth/refresh').single.header('Authorization'),
      isNull,
    );
    final tokens = await store.readTokens();
    expect(tokens!.accessToken, server.access);
    expect(tokens.refreshToken, server.refresh);

    final me = adapter.callsTo('/me');
    expect(me[0].header('X-Request-Id'), me[1].header('X-Request-Id'));
    expect(response.requestId, me[0].header('X-Request-Id'));
    expect(
      adapter.callsTo('/auth/refresh').single.header('X-Request-Id'),
      isNot(me[0].header('X-Request-Id')),
    );

    final text = logs.text;
    expect(
      text,
      contains(
        'access token rejected: GET /api/v1/me 401 '
        'unauthorized → refreshing session',
      ),
    );
    expect(text, contains('POST /api/v1/auth/refresh 200 in '));
    expect(text, contains('session refreshed in '));
    expect(text, contains('GET /api/v1/me 200 in '));
    expect(text, contains('attempt=2'));
    expect(text, contains('<omitted: response with tokens>'));
    expect(events, isEmpty);
    expectNoTokensInLogs();
  });

  test('refresh отклонён (401) → событие «сессия закончилась», запрос - '
      'ApiSessionExpired, дальше без сети', () async {
    server.refresh = 'refresh-token-the-server-knows-wwwwwww';

    await expectLater(
      api.get('/me'),
      throwsA(
        isA<ApiSessionExpired>().having(
          (e) => e.reason,
          'reason',
          SessionEndReason.refreshRejected,
        ),
      ),
    );
    await pumpEventQueue();

    expect(events, hasLength(1));
    expect(events.single.reason, SessionEndReason.refreshRejected);
    expect(events.single.path, '/api/v1/me');
    expect(
      logs.text,
      contains(
        'refresh token expired → re-login (401 '
        'session_expired)',
      ),
    );
    expect(logs.text, contains('session expired event reason=refreshRejected'));

    final sent = adapter.calls.length;
    await expectLater(
      api.get('/budgets'),
      throwsA(
        isA<ApiSessionExpired>().having(
          (e) => e.reason,
          'reason',
          SessionEndReason.endedEarlier,
        ),
      ),
    );
    await pumpEventQueue();
    expect(adapter.calls, hasLength(sent));
    expect(events, hasLength(1));
    expectNoTokensInLogs();
  });

  test('два параллельных 401 - один refresh, оба повторены; запрос во время '
      'refresh ждёт и уходит с новым токеном', () async {
    server.refreshGate = Completer<void>();

    final first = api.get('/me');
    final second = api.get('/budgets');
    while (server.refreshCalls == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    await pumpEventQueue();
    final third = api.get('/sync/pull');
    await pumpEventQueue();
    server.refreshGate!.complete();
    final results = await Future.wait([first, second, third]);

    expect(results.map((r) => r.statusCode), [200, 200, 200]);
    expect(server.refreshCalls, 1);
    expect(authHeaders('/me'), [
      'Bearer $_staleAccess',
      'Bearer ${server.access}',
    ]);
    expect(authHeaders('/budgets'), [
      'Bearer $_staleAccess',
      'Bearer ${server.access}',
    ]);
    expect(authHeaders('/sync/pull'), ['Bearer ${server.access}']);
    expect(
      logs.text,
      contains('session refresh already in progress → waiting'),
    );
    expect(events, isEmpty);
  });

  test('401 bad_credentials - не refresh, ошибка как есть', () async {
    server.alwaysUnauthorized = true;
    server.meCode = 'bad_credentials';

    await expectLater(
      api.delete('/account', body: const {'password': 'x'}),
      throwsA(
        isA<ApiErrorResponse>().having(
          (e) => e.code,
          'code',
          ApiErrorCode.badCredentials,
        ),
      ),
    );

    expect(server.refreshCalls, 0);
    expect(logs.text, contains('401 bad_credentials → wrong password'));
    await pumpEventQueue();
    expect(events, isEmpty);
  });

  test(
    '401 session_expired на обычном запросе - событие без refresh',
    () async {
      server.alwaysUnauthorized = true;
      server.meCode = 'session_expired';

      await expectLater(
        api.post('/auth/recovery-code', body: const {'password': 'x'}),
        throwsA(
          isA<ApiSessionExpired>().having(
            (e) => e.reason,
            'reason',
            SessionEndReason.sessionRejected,
          ),
        ),
      );
      await pumpEventQueue();

      expect(server.refreshCalls, 0);
      expect(events.single.reason, SessionEndReason.sessionRejected);
    },
  );

  test('refresh не дошёл (нет сети) - без события, сессия остаётся, ошибка '
      'сети у исходного запроса', () async {
    server.refreshThrows = const SocketException('Network is unreachable');

    await expectLater(
      api.get('/me'),
      throwsA(
        isA<ApiNetworkFailure>()
            .having((e) => e.path, 'path', '/api/v1/me')
            .having((e) => e.problem, 'problem', ApiNetworkProblem.connection),
      ),
    );
    await pumpEventQueue();

    expect(events, isEmpty);
    expect((await store.readTokens())!.accessToken, _staleAccess);
    expect(logs.text, contains('session refresh failed in '));
    expect(logs.text, contains('→ session kept, request fails'));

    server.refreshThrows = null;
    final retried = await api.get('/me');
    expect(retried.statusCode, 200);
    expect(server.refreshCalls, 2);
  });

  test(
    'после refresh снова 401 - только один повтор, ошибка unauthorized',
    () async {
      server.alwaysUnauthorized = true;

      await expectLater(
        api.get('/me'),
        throwsA(
          isA<ApiErrorResponse>().having(
            (e) => e.code,
            'code',
            ApiErrorCode.unauthorized,
          ),
        ),
      );

      expect(server.refreshCalls, 1);
      expect(adapter.callsTo('/me'), hasLength(2));
      expect(
        logs.text,
        contains('still 401 unauthorized after session refresh'),
      );
    },
  );

  test(
    'нет токенов - запрос не уходит, без события; без авторизации - уходит',
    () async {
      final empty = ApiClient(
        config: config,
        tokens: MemoryTokenStore(),
        adapter: adapter,
      );
      final emptyEvents = <SessionExpired>[];
      final sub = empty.sessionExpired.listen(emptyEvents.add);

      await expectLater(
        empty.get('/me'),
        throwsA(
          isA<ApiSessionExpired>().having(
            (e) => e.reason,
            'reason',
            SessionEndReason.noSession,
          ),
        ),
      );
      expect(adapter.calls, isEmpty);

      server.alwaysUnauthorized = true;
      await expectLater(
        empty.post('/auth/login', body: const {}, auth: false),
        throwsA(isA<ApiErrorResponse>()),
      );
      expect(adapter.calls.single.header('Authorization'), isNull);
      expect(server.refreshCalls, 0);
      await pumpEventQueue();
      expect(emptyEvents, isEmpty);
      await sub.cancel();
      empty.close();
    },
  );
}
