import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/sync/pull_service.dart';
import 'package:milionchik/data/sync/sync_engine.dart';
import 'package:milionchik/data/sync/sync_service.dart';

import '../api/fake_api_adapter.dart';
import 'sync_engine_fixture.dart';

void main() {
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
    server.order.clear();
  });

  tearDown(() async {
    phone.dispose();
    await logs.dispose();
  });

  Completer<void> gatePush() {
    final gate = Completer<void>();
    server.beforePush = (call) async {
      await gate.future;
      return null;
    };
    return gate;
  }

  test('три вызова во время цикла: ровно один цикл после текущего, '
      'второй и третий получают его результат', () async {
    await phone.add(100);
    final gate = gatePush();

    final first = phone.sync();
    await pumpEventQueue();
    expect(phone.engine.isRunning, isTrue);
    final second = phone.sync();
    final third = phone.sync();
    gate.complete();
    final results = await Future.wait([first, second, third]);

    expect(identical(results[1], results[2]), isTrue);
    expect(identical(results[0], results[1]), isFalse);
    expect(results, everyElement(isA<SyncCycleDone>()));
    expect(server.order, [
      'POST /api/v1/sync/push',
      'GET /api/v1/sync/pull',
      'GET /api/v1/sync/pull',
    ]);
    expect(server.maxInFlight, 1);
    expect(
      logs.linesOf('sync', Level.FINE),
      containsAllInOrder([
        contains(
          'sync reason=manual requested while cycle manual runs → one more '
          'cycle after it',
        ),
        endsWith('sync reason=manual joins the cycle queued for reason=manual'),
      ]),
    );
    expect(
      logs.linesOf('sync', Level.INFO),
      contains(
        endsWith(
          'sync cycle start reason=manual joined=[manual] attempt=1 '
          'queue=0',
        ),
      ),
    );
  });

  test('два вызова до начала цикла склеиваются в один', () async {
    final a = phone.sync();
    final b = phone.sync(SyncReason.retry);

    expect(identical(await a, await b), isTrue);
    expect(server.order, ['GET /api/v1/sync/pull']);
  });

  test('pull первой загрузки и sync now ждут идущий цикл, запросы не '
      'пересекаются', () async {
    await phone.add(100);
    final gate = gatePush();

    final cycle = phone.sync();
    await pumpEventQueue();
    final pulled = phone.engine.pullNow(PullReason.login);
    final pushed = phone.engine.syncNow();
    final pushedAgain = phone.engine.syncNow();
    expect(identical(pushed, pushedAgain), isTrue);
    gate.complete();

    expect(await cycle, isA<SyncCycleDone>());
    expect(await pulled, isNotNull);
    expect(await pushed, isA<SyncNowDone>());
    expect(server.order, [
      'POST /api/v1/sync/push',
      'GET /api/v1/sync/pull',
      'GET /api/v1/sync/pull',
    ]);
    expect(server.maxInFlight, 1);
    expect(
      logs.linesOf('sync', Level.FINE),
      contains(
        endsWith('pull reason=login waits for cycle manual in the sync engine'),
      ),
    );
  });

  test('удержание на время очистки: ждёт цикл, отменяет повтор и '
      'пропускает новые запуски до смены сессии', () async {
    await phone.add(100);
    server.online = false;
    await phone.sync();
    expect(phone.engine.retryScheduled, isTrue);
    server.online = true;

    await phone.engine.hold('sign-out');

    expect(phone.engine.retryScheduled, isFalse);
    expect(phone.timers.active, isEmpty);
    final skipped = await phone.sync();
    expect((skipped as SyncCycleSkipped).why, 'held by sign-out');
    expect(await phone.engine.pullNow(PullReason.manual), isNull);
    final now = await phone.engine.syncNow();
    expect((now as SyncNowFailed).remaining, 1);
    expect(server.order.where((r) => r.contains('/sync/')), [
      'POST /api/v1/sync/push',
    ]);

    phone.engine.release('test');
    expect(await phone.sync(), isA<SyncCycleDone>());
    expect(await phone.outbox.count(), 0);
    expect(
      logs.linesOf('sync', Level.INFO),
      containsAllInOrder([
        contains('sync held by sign-out: retry timer cancelled'),
        contains('sync held by sign-out: engine idle after'),
        endsWith('sync cycle skipped reason=manual: held by sign-out'),
        endsWith('sync hold by sign-out released: test'),
      ]),
    );
  });
}
