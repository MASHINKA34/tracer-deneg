import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/isolate_lock.dart';
import 'package:milionchik/data/sync/background_sync.dart';
import 'package:milionchik/data/sync/sync_engine.dart';

import '../api/fake_api_adapter.dart';
import 'sync_engine_fixture.dart';

var _locks = 0;

void main() {
  late LogCapture logs;
  late EngineServer server;
  late EngineDevice phone;
  late IsolateLock jobLock;
  late SyncEngine engine;

  setUp(() async {
    logs = LogCapture();
    server = seededServer();
    phone = EngineDevice(
      server,
      name: 'phone',
      clock: TestClock(DateTime.utc(2026, 10, 19, 15, 40)),
    );
    jobLock = IsolateLock('test.background-job.${_locks++}');
    engine = SyncEngine(
      api: () => phone.api,
      outbox: () => phone.outbox,
      pullService: () => phone.pull,
      signedInUserId: () => engineUserId,
      selectedBudgetId: () async => 'budget-personal',
      beforeRun: backgroundJobGate(jobLock, () => phone.db),
      now: phone.now,
      startTimer: phone.timers.start,
    );
  });

  tearDown(() async {
    engine.dispose();
    phone.dispose();
    await logs.dispose();
  });

  test('фоновая задача держит замок: цикл приложения ждёт её и только потом '
      'идёт к серверу; открытые экраны перечитывают базу', () async {
    await phone.add(250);
    final background = await jobLock.acquire('background task sync-periodic');
    final prefsEmits = <int>[];
    final watch = phone.db
        .select(phone.db.localPrefs)
        .watch()
        .listen((rows) => prefsEmits.add(rows.length));
    await pumpEventQueue();
    final before = prefsEmits.length;

    final cycle = engine.sync(SyncReason.startup);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(server.order, isEmpty);
    expect(await jobLock.holder(), 'background task sync-periodic');

    background.release();
    final result = await cycle;
    await pumpEventQueue();

    expect(result, isA<SyncCycleDone>());
    expect(server.order, ['POST /api/v1/sync/push', 'GET /api/v1/sync/pull']);
    expect(prefsEmits.length, greaterThan(before));
    expect(
      logs.linesOf('bg', Level.INFO),
      contains(
        matches(
          RegExp(
            r'sync cycle startup waited \d+ms for background task '
            r'sync-periodic → its database changes announced to the open '
            r'screens$',
          ),
        ),
      ),
    );
    await watch.cancel();
  });

  test('выход во время фоновой задачи: hold ждёт её конца, данные '
      'не чистятся параллельно с ней', () async {
    final background = await jobLock.acquire('background task sync-pending');
    var held = false;
    final hold = engine.hold('sign-out').then((_) => held = true);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(held, isFalse);

    background.release();
    await hold;
    expect(held, isTrue);
    expect(
      logs.linesOf('lock', Level.INFO),
      contains(
        endsWith(
          'held by background task sync-pending → app sync engine (hold by '
          'sign-out) waits',
        ),
      ),
    );
  });

  test('замок свободен: цикл идёт сразу, без лишних уведомлений', () async {
    final result = await engine.sync(SyncReason.periodic);

    expect(result, isA<SyncCycleDone>());
    expect(logs.linesOf('bg'), isEmpty);
    expect(await jobLock.holder(), isNull);
  });
}
