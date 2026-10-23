import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/data/api/api_client.dart';
import 'package:milionchik/data/api/api_config.dart';
import 'package:milionchik/data/api/auth_interceptor.dart';
import 'package:milionchik/data/api/token_store.dart';

import 'fake_api_adapter.dart';

const _readDelay = Duration(milliseconds: 60);
const _secondReplyDelay = Duration(milliseconds: 30);

final class _SlowReadStore implements TokenStore {
  _SlowReadStore(this._tokens);

  AuthTokens _tokens;
  int reads = 0;

  @override
  Future<AuthTokens?> readTokens() async {
    reads++;
    final snapshot = _tokens;
    await Future<void>.delayed(_readDelay);
    return snapshot;
  }

  @override
  Future<void> saveTokens(AuthTokens tokens) async {
    _tokens = tokens;
  }

  AuthTokens get current => _tokens;
}

final class _RotatingServer {
  String access = 'srv-access-0-qqqqqqqqqqqqqqqqqqqq';
  String refresh = 'srv-refresh-0-pppppppppppppppppppp';
  final Set<String> usedRefresh = {};
  bool revoked = false;
  int refreshCalls = 0;
  int rotation = 0;

  Future<FakeReply> handle(FakeCall call) async {
    if (call.path.endsWith('/auth/refresh')) {
      refreshCalls++;
      final sent = call.json['refreshToken'];
      if (revoked) return FakeReply.error(401, 'session_expired');
      if (usedRefresh.contains(sent)) {
        revoked = true;
        return FakeReply.error(401, 'session_expired');
      }
      if (sent != refresh) return FakeReply.error(401, 'session_expired');
      usedRefresh.add(refresh);
      rotation++;
      access = 'srv-access-$rotation-qqqqqqqqqqqqqqqqqqqq';
      refresh = 'srv-refresh-$rotation-pppppppppppppppppppp';
      return FakeReply.json(200, {
        'accessToken': access,
        'refreshToken': refresh,
      });
    }
    final authorized =
        !revoked && call.header('Authorization') == 'Bearer $access';
    if (!authorized && call.path.endsWith('/budgets')) {
      await Future<void>.delayed(_secondReplyDelay);
    }
    if (!authorized) return FakeReply.error(401, 'unauthorized');
    return FakeReply.json(200, {'path': call.path});
  }
}

void main() {
  final config = ApiConfig.resolve(define: '', debugBuild: true);

  test('медленное хранилище: два параллельных 401 - ровно один refresh, '
      'сессия не отозвана, оба запроса повторены с новым токеном', () async {
    final logs = LogCapture();
    addTearDown(logs.dispose);
    final server = _RotatingServer();
    final adapter = FakeApiAdapter(server.handle);
    final store = _SlowReadStore(
      AuthTokens(
        accessToken: 'stale-access-ssssssssssssssssssss',
        refreshToken: server.refresh,
      ),
    );
    var n = 0;
    final api = ApiClient(
      config: config,
      tokens: store,
      adapter: adapter,
      newRequestId: () => 'rid${(++n).toString().padLeft(13, '0')}',
    );
    final events = <SessionExpired>[];
    final sub = api.sessionExpired.listen(events.add);
    addTearDown(() async {
      await sub.cancel();
      api.close();
    });

    final results = await Future.wait([api.get('/me'), api.get('/budgets')]);
    await pumpEventQueue();

    expect(results.map((r) => r.statusCode), [200, 200]);
    expect(server.refreshCalls, 1);
    expect(server.revoked, isFalse);
    expect(events, isEmpty);
    expect(store.current.accessToken, server.access);
    expect(store.current.refreshToken, server.refresh);
    for (final path in ['/me', '/budgets']) {
      expect(
        adapter.callsTo(path).last.header('Authorization'),
        'Bearer ${server.access}',
        reason: path,
      );
    }
    expect(
      logs.text,
      contains('session refresh already in progress → waiting'),
    );
    expect(logs.text, isNot(contains('srv-refresh-')));
    expect(logs.text, isNot(contains('srv-access-')));
  });
}
