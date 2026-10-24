import 'dart:async';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/isolate_lock.dart';
import 'package:milionchik/data/api/api_client.dart';
import 'package:milionchik/data/api/api_config.dart';
import 'package:milionchik/data/api/auth_interceptor.dart';
import 'package:milionchik/data/api/token_store.dart';

import 'fake_api_adapter.dart';

const _expiredAccess = 'expired-access-alpha-across-isolates';

final class _RotatingServer {
  String access = 'live-access-1-bravo-across-isolates';
  String refresh = 'live-refresh-1-charlie-across-isolates';
  final List<String> refreshTokensSeen = [];
  bool revoked = false;
  Completer<void> refreshGate = Completer<void>();
  int rotations = 1;

  Future<FakeReply> handle(FakeCall call) async {
    if (call.path.endsWith('/auth/refresh')) {
      final sent = call.json['refreshToken']! as String;
      refreshTokensSeen.add(sent);
      await refreshGate.future;
      if (revoked || sent != refresh) {
        revoked = true;
        return FakeReply.error(401, 'session_expired');
      }
      rotations++;
      access = 'live-access-$rotations-bravo-across-isolates';
      refresh = 'live-refresh-$rotations-charlie-across-isolates';
      return FakeReply.json(200, {
        'accessToken': access,
        'refreshToken': refresh,
      });
    }
    if (revoked || call.header('Authorization') != 'Bearer $access') {
      return FakeReply.error(401, 'unauthorized');
    }
    return FakeReply.json(200, {'path': call.path});
  }
}

Future<void> _until(bool Function() done) async {
  final sw = Stopwatch()..start();
  while (!done()) {
    if (sw.elapsed > const Duration(seconds: 10)) {
      throw StateError('condition not reached in 10s');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  final config = ApiConfig.resolve(define: '', debugBuild: true);
  late LogCapture logs;

  setUp(() => logs = LogCapture());
  tearDown(() => logs.dispose());

  test(
    'приложение и фоновая задача одновременно получили 401: refresh '
    'уходит один раз, второй ждёт замок и берёт сохранённые токены',
    () async {
      final server = _RotatingServer();
      final stored = MemoryTokenStore(
        AuthTokens(accessToken: _expiredAccess, refreshToken: server.refresh),
      );
      final lock = 'test.session-refresh.${Isolate.current.hashCode}';
      var n = 0;
      ApiClient client(String who) => ApiClient(
        config: config,
        tokens: stored,
        adapter: FakeApiAdapter(server.handle),
        newRequestId: () => 'rid$who${(++n).toString().padLeft(8, '0')}',
        refreshLock: IsolateLock(lock),
      );
      final app = client('app');
      final background = client('bgr');
      final appExpired = <SessionExpired>[];
      final backgroundExpired = <SessionExpired>[];
      final subscriptions = [
        app.sessionExpired.listen(appExpired.add),
        background.sessionExpired.listen(backgroundExpired.add),
      ];

      final fromApp = app.get('/me');
      final fromBackground = background.get('/budgets');
      await _until(() => server.refreshTokensSeen.isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(server.refreshTokensSeen, hasLength(1));
      server.refreshGate.complete();

      final answers = await Future.wait([fromApp, fromBackground]);
      expect(answers.map((a) => a.statusCode), [200, 200]);
      expect(server.refreshTokensSeen, [
        'live-refresh-1-charlie-across-isolates',
      ]);
      expect(server.revoked, isFalse);
      expect(appExpired, isEmpty);
      expect(backgroundExpired, isEmpty);
      expect(
        (await stored.readTokens())!.refreshToken,
        'live-refresh-2-charlie-across-isolates',
      );
      final info = logs.linesOf('api', Level.INFO);
      expect(
        info,
        contains(
          matches(
            RegExp(
              r'session refresh waited \d+ms for session refresh rid=rid\w+ → '
              r'reading tokens it may have saved rid=rid\w+$',
            ),
          ),
        ),
      );
      expect(
        info,
        contains(
          contains(
            'access token already refreshed by another request → retry '
            'without refresh',
          ),
        ),
      );
      expect(logs.text, isNot(contains('charlie-across-isolates')));
      for (final s in subscriptions) {
        await s.cancel();
      }
      app.close();
      background.close();
    },
  );
}
