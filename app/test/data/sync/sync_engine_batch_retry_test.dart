import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/api/api_exception.dart';
import 'package:milionchik/data/sync/sync_engine.dart';
import 'package:shared/shared.dart';

import '../api/fake_api_adapter.dart';
import 'sync_engine_fixture.dart';

void main() {
  late LogCapture logs;
  late EngineServer server;
  late TestClock clock;
  late EngineDevice phone;

  setUp(() async {
    logs = LogCapture();
    server = seededServer();
    clock = TestClock(DateTime.utc(2026, 10, 19, 15, 40));
    phone = EngineDevice(server, name: 'phone', clock: clock);
    await phone.sync();
  });

  tearDown(() async {
    phone.dispose();
    await logs.dispose();
  });

  test('ответ на пачку потерян после записи на сервере: повтор с тем же '
      'batchId, сервер отвечает прежним результатом, дублей нет', () async {
    final added = [
      for (final r in [101, 202, 303]) await phone.add(r),
    ];
    final writesBefore = server.writes;
    server.dropNextPushAnswer = true;

    final broken = await phone.sync();

    expect(broken, isA<SyncCycleFailed>());
    expect((broken as SyncCycleFailed).error, isA<ApiNetworkFailure>());
    expect(server.writes - writesBefore, 3);
    expect(await phone.outbox.count(), 3);
    expect(phone.engine.state.phase, SyncPhase.waitingNetwork);

    await phone.fireRetry();

    expect(server.pushBatchIds, ['phone-batch-1', 'phone-batch-1']);
    expect(server.writes - writesBefore, 3);
    expect(server.countOf(SyncEntity.expense), 3);
    expect(await phone.outbox.count(), 0);
    expect(await phone.rows('expenses'), 3);
    for (final e in added) {
      expect(server.stored<Expense>(SyncEntity.expense, e.id).id, e.id);
    }
    expect(
      logs.linesOf('sync', Level.INFO),
      contains(
        contains(
          'resends batchId=phone-batch-1 changes=3 send=2: the previous send '
          'broke off without an answer',
        ),
      ),
    );
    expect(
      logs.linesOf('sync', Level.WARNING),
      contains(
        contains(
          'push batch=1 trigger=manual batchId=phone-batch-1 changes=3 failed '
          'ApiNetworkFailure: connection',
        ),
      ),
    );
  });

  test('после ответа сервера следующая пачка получает новый batchId', () async {
    await phone.add(101);
    await phone.sync();
    await phone.add(202);
    await phone.sync();

    expect(server.pushBatchIds, ['phone-batch-1', 'phone-batch-2']);
  });

  test('205 изменений уходят пачками 200 и 5 с разными batchId', () async {
    for (var i = 0; i < 205; i++) {
      await phone.add(100 + i);
    }

    final result = await phone.sync();

    expect(result, isA<SyncCycleDone>());
    final push = (result as SyncCycleDone).push;
    expect((push.sent, push.applied, push.batches), (205, 205, 2));
    expect(server.pushBatchIds, ['phone-batch-1', 'phone-batch-2']);
    expect(server.countOf(SyncEntity.expense), 205);
    expect(await phone.outbox.count(), 0);
  });

  test('ошибка 400 на пачку: batchId забыт, без повтора по таймеру, '
      'следующая попытка — новый batchId', () async {
    await phone.add(101);
    server.beforePush = (call) => FakeReply.error(400, 'bad_request');

    final failed = await phone.sync();

    expect(failed, isA<SyncCycleFailed>());
    expect((failed as SyncCycleFailed).retryIn, isNull);
    expect(phone.engine.state.phase, SyncPhase.error);
    expect(phone.timers.all, isEmpty);
    expect(await phone.outbox.count(), 1);

    server.beforePush = null;
    expect(await phone.sync(), isA<SyncCycleDone>());
    expect(
      [for (final c in phone.adapter.callsTo('/sync/push')) c.json['batchId']],
      ['phone-batch-1', 'phone-batch-2'],
    );
    expect(await phone.outbox.count(), 0);
  });
}
