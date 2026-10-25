import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/data/api/api_client.dart';
import 'package:milionchik/data/api/api_providers.dart';
import 'package:milionchik/data/api/token_store.dart';
import 'package:milionchik/data/holiday_settings.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/sync/sync_engine.dart';
import 'package:milionchik/features/profile/theme_mode.dart';
import 'package:milionchik/l10n/app_localizations.dart';
import 'package:shared/shared.dart';

import '../../data/api/fake_api_adapter.dart';
import '../../data/sync/pull_fixture.dart';
import '../../data/sync/sync_engine_fixture.dart' show EngineServer;
import '../auth/session_expired_fixture.dart' show testUnmounting;
import '../profile/profile_fixture.dart';
import 'widget_update_fixture.dart';

const _second = Duration(seconds: 1);

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    await initializeDateFormatting('ru');
    l10n = lookupAppLocalizations(const Locale('ru'));
  });

  String total(int rubles) => Money.rubles(rubles).formatTotal();

  String today(int rubles) => l10n.widgetToday(total(rubles));

  testUnmounting('старт: одна запись - итог октября и сегодня открытого '
      'личного бюджета, без трат сентября и общего бюджета', (tester) async {
    final rig = WidgetRig(tester);
    await rig.mount();

    expect(rig.storage.writes, hasLength(1));
    final write = rig.storage.last;
    expect(write.state, 'month');
    expect(write.month, 'Октябрь');
    expect(write.total, total(2140));
    expect(write.today, today(640));
    expect(write.emoji, '🍂');
    expect(write.mood, 'autumn');
    expect(write.theme, 'system');
    expect(rig.reasons.single, contains('startup'));
  });

  testUnmounting('трата сегодня: запись через 1 с с новым итогом и «сегодня», '
      'не раньше', (tester) async {
    final rig = WidgetRig(tester);
    await rig.mount();

    await rig.act(
      (c) => c
          .read(expensesRepositoryProvider)
          .create(
            budgetId: profilePersonalId,
            categoryId: 'cat-personal-0',
            amount: const Money.rubles(315),
            spentOn: LocalDate(2026, 10, 19),
          ),
    );
    await rig.time.elapse(const Duration(milliseconds: 999));
    expect(rig.storage.writes, hasLength(1));

    await rig.time.elapse(const Duration(milliseconds: 1));
    expect(rig.storage.writes, hasLength(2));
    expect(rig.storage.last.total, total(2455));
    expect(rig.storage.last.today, today(955));
    expect(rig.reasons.last, 'expenses changed');
  });

  testUnmounting('трата в общем бюджете и в сентябре: данные виджета те же - '
      'проверка есть, записи нет', (tester) async {
    final rig = WidgetRig(tester);
    await rig.mount();

    for (final (budget, day) in [
      (profileFamilyId, LocalDate(2026, 10, 19)),
      (profilePersonalId, LocalDate(2026, 9, 12)),
    ]) {
      await rig.act(
        (c) => c
            .read(expensesRepositoryProvider)
            .create(
              budgetId: budget,
              categoryId: 'cat-personal-2',
              amount: const Money.rubles(777),
              spentOn: day,
            ),
      );
      await rig.time.elapse(_second);
    }

    expect(rig.storage.writes, hasLength(1));
    expect(
      rig.logs
          .linesOf('widget', Level.FINE)
          .where((l) => l.contains('reason=expenses changed: state=month'))
          .where((l) => l.contains('unchanged since the last write')),
      hasLength(2),
    );
  });

  testUnmounting('синхронизация с другого телефона: трата пришла pull - одна '
      'запись, причина и трата, и синхронизация', (tester) async {
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
    final adapter = FakeApiAdapter((call) {
      if (call.path.endsWith('/me')) {
        return FakeReply.json(200, widgetMeReply());
      }
      return server.handle(call);
    });
    final rig = WidgetRig(tester);
    await rig.mount(
      overrides: [
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
            newRequestId: server.nextRequestId,
          ),
        ),
      ],
    );

    SyncCycleResult? result;
    unawaited(
      rig.container
          .read(syncEngineProvider)
          .sync(SyncReason.websocket)
          .then((r) => result = r),
    );
    for (var i = 0; i < 50 && result == null; i++) {
      await rig.settle();
    }
    expect(result, isA<SyncCycleDone>());
    expect(rig.storage.writes, hasLength(1));
    await rig.time.elapse(_second);

    expect(rig.storage.writes, hasLength(2));
    expect(rig.storage.last.total, total(3374));
    expect(rig.storage.last.today, today(1874));
    expect(
      rig.reasons.last.split('+'),
      unorderedEquals(['expenses changed', 'sync done']),
    );
  });

  testUnmounting('тема приложения тёмная: запись theme=dark', (tester) async {
    final rig = WidgetRig(tester);
    await rig.mount();

    await rig.act((c) => c.read(themeModeProvider.notifier).set(ThemeMode.dark));
    await rig.time.elapse(_second);

    expect(rig.storage.writes, hasLength(2));
    expect(rig.storage.last.theme, 'dark');
    expect(rig.storage.last.total, total(2140));
    expect(rig.reasons.last, 'theme changed');
  });

  testUnmounting('системная тема при теме «как в системе»: перерисовка с теми '
      'же данными', (tester) async {
    final rig = WidgetRig(tester);
    await rig.mount();
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await rig.settle();
    await rig.time.elapse(_second);

    expect(rig.storage.writes, hasLength(2));
    expect(rig.storage.writes[1].text, rig.storage.writes[0].text);
    expect(rig.storage.redraws, hasLength(2));
    expect(rig.reasons.last, 'system theme changed');
  });

  testUnmounting('открыт общий бюджет: запись с его итогом', (tester) async {
    final rig = WidgetRig(tester);
    await rig.mount();

    await rig.act(
      (c) => c
          .read(budgetSelectionProvider.notifier)
          .select(profileFamilyId, from: profilePersonalId, by: 'test'),
    );
    await rig.time.elapse(_second);

    expect(rig.storage.writes, hasLength(2));
    expect(rig.storage.last.total, total(300));
    expect(rig.storage.last.today, today(300));
    expect(rig.reasons.last, 'budget changed');
  });

  testUnmounting('смена дня: 31 октября - хеллоуин 🎃 и «сегодня» 0 ₽; '
      '1 ноября - новый месяц с нулём', (tester) async {
    final rig = WidgetRig(tester);
    await rig.mount();

    await rig.act(
      (c) => c.read(todayOverrideProvider.notifier).set(LocalDate(2026, 10, 31)),
    );
    await rig.time.elapse(_second);

    expect(rig.storage.writes, hasLength(2));
    expect(rig.storage.last.mood, 'halloween');
    expect(rig.storage.last.emoji, '🎃');
    expect(rig.storage.last.month, 'Октябрь');
    expect(rig.storage.last.total, total(2140));
    expect(rig.storage.last.today, today(0));
    expect(rig.reasons.last, 'day changed');

    await rig.act(
      (c) => c.read(todayOverrideProvider.notifier).set(LocalDate(2026, 11, 1)),
    );
    await rig.time.elapse(_second);

    expect(rig.storage.writes, hasLength(3));
    expect(rig.storage.last.mood, 'autumn');
    expect(rig.storage.last.emoji, '🍂');
    expect(rig.storage.last.month, 'Ноябрь');
    expect(rig.storage.last.total, total(0));
  });

  testUnmounting('смена настроения в тот же день: хеллоуин выключен в '
      'настройках праздников 31 октября - одна запись с осенью 🍂, причина '
      '«mood changed»', (tester) async {
    final patches = <FakeCall>[];
    final rig = WidgetRig(tester);
    await rig.mount(
      today: LocalDate(2026, 10, 31),
      overrides: [
        apiClientProvider.overrideWith(
          (ref) => ApiClient(
            config: pullApiConfig,
            tokens: MemoryTokenStore(
              const AuthTokens(
                accessToken: pullAccess,
                refreshToken: pullRefresh,
              ),
            ),
            adapter: FakeApiAdapter((call) {
              if (call.path.endsWith('/me') && call.method == 'PATCH') {
                patches.add(call);
                return FakeReply.json(200, {
                  ...widgetMeReply(),
                  'holidaysDisabled': ['halloween'],
                });
              }
              throw StateError('unexpected ${call.method} ${call.path}');
            }),
            newRequestId: () => 'ridwidgetmood001',
          ),
        ),
      ],
    );
    expect(rig.storage.last.mood, 'halloween');
    expect(rig.storage.last.emoji, '🎃');
    final before = rig.storage.writes.length;

    final saved = await rig.act(
      (c) => c
          .read(accountHolidaySettingsProvider.notifier)
          .setHoliday(HolidayKey.halloween, false),
    );
    await rig.time.elapse(const Duration(seconds: 3));

    expect(saved, isTrue);
    expect(patches, hasLength(1));
    final after = rig.storage.writes.sublist(before);
    expect(after, hasLength(1));
    expect(after.single.mood, 'autumn');
    expect(after.single.emoji, '🍂');
    expect(after.single.month, 'Октябрь');
    expect(after.single.total, total(2140));
    expect(rig.reasons.last, 'mood changed');
  });
}
