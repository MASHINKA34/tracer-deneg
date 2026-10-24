import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/api/api_exception.dart';
import 'package:milionchik/data/sync/sync_engine.dart';
import 'package:shared/shared.dart';

import '../api/fake_api_adapter.dart';
import 'pull_fixture.dart';
import 'sync_engine_fixture.dart';

void main() {
  late LogCapture logs;

  setUp(() => logs = LogCapture());
  tearDown(() => logs.dispose());

  test('без сети 3 траты остаются в очереди, цикл ждёт сети с повтором через '
      '2 с; сеть появилась — повтор отправляет их, очередь пуста', () async {
    final server = seededServer();
    final clock = TestClock(DateTime.utc(2026, 10, 19, 15, 40));
    final phone = EngineDevice(server, name: 'phone', clock: clock);
    addTearDown(phone.dispose);
    expect(await phone.sync(), isA<SyncCycleDone>());

    server.online = false;
    final added = [
      for (final r in [120, 340, 560]) await phone.add(r),
    ];
    final failed = await phone.sync();

    expect(failed, isA<SyncCycleFailed>());
    failed as SyncCycleFailed;
    expect(failed.stage, SyncStage.push);
    expect(failed.error, isA<ApiNetworkFailure>());
    expect(failed.retryIn, const Duration(seconds: 2));
    expect(phone.engine.state.phase, SyncPhase.waitingNetwork);
    expect(phone.engine.state.queueSize, 3);
    expect(phone.engine.state.retryAt, clock.now.add(failed.retryIn!));
    expect(await phone.outbox.count(), 3);
    expect(server.countOf(SyncEntity.expense), 0);
    expect(phone.timers.active, hasLength(1));

    server.online = true;
    await phone.fireRetry();

    expect(await phone.outbox.count(), 0);
    expect(
      [
        for (final e in added)
          server.stored<Expense>(SyncEntity.expense, e.id).amount,
      ],
      [Money.rubles(120), Money.rubles(340), Money.rubles(560)],
    );
    expect(phone.engine.state.phase, SyncPhase.idle);
    expect(phone.engine.state.failures, 0);
    expect(phone.engine.state.queueSize, 0);
    expect(phone.engine.state.lastSyncAt, clock.now);
    expect(phone.timers.active, isEmpty);
    for (final e in added) {
      expect((await phone.row(e.id))!.serverSeq, isNotNull);
    }

    final info = logs.linesOf('sync', Level.INFO);
    expect(
      info,
      containsAllInOrder([
        endsWith('sync cycle start reason=manual attempt=1 queue=3'),
        contains('sync retry timer fired after 2000ms → cycle reason=retry'),
        endsWith('sync cycle start reason=retry attempt=2 queue=3'),
        matches(
          RegExp(
            r'push batch=1 batchId=phone-batch-\d+ changes=3 applied=3 '
            r'rejected=0 codes=- removed=3 cursor=\d+ rid=ridengine\d+ ',
          ),
        ),
        matches(
          RegExp(
            r'sync cycle done reason=retry attempt=2 push: sent=3 applied=3 '
            r'rejected=0 batches=1 in \d+ms; pull: pages=1 entities=3 '
            r'cursor=\d+→\d+ kept=0 removedBudgets=0 apply=\d+ms in \d+ms; '
            r'queue=3→0 in \d+ms$',
          ),
        ),
      ]),
    );
    expect(
      logs.linesOf('sync', Level.WARNING),
      contains(
        matches(
          RegExp(
            r'sync cycle failed reason=manual stage=push batch=1 '
            r'batchId=phone-batch-\d+ attempt=1 ApiNetworkFailure: connection '
            r'.* → retry attempt=2 in 2000ms, queue=3 kept$',
          ),
        ),
      ),
    );
    expect(logs.text, isNot(contains('kommentariy-engine-oscar-papa')));
    expect(logs.text, isNot(contains(pullAccess)));
  });

  test('без сессии цикл не идёт на сервер и не ставит повтор', () async {
    final server = seededServer();
    final phone = EngineDevice(
      server,
      name: 'phone',
      clock: TestClock(DateTime.utc(2026, 10, 19, 15, 40)),
    )..signedIn = false;
    addTearDown(phone.dispose);

    final result = await phone.sync();

    expect(result, isA<SyncCycleSkipped>());
    expect((result as SyncCycleSkipped).why, 'no active session');
    expect(server.order, isEmpty);
    expect(phone.timers.all, isEmpty);
    expect(
      logs.linesOf('sync', Level.INFO),
      contains(endsWith('sync cycle skipped reason=manual: no active session')),
    );
  });
}
