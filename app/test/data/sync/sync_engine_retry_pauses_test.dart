import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/api/api_exception.dart';
import 'package:milionchik/data/session/session.dart';
import 'package:milionchik/data/session/session_state.dart';
import 'package:milionchik/data/sync/sync_engine.dart';

import '../api/fake_api_adapter.dart';
import 'sync_engine_fixture.dart';

const _user = SessionUser(
  userId: engineUserId,
  login: 'anya_m',
  displayName: 'Аня',
);

void main() {
  test('паузы повторов: 2, 4, 8 … до 300 с, разброс ±20 % и потолок', () {
    List<int> seconds(double random) => [
      for (var attempt = 1; attempt <= 11; attempt++)
        syncRetryDelay(attempt, random).inMilliseconds,
    ];

    expect(seconds(0.5), [
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
      300000,
    ]);
    expect(seconds(0).take(3), [1600, 3200, 6400]);
    expect(seconds(0.999).take(2), [2399, 4798]);
    expect(seconds(0).last, 240000);
    expect(seconds(0.999).last, 300000);
    expect(syncRetryDelay(1000, 0.5), const Duration(seconds: 300));
    expect(syncRetryDelay(0, 0.5), const Duration(seconds: 2));
  });

  group('движок', () {
    late LogCapture logs;
    late EngineServer server;
    late EngineDevice phone;

    setUp(() async {
      logs = LogCapture();
      server = seededServer();
      phone = EngineDevice(
        server,
        name: 'phone',
        clock: TestClock(DateTime.utc(2026, 10, 19, 15, 40)),
      );
      await phone.sync();
      await phone.add(100);
    });

    tearDown(() async {
      phone.dispose();
      await logs.dispose();
    });

    test('без сети паузы растут 2, 4, 8, 16 с; успех сбрасывает счёт, '
        'следующая ошибка снова ждёт 2 с', () async {
      server.online = false;
      await phone.sync();
      for (var i = 0; i < 3; i++) {
        await phone.fireRetry();
      }
      expect(phone.timers.delays, [
        const Duration(seconds: 2),
        const Duration(seconds: 4),
        const Duration(seconds: 8),
        const Duration(seconds: 16),
      ]);
      expect(phone.engine.state.failures, 4);
      expect(phone.engine.state.phase, SyncPhase.waitingNetwork);

      server.online = true;
      await phone.fireRetry();
      expect(phone.engine.state.failures, 0);
      expect(phone.engine.state.phase, SyncPhase.idle);
      expect(phone.timers.active, isEmpty);

      server.online = false;
      await phone.add(200);
      await phone.sync();
      expect(phone.timers.delays.last, const Duration(seconds: 2));
      expect(
        logs.linesOf('sync', Level.WARNING),
        containsAllInOrder([
          matches(
            RegExp(
              r'sync cycle failed reason=manual .*attempt=1 '
              r'ApiNetworkFailure: .* → retry attempt=2 in 2000ms, queue=1 '
              r'kept$',
            ),
          ),
          matches(
            RegExp(
              r'sync cycle failed reason=retry .*attempt=4 '
              r'ApiNetworkFailure: .* → retry attempt=5 in 16000ms, queue=1 '
              r'kept$',
            ),
          ),
        ]),
      );
    });

    test('ручной запуск раньше таймера отменяет таймер повтора', () async {
      server.online = false;
      await phone.sync();
      final timer = phone.timers.active.single;
      server.online = true;

      expect(await phone.sync(), isA<SyncCycleDone>());

      expect(timer.isActive, isFalse);
      expect(phone.timers.active, isEmpty);
    });

    test('503 сервера: ошибка и повтор с паузой; 401 session_expired: без '
        'повтора', () async {
      server.beforePush = (call) => FakeReply.error(503, 'internal');
      final busy = await phone.sync();
      expect((busy as SyncCycleFailed).retryIn, const Duration(seconds: 2));
      expect(phone.engine.state.phase, SyncPhase.error);
      expect(phone.engine.state.lastError, contains('ApiServerFailure: 503'));

      server.beforePush = (call) => FakeReply.error(401, 'session_expired');
      await phone.fireRetry();
      expect(phone.timers.active, isEmpty);
      expect(phone.engine.retryScheduled, isFalse);
      expect(phone.engine.state.phase, SyncPhase.error);
      expect(phone.engine.state.lastError, contains('ApiSessionExpired'));
      expect(
        logs.linesOf('sync', Level.INFO),
        contains(contains('→ session ended, no retry until the next sign-in')),
      );
    });

    test('смена сессии отменяет повтор и снимает удержание', () async {
      server.online = false;
      await phone.sync();
      expect(phone.engine.retryScheduled, isTrue);

      phone.engine.sessionChanged(
        const SessionActive(_user),
        const SessionEnded(_user, SessionEndReason.sessionRejected),
      );

      expect(phone.engine.retryScheduled, isFalse);
      expect(phone.engine.state.phase, SyncPhase.idle);
      expect(phone.engine.state.failures, 0);
    });
  });
}
