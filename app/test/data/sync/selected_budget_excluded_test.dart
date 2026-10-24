import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/data/api/api_client.dart';
import 'package:milionchik/data/api/api_providers.dart';
import 'package:milionchik/data/api/token_store.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:milionchik/data/session/session.dart';
import 'package:milionchik/data/session/session_providers.dart';
import 'package:milionchik/data/session/session_state.dart';
import 'package:milionchik/data/sync/budget_removed_notice.dart';
import 'package:milionchik/data/sync/sync_engine.dart';

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

  ProviderContainer phone(EngineServer server, AppDatabase db) {
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
      ],
    );
    container.listen(selectedBudgetIdProvider, (_, _) {});
    return container;
  }

  Future<String?> selectedAfterChange(
    ProviderContainer container,
    String? from,
  ) async {
    for (var i = 0; i < 100; i++) {
      final value = container.read(selectedBudgetIdProvider).value;
      if (value != from) return value;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return container.read(selectedBudgetIdProvider).value;
  }

  test('открыт общий бюджет, выбранный в переключателе; создатель исключил: '
      'движок видит его открытым — уведомление «исключили», открыт личный, '
      'сохранённый выбор стёрт', () async {
    final server = seededServer(family: true);
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final container = phone(server, db);
    final engine = container.read(syncEngineProvider);

    expect(await engine.sync(SyncReason.manual), isA<SyncCycleDone>());
    expect(await selectedAfterChange(container, null), 'budget-personal');
    await container
        .read(budgetSelectionProvider.notifier)
        .select(familyBudgetId, from: 'budget-personal', by: 'test');
    expect(
      await selectedAfterChange(container, 'budget-personal'),
      familyBudgetId,
    );

    server.exclude(familyBudgetId);
    expect(await engine.sync(SyncReason.manual), isA<SyncCycleDone>());

    final notice = container.read(budgetRemovedNoticeProvider);
    expect(
      (notice?.budgetId, notice?.name, notice?.kind),
      (familyBudgetId, 'Семья', BudgetRemovalKind.excluded),
    );
    expect(
      await selectedAfterChange(container, familyBudgetId),
      'budget-personal',
    );
    for (var i = 0; i < 100; i++) {
      if (await DriftPrefsRepository(db).getString(PrefKeys.selectedBudgetId) ==
          null) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(
      await DriftPrefsRepository(db).getString(PrefKeys.selectedBudgetId),
      isNull,
    );
    expect(
      logs.linesOf('sync', Level.INFO),
      contains(
        endsWith(
          'selected budget removed budgetId=$familyBudgetId kind=shared '
          'as=excluded → personal budget is shown, snackbar notice',
        ),
      ),
    );
    expect(
      logs.linesOf('budgets', Level.INFO),
      contains(
        contains(
          'chosen budgetId=$familyBudgetId is gone (removed or not visible to '
          'this user) → stored choice cleared',
        ),
      ),
    );
    container.dispose();
  });
}
