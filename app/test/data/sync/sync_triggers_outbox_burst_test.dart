import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart' show TableUpdate;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/sync/sync_engine.dart';
import 'package:milionchik/data/sync/sync_triggers.dart';

import '../api/fake_api_adapter.dart';
import 'sync_engine_fixture.dart';
import 'sync_triggers_fixture.dart';

void main() {
  late LogCapture logs;
  late EngineServer server;
  late EngineDevice phone;
  late VirtualTime time;
  late SyncTriggers triggers;
  late StreamSubscription<Set<TableUpdate>> writes;

  setUp(() async {
    logs = LogCapture();
    server = seededServer();
    phone = EngineDevice(
      server,
      name: 'phone',
      clock: TestClock(DateTime.utc(2026, 10, 19, 15, 40)),
    );
    time = VirtualTime(
      settle: () async {
        await pumpEventQueue();
        await phone.engine.whenIdle();
        await pumpEventQueue();
      },
    );
    final container = ProviderContainer.test(
      overrides: [appDatabaseProvider.overrideWithValue(phone.db)],
    );
    triggers = SyncTriggers(
      sync: phone.engine.sync,
      retryScheduled: () => phone.engine.retryScheduled,
      timer: time.start,
    );
    writes = container
        .read(outboxWritesProvider)
        .listen((_) => triggers.outboxWritten());
    triggers.start(signedIn: true, foreground: true);
    await time.elapse(Duration.zero);
    server.order.clear();
  });

  tearDown(() async {
    triggers.dispose();
    await writes.cancel();
    phone.dispose();
    await logs.dispose();
  });

  Future<void> write(int rubles) async {
    await phone.add(rubles);
    await pumpEventQueue();
  }

  test('пять записей с паузой 1 с: задержка 1,5 с сбрасывается каждой новой, '
      'один push с пятью изменениями через 1,5 с после последней', () async {
    for (var i = 0; i < 5; i++) {
      await write(100 + i);
      if (i < 4) {
        await time.elapse(const Duration(seconds: 1));
        expect(server.order, isEmpty, reason: 'запись ${i + 1}');
      }
    }
    expect(await phone.outbox.count(), 5);
    expect(triggers.outboxWritesWaiting, 5);

    await time.elapse(const Duration(milliseconds: 1499));
    expect(server.order, isEmpty);

    await time.elapse(const Duration(milliseconds: 1));

    expect(server.order, ['POST /api/v1/sync/push', 'GET /api/v1/sync/pull']);
    expect(server.pushBatchIds, hasLength(1));
    expect(server.batches.values.single.applied, hasLength(5));
    expect(await phone.outbox.count(), 0);
    expect(triggers.outboxDelayScheduled, isFalse);
    expect(time.now, const Duration(milliseconds: 5500));
    expect(
      logs.linesOf('sync', Level.FINE),
      containsAllInOrder([
        endsWith(
          'sync triggers: outbox write → sync reason=outbox in 1500ms unless '
          'more writes come',
        ),
        endsWith(
          'sync triggers: outbox write #5 before the delay elapsed → delay '
          'restarted, sync in 1500ms',
        ),
        endsWith(
          'sync triggers: outbox delay elapsed, 5 writes merged into one cycle',
        ),
        endsWith(
          'sync trigger reason=outbox: 5 outbox write(s), none in the last '
          '1500ms',
        ),
      ]),
    );
    expect(
      logs.linesOf('sync', Level.INFO),
      contains(endsWith('sync cycle start reason=outbox attempt=1 queue=5')),
    );
  });

  test('запись, потом появилась сеть: цикл reason=network забирает запись, '
      'задержка снята, второго push нет', () async {
    triggers.networkChanged(const [ConnectivityResult.wifi]);
    triggers.networkChanged(const [ConnectivityResult.none]);
    await write(100);
    await write(200);
    expect(triggers.outboxDelayScheduled, isTrue);

    triggers.networkChanged(const [ConnectivityResult.wifi]);
    await time.elapse(Duration.zero);

    expect(triggers.outboxDelayScheduled, isFalse);
    expect(server.order, ['POST /api/v1/sync/push', 'GET /api/v1/sync/pull']);
    expect(await phone.outbox.count(), 0);

    await time.elapse(const Duration(seconds: 5));
    expect(server.order, hasLength(2));
    expect(
      logs.linesOf('sync', Level.FINE),
      containsAllInOrder([
        endsWith('sync trigger reason=network: network appeared types=wifi'),
        endsWith(
          'sync trigger reason=network takes 2 pending outbox write(s) into '
          'its cycle → outbox delay cancelled',
        ),
      ]),
    );
    expect(
      logs.linesOf('sync', Level.INFO),
      containsAllInOrder([
        endsWith(
          'network lost types=none → sync waits for network, changes stay in '
          'the queue',
        ),
        endsWith('network appeared types=wifi → sync reason=network'),
        endsWith('sync cycle start reason=network attempt=1 queue=2'),
      ]),
    );
  });

  test('запись во время идущего цикла: после него ровно один цикл '
      'reason=outbox, изменение на сервере', () async {
    final gate = Completer<void>();
    server.beforePull = (call) async {
      await gate.future;
      return null;
    };
    final running = phone.engine.sync(SyncReason.manual);
    await pumpEventQueue();
    expect(phone.engine.isRunning, isTrue);

    await write(300);
    await time.elapse(
      const Duration(milliseconds: 1500),
      settle: () => pumpEventQueue(),
    );
    gate.complete();
    server.beforePull = null;
    await running;
    await time.elapse(Duration.zero);

    expect(server.order, [
      'GET /api/v1/sync/pull',
      'POST /api/v1/sync/push',
      'GET /api/v1/sync/pull',
    ]);
    expect(await phone.outbox.count(), 0);
    expect(
      logs.linesOf('sync', Level.FINE),
      contains(
        endsWith(
          'sync reason=outbox requested while cycle manual runs → one more '
          'cycle after it',
        ),
      ),
    );
  });

  test('без входа записи в очередь синхронизацию не запускают', () async {
    triggers.sessionChanged(active: false, change: 'active→absent');

    await write(100);
    await time.elapse(const Duration(seconds: 5));

    expect(server.order, isEmpty);
    expect(triggers.outboxDelayScheduled, isFalse);
    expect(await phone.outbox.count(), 1);
    expect(
      logs.linesOf('sync', Level.FINE),
      contains(
        endsWith('sync triggers: outbox write, no active session → no sync'),
      ),
    );
  });
}
