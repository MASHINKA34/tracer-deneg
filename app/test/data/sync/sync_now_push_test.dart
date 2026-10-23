import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/api/api_client.dart';
import 'package:milionchik/data/api/api_exception.dart';
import 'package:milionchik/data/api/sync_api.dart';
import 'package:milionchik/data/api/token_store.dart';
import 'package:milionchik/data/current_user.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/repositories/expenses_repository.dart';
import 'package:milionchik/data/repositories/outbox_queue.dart';
import 'package:milionchik/data/sync/sync_service.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';
import '../api/fake_api_adapter.dart';
import 'pull_fixture.dart';

const String _comment = 'kommentariy-push-xray-yankee';

final DateTime _now = DateTime.utc(2026, 10, 19, 15, 40);

final class _Rig {
  _Rig(this.db, FakeHandler handler) : adapter = FakeApiAdapter(handler);

  final AppDatabase db;
  final FakeApiAdapter adapter;
  late final DriftOutboxQueue outbox = DriftOutboxQueue(db, now: () => _now);
  int _batch = 0;
  int _rid = 0;

  late final PushOnceSyncService service = PushOnceSyncService(
    api: SyncApi(
      ApiClient(
        config: pullApiConfig,
        tokens: MemoryTokenStore(
          const AuthTokens(accessToken: pullAccess, refreshToken: pullRefresh),
        ),
        adapter: adapter,
        newRequestId: () => 'ridpush${(++_rid).toString().padLeft(9, '0')}',
      ),
    ),
    outbox: outbox,
    newBatchId: () => 'batch-${++_batch}',
  );

  DriftExpensesRepository get expenses => DriftExpensesRepository(
    db,
    currentUser: const SessionCurrentUser(pullUserId),
    outbox: outbox,
    now: () => _now,
  );

  Future<List<Expense>> addExpenses(int count) async => [
    for (var i = 0; i < count; i++)
      await expenses.create(
        budgetId: 'budget-personal',
        categoryId: 'cat-$i',
        amount: Money.rubles(100 + i),
        spentOn: LocalDate(2026, 10, 19),
        comment: _comment,
      ),
  ];

  List<Map<String, Object?>> changesOf(FakeCall call) => [
    for (final c in call.json['changes']! as List<Object?>)
      c! as Map<String, Object?>,
  ];
}

FakeReply _applyAll(FakeCall call) => FakeReply.json(200, {
  'applied': [
    for (final c in call.json['changes']! as List<Object?>)
      (c! as Map<String, Object?>)['id'],
  ],
  'rejected': const <Object?>[],
  'cursor': 77,
});

void main() {
  late LogCapture logs;

  setUp(() => logs = LogCapture());
  tearDown(() => logs.dispose());

  test('3 траты уходят одной пачкой: очередь пуста, SyncNowDone, в логе '
      'пачка с rid и без комментариев', () async {
    final rig = _Rig(openTestDatabase(), _applyAll);
    final added = await rig.addExpenses(3);

    final result = await rig.service.syncNow();

    expect(result, isA<SyncNowDone>());
    expect((result.applied, result.rejected, result.batches), (3, 0, 1));
    expect(await rig.outbox.count(), 0);
    final call = rig.adapter.callsTo('/sync/push').single;
    expect(call.method, 'POST');
    expect(call.header('Authorization'), 'Bearer $pullAccess');
    expect(call.json['batchId'], 'batch-1');
    expect(
      [for (final c in rig.changesOf(call)) (c['entity'], c['op'], c['id'])],
      [for (final e in added) ('expense', 'upsert', e.id)],
    );
    final sync = logs.linesOf('sync', Level.INFO);
    expect(
      sync,
      contains(endsWith('sync now: one push attempt queue=3 batch up to 200')),
    );
    expect(
      sync,
      contains(
        matches(
          r'push batch=1 batchId=batch-1 changes=3 applied=3 rejected=0 '
          r'codes=- removed=3 cursor=77 rid=ridpush000000001 in \d+ms$',
        ),
      ),
    );
    expect(
      sync,
      contains(
        matches(
          r'sync now done applied=3 rejected=0 batches=1 queue=3→0 '
          r'in \d+ms$',
        ),
      ),
    );
    expect(logs.text, isNot(contains(_comment)));
    expect(logs.text, isNot(contains(pullAccess)));
  });

  test('205 изменений → две пачки 200 и 5 с разными batchId', () async {
    final rig = _Rig(openTestDatabase(), _applyAll);
    for (var i = 0; i < 205; i++) {
      await rig.outbox.enqueueDelete(SyncEntity.expense, 'e-$i', at: _now);
    }

    final result = await rig.service.syncNow();

    expect(result, isA<SyncNowDone>());
    expect(result.batches, 2);
    final calls = rig.adapter.callsTo('/sync/push');
    expect([for (final c in calls) rig.changesOf(c).length], [200, 5]);
    expect([for (final c in calls) c.json['batchId']], ['batch-1', 'batch-2']);
    expect(rig.changesOf(calls.last).last['id'], 'e-204');
    expect(await rig.outbox.count(), 0);
  });

  test('отклонённое изменение снимается из очереди, код в warn', () async {
    late String rejectedId;
    final rig = _Rig(openTestDatabase(), (call) {
      final ids = [
        for (final c in call.json['changes']! as List<Object?>)
          (c! as Map<String, Object?>)['id']! as String,
      ];
      rejectedId = ids[1];
      return FakeReply.json(200, {
        'applied': [ids[0], ids[2]],
        'rejected': [
          {'id': rejectedId, 'code': 'validation_failed'},
        ],
        'cursor': 9,
      });
    });
    await rig.addExpenses(3);

    final result = await rig.service.syncNow();

    expect(result, isA<SyncNowDone>());
    expect((result.applied, result.rejected), (2, 1));
    expect(await rig.outbox.count(), 0);
    expect(
      logs.linesOf('sync', Level.WARNING),
      contains(
        endsWith(
          'push change rejected entity=expense id=$rejectedId '
          'code=validation_failed batchId=batch-1 → dropped from the queue '
          'rid=ridpush000000001',
        ),
      ),
    );
  });

  test('нет сети: SyncNowFailed с ApiNetworkFailure, очередь цела', () async {
    final rig = _Rig(
      openTestDatabase(),
      (call) => throw const SocketException('Network is unreachable'),
    );
    await rig.addExpenses(3);

    final result = await rig.service.syncNow();

    expect(result, isA<SyncNowFailed>());
    final failed = result as SyncNowFailed;
    expect(failed.error, isA<ApiNetworkFailure>());
    expect(failed.remaining, 3);
    expect(await rig.outbox.count(), 3);
    expect(
      logs.linesOf('sync', Level.WARNING),
      contains(
        matches(
          r'sync now failed at batch=1 ApiNetworkFailure: connection .* '
          r'rid=ridpush000000001 applied=0 rejected=0 queue=3→3 '
          r'after \d+ms → changes kept in the queue',
        ),
      ),
    );
  });

  test(
    '500 на второй пачке: первая снята, остаток в очереди, severe',
    () async {
      final rig = _Rig(openTestDatabase(), (call) {
        if (call.json['batchId'] == 'batch-2') {
          return FakeReply.error(500, 'internal', 'boom');
        }
        return _applyAll(call);
      });
      for (var i = 0; i < 203; i++) {
        await rig.outbox.enqueueDelete(SyncEntity.expense, 'e-$i', at: _now);
      }

      final result = await rig.service.syncNow();

      expect(result, isA<SyncNowFailed>());
      final failed = result as SyncNowFailed;
      expect(failed.error, isA<ApiServerFailure>());
      expect((failed.applied, failed.batches, failed.remaining), (200, 1, 3));
      expect(await rig.outbox.count(), 3);
      expect(
        logs.linesOf('sync', Level.SEVERE),
        contains(contains('sync now failed at batch=2 ApiServerFailure: 500')),
      );
    },
  );

  test('удаление в окне «Отменить» не отправляется: SyncNowFailed без '
      'ошибки, remaining=1', () async {
    final rig = _Rig(openTestDatabase(), _applyAll);
    await rig.addExpenses(1);
    await rig.outbox.enqueueDelete(
      SyncEntity.expense,
      'e-undo',
      at: _now,
      notBefore: _now.add(const Duration(seconds: 5)),
    );

    final result = await rig.service.syncNow();

    expect(result, isA<SyncNowFailed>());
    final failed = result as SyncNowFailed;
    expect(failed.error, isNull);
    expect((failed.applied, failed.remaining), (1, 1));
    expect([
      for (final c in rig.changesOf(rig.adapter.calls.single)) c['id'],
    ], isNot(contains('e-undo')));
    expect(
      logs.linesOf('sync', Level.WARNING),
      contains(
        contains(
          'sync now incomplete applied=1 rejected=0 batches=1 '
          'queue=2→1',
        ),
      ),
    );
  });

  test('повторный вызов во время попытки присоединяется к ней', () async {
    final release = Completer<void>();
    final rig = _Rig(openTestDatabase(), (call) async {
      await release.future;
      return _applyAll(call);
    });
    await rig.addExpenses(2);

    final first = rig.service.syncNow();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final second = rig.service.syncNow();
    release.complete();

    expect(identical(await first, await second), isTrue);
    expect(rig.adapter.callsTo('/sync/push'), hasLength(1));
  });
}
