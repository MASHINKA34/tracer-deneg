import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/data/api/api_client.dart';
import 'package:milionchik/data/api/api_providers.dart';
import 'package:milionchik/data/api/token_store.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/session/session.dart';
import 'package:milionchik/data/session/session_providers.dart';
import 'package:milionchik/data/session/session_state.dart';
import 'package:milionchik/data/sync/budget_removed_notice.dart';
import 'package:milionchik/data/sync/sync_engine.dart';
import 'package:milionchik/data/sync/sync_service.dart';

import '../api/fake_api_adapter.dart';
import 'pull_fixture.dart';
import 'sync_engine_fixture.dart';

void main() {
  late LogCapture logs;
  late TestClock clock;

  setUp(() {
    logs = LogCapture();
    clock = TestClock(DateTime.utc(2026, 10, 19, 15, 40));
  });

  tearDown(() => logs.dispose());

  Future<(EngineServer, EngineDevice)> withFamily({String? owner}) async {
    final server = seededServer(family: true, familyOwner: owner);
    final phone = EngineDevice(server, name: 'phone', clock: clock);
    addTearDown(phone.dispose);
    await phone.sync();
    await phone.add(500, budgetId: familyBudgetId);
    await phone.sync();
    await phone.add(700, budgetId: familyBudgetId);
    await phone.add(900);
    expect(await phone.rows('budgets'), 2);
    expect(await phone.outbox.count(), 2);
    return (server, phone);
  }

  test('исключили из открытого общего бюджета: данные бюджета стёрты, его '
      'изменения сняты из очереди, снекбар «исключили»', () async {
    final (server, phone) = await withFamily();
    phone.selected = familyBudgetId;
    server.exclude(familyBudgetId);

    final result = await phone.sync();

    expect(result, isA<SyncCycleDone>());
    result as SyncCycleDone;
    expect(result.push.rejected.single.code, 'not_found');
    expect(result.pull.removedBudgets.single.budgetId, familyBudgetId);
    expect(await phone.rows('budgets'), 1);
    expect(
      await (phone.db.select(
        phone.db.expenses,
      )..where((e) => e.budgetId.equals(familyBudgetId))).get(),
      isEmpty,
    );
    expect(await phone.rows('expenses'), 1);
    expect(await phone.outbox.count(), 0);
    expect(phone.notices, hasLength(1));
    final (budget, kind) = phone.notices.single;
    expect(
      (budget.budgetId, budget.name, budget.wasSelected),
      (familyBudgetId, 'Семья', true),
    );
    expect(kind, BudgetRemovalKind.excluded);
    expect(
      logs.linesOf('sync', Level.INFO),
      contains(
        endsWith(
          'selected budget removed budgetId=$familyBudgetId kind=shared '
          'as=excluded → personal budget is shown, snackbar notice',
        ),
      ),
    );
    expect(logs.text, isNot(contains('Семья')));
  });

  test(
    'свой общий бюджет удалён с другого телефона: снекбар «удалён»',
    () async {
      final (server, phone) = await withFamily(owner: engineUserId);
      phone.selected = familyBudgetId;
      server.exclude(familyBudgetId);

      await phone.sync();

      expect(phone.notices.single.$2, BudgetRemovalKind.deleted);
      expect(await phone.rows('budgets'), 1);
    },
  );

  test('исключили из бюджета, который не открыт: данные стёрты, снекбара '
      'нет', () async {
    final (server, phone) = await withFamily();
    server.exclude(familyBudgetId);

    await phone.sync();

    expect(phone.notices, isEmpty);
    expect(await phone.rows('budgets'), 1);
    expect(
      logs.linesOf('sync', Level.INFO),
      contains(
        endsWith(
          'budget removed budgetId=$familyBudgetId kind=shared as=excluded: '
          'not the selected budget → data removed, no snackbar',
        ),
      ),
    );
  });

  test('через провайдеры: SyncService — движок, уведомление об исключении '
      'приходит в budgetRemovedNoticeProvider', () async {
    final server = seededServer(family: true);
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final container = ProviderContainer.test(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(Clock(now: () => clock.now)),
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
          (ref, _) => const SessionActive(
            SessionUser(
              userId: engineUserId,
              login: 'anya_m',
              displayName: 'Аня',
            ),
          ),
        ),
        selectedBudgetIdProvider.overrideWith(
          (ref) => Stream.value(familyBudgetId),
        ),
      ],
    );
    container.listen(selectedBudgetIdProvider, (_, _) {});
    final engine = container.read(syncEngineProvider);
    expect(identical(container.read(syncServiceProvider), engine), isTrue);

    expect(await engine.sync(SyncReason.manual), isA<SyncCycleDone>());
    server.exclude(familyBudgetId);
    expect(await engine.sync(SyncReason.manual), isA<SyncCycleDone>());

    final notice = container.read(budgetRemovedNoticeProvider)!;
    expect(
      (notice.budgetId, notice.name, notice.kind),
      (familyBudgetId, 'Семья', BudgetRemovalKind.excluded),
    );
    expect(
      container.read(budgetRemovedNoticeProvider.notifier).claim(notice.id),
      isTrue,
    );
    expect(
      container.read(budgetRemovedNoticeProvider.notifier).claim(notice.id),
      isFalse,
    );
  });
}
