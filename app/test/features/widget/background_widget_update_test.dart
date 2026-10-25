import 'dart:ui';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/data/api/api_client.dart';
import 'package:milionchik/data/api/api_providers.dart';
import 'package:milionchik/data/api/token_store.dart';
import 'package:milionchik/data/holiday_settings.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/session/session_providers.dart';
import 'package:milionchik/data/session/session_state.dart';
import 'package:milionchik/data/sync/background_job.dart';
import 'package:milionchik/features/widget/home_widget_store.dart';
import 'package:milionchik/features/widget/widget_updater.dart';
import 'package:milionchik/l10n/app_localizations.dart';
import 'package:shared/shared.dart';

import '../../data/api/fake_api_adapter.dart';
import '../../data/session/fake_secure_values.dart';
import '../../data/sync/pull_fixture.dart';
import '../../data/sync/sync_engine_fixture.dart' show EngineServer;
import '../../support/app_scope.dart';
import '../profile/profile_fixture.dart';
import 'widget_update_fixture.dart';

void main() {
  late AppLocalizations l10n;
  late LogCapture logs;
  late FakeWidgetStorage storage;

  setUpAll(() async {
    await initializeDateFormatting('ru');
    l10n = lookupAppLocalizations(const Locale('ru'));
  });

  setUp(() {
    logs = LogCapture();
    storage = FakeWidgetStorage();
  });

  tearDown(() => logs.dispose());

  EngineServer otherPhone() {
    final server = EngineServer(userId: profileUserId);
    server.seed(
      serverPersonal(id: profilePersonalId, ownerId: profileUserId, seq: 0),
    );
    server.seed(
      serverExpense(
        id: otherPhoneExpenseId,
        budgetId: profilePersonalId,
        categoryId: 'cat-personal-3',
        kopecks: 123400,
        seq: 0,
      ),
    );
    server.seed(
      RecurringRule(
        id: 'rule-widget-internet',
        budgetId: profilePersonalId,
        categoryId: 'cat-personal-4',
        title: 'Интернет',
        amount: const Money.rubles(650),
        dayOfMonth: 31,
        startMonth: YearMonth(2026, 10),
        createdAt: pullT0,
        updatedAt: pullT0,
        updatedBy: profileUserId,
      ),
    );
    return server;
  }

  Future<ProviderContainer> background({
    required bool signedIn,
    EngineServer? server,
  }) async {
    final db = openTestDatabase();
    await ProfileFixture.mockup(db);
    await seedWidgetExpenses(db);
    final adapter = FakeApiAdapter((call) {
      if (call.path.endsWith('/me')) {
        return FakeReply.error(503, 'internal', 'me is down');
      }
      return (server ?? otherPhone()).handle(call);
    });
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(
          Clock(now: () => DateTime(2026, 10, 31, 3, 15)),
        ),
        secureValuesProvider.overrideWithValue(FakeSecureValues()),
        homeWidgetStoreProvider.overrideWithValue(HomeWidgetStore(storage)),
        apiClientProvider.overrideWith(
          (ref) => ApiClient(
            config: pullApiConfig,
            tokens: MemoryTokenStore(
              const AuthTokens(
                accessToken: pullAccess,
                refreshToken: pullRefresh,
              ),
            ),
            adapter: adapter,
            newRequestId: () => 'ridwidgetbg0001',
          ),
        ),
        ...backgroundWidgetOverrides(
          themeMode: ThemeMode.dark,
          holidaySettings: const CachedHolidaySettings(
            userId: profileUserId,
            settings: HolidaySettings(disabled: {HolidayKey.halloween}),
          ),
        ),
        if (signedIn)
          sessionProvider.overrideWithBuild(
            (ref, _) => const SessionActive(profileUser),
          ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('фоновая задача 31.10: pull с другого телефона, генерация регулярной, '
      'потом виджет - итог со всеми тратами, тёмная тема и выключенный '
      'хеллоуин из сохранённых настроек', () async {
    final container = await background(signedIn: true);

    final result = await BackgroundJob.from(container.read).run(
      task: periodicSyncTask,
      reason: 'periodic every 30min',
      handledBy: 'background isolate',
    );

    expect(result.errors, 0);
    expect(result.widget, 'ok');
    expect(storage.writes, hasLength(1));
    final write = storage.last;
    expect(write.state, 'month');
    expect(write.theme, 'dark');
    expect(write.mood, 'autumn');
    expect(write.emoji, '🍂');
    expect(write.total, const Money.rubles(4024).formatTotal());
    expect(write.today, l10n.widgetToday(const Money.rubles(650).formatTotal()));

    final lines = logs.lines;
    final generated = lines.indexWhere(
      (l) => l.contains('[recurring]') && l.contains('created=1'),
    );
    final widget = lines.indexWhere(
      (l) =>
          l.contains('INFO  [widget] widget updated reason=background task '
              'sync-periodic'),
    );
    expect(generated, isNot(-1));
    expect(widget, greaterThan(generated));
    expect(
      logs.linesOf('bg', Level.INFO).last,
      contains('widget=ok errors=0'),
    );
  });

  test('фоновая задача без сессии: синхронизация пропущена, виджет «Войди в '
      'Милиончик»', () async {
    final container = await background(signedIn: false);

    final result = await BackgroundJob.from(container.read).run(
      task: periodicSyncTask,
      reason: 'periodic every 30min',
      handledBy: 'background isolate',
    );

    expect(result.sync, startsWith('skipped'));
    expect(result.widget, 'ok');
    expect(storage.last.state, 'signedOut');
    expect(storage.last.theme, 'dark');
    expect(storage.last.text, isNot(contains('₽')));
    expect(
      logs.linesOf('widget', Level.INFO).last,
      contains('because=session absent'),
    );
  });

  test('фоновая задача: запись виджета не удалась - в итоге задачи '
      'widget=crashed, ошибка в отчёт', () async {
    final container = await background(signedIn: true);
    storage.saveError = StateError('prefs file is locked');

    final result = await BackgroundJob.from(container.read).run(
      task: periodicSyncTask,
      reason: 'periodic every 30min',
      handledBy: 'background isolate',
    );

    expect(result.widget, 'crashed');
    expect(result.errors, 1);
    expect(
      logs.linesOf('widget', Level.SEVERE).first,
      contains('home widget data not saved reason=background task '
          'sync-periodic'),
    );
    expect(
      [
        for (final r in logs.records)
          if (r.loggerName == 'widget' && r.level == Level.WARNING) r.message,
      ],
      [
        matches(
          RegExp(
            r'^widget update reason=background task sync-periodic not shown '
            r'after \d+ms: the widget storage failed \(error above\) → the '
            r'widget keeps its previous data, the next update writes and '
            r'redraws it again$',
          ),
        ),
      ],
    );
  });
}
