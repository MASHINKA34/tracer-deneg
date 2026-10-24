import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/data/api/api_client.dart';
import 'package:milionchik/data/api/api_exception.dart';
import 'package:milionchik/data/api/api_providers.dart';
import 'package:milionchik/data/api/token_store.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/repositories/outbox_queue.dart';
import 'package:milionchik/data/session/session.dart';
import 'package:milionchik/data/session/session_providers.dart';
import 'package:milionchik/data/session/session_state.dart';
import 'package:milionchik/data/sync/pull_controller.dart';
import 'package:milionchik/data/sync/pull_service.dart';
import 'package:shared/shared.dart';

import '../api/fake_api_adapter.dart';
import 'pull_fixture.dart';
import 'sync_engine_fixture.dart';

const _user = SessionUser(
  userId: engineUserId,
  login: 'anya_m',
  displayName: 'Аня',
);

void main() {
  late LogCapture logs;
  late AppDatabase db;
  late EngineServer server;
  late ProviderContainer c;

  setUp(() async {
    logs = LogCapture();
    db = AppDatabase.memory();
    server = seededServer();
    c = ProviderContainer.test(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(
          Clock(now: () => DateTime.utc(2026, 10, 19, 15, 40)),
        ),
        apiClientProvider.overrideWith(
          (ref) => ApiClient(
            config: pullApiConfig,
            tokens: MemoryTokenStore(
              const AuthTokens(
                accessToken: pullAccess,
                refreshToken: pullRefresh,
              ),
            ),
            adapter: FakeApiAdapter(server.handle),
            newRequestId: server.nextRequestId,
          ),
        ),
        sessionProvider.overrideWithBuild(
          (ref, _) => const SessionActive(_user),
        ),
      ],
    );
    expect(
      await c.read(pullControllerProvider.notifier).run(PullReason.login),
      isNotNull,
    );
    await c
        .read(expensesRepositoryProvider)
        .create(
          budgetId: 'budget-personal',
          categoryId: 'budget-personal-cat',
          amount: Money.rubles(150),
          spentOn: LocalDate(2026, 10, 19),
          comment: 'kommentariy-pull-down-yankee',
        );
    server.order.clear();
  });

  tearDown(() async {
    await logs.dispose();
    await db.close();
  });

  test('потянуть вниз: полный цикл движка - сначала push очереди, потом '
      'pull; очередь пуста, трата на сервере', () async {
    final pulled = await c
        .read(pullControllerProvider.notifier)
        .run(PullReason.manual);

    expect(server.order, ['POST /api/v1/sync/push', 'GET /api/v1/sync/pull']);
    expect(await DriftOutboxQueue(db).count(), 0);
    expect(server.countOf(SyncEntity.expense), 1);
    expect(pulled!.reason, PullReason.manual);
    expect(c.read(pullControllerProvider), isA<PullIdle>());
    expect(
      logs.linesOf('sync', Level.FINE),
      containsAllInOrder([
        endsWith(
          'pull reason=manual → full sync cycle (push, then pull) in the sync '
          'engine',
        ),
        endsWith('sync trigger reason=manual: pulled down on the main screen'),
      ]),
    );
    expect(
      logs.linesOf('sync', Level.INFO),
      contains(endsWith('sync cycle start reason=manual attempt=1 queue=1')),
    );
  });

  test('потянуть вниз без сети: push не прошёл - pull показан неудачным '
      '(снекбар «Не удалось загрузить»), очередь на месте', () async {
    server.online = false;

    final pulled = await c
        .read(pullControllerProvider.notifier)
        .run(PullReason.manual);

    expect(pulled, isNull);
    final status = c.read(pullControllerProvider) as PullFailed;
    expect(status.failure.reason, PullReason.manual);
    expect(status.failure.stage, PullStage.prepare);
    expect(status.failure.error, isA<ApiNetworkFailure>());
    expect(status.failure.attempt, 1);
    expect(await DriftOutboxQueue(db).count(), 1);
    expect(server.countOf(SyncEntity.expense), 0);
    expect(
      logs.linesOf('sync', Level.FINE),
      contains(
        endsWith(
          'pull reason=manual not started: sync cycle failed at stage=push → '
          'shown as a failed pull',
        ),
      ),
    );
  });

  test('потянуть вниз: pull не прошёл после push - в статусе та же ошибка '
      'pull, что записал сервис pull', () async {
    server.beforePull = (call) => FakeReply.error(503, 'internal');

    await c.read(pullControllerProvider.notifier).run(PullReason.manual);

    final status = c.read(pullControllerProvider) as PullFailed;
    expect(status.failure.stage, PullStage.request);
    expect(status.failure.error, isA<ApiServerFailure>());
    expect(server.countOf(SyncEntity.expense), 1);
    expect(await DriftOutboxQueue(db).count(), 0);
  });
}
