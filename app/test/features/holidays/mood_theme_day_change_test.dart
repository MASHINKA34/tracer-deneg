import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/app.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/holiday_settings.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/session/session.dart';
import 'package:milionchik/data/session/session_providers.dart';
import 'package:milionchik/data/session/session_state.dart';
import 'package:milionchik/features/month/month_screen.dart';
import 'package:milionchik/ui/components/month_card.dart';
import 'package:milionchik/ui/theme/app_theme.dart';
import 'package:milionchik/ui/theme/mood_colors.dart';
import 'package:shared/shared.dart';

import '../../data/api/fake_api_adapter.dart';
import '../../support/app_scope.dart';
import '../auth/session_expired_fixture.dart' show testUnmounting;
import '../month/month_fixture.dart';

const _user = SessionUser(
  userId: 'user-theme-12',
  login: 'theme_user',
  displayName: 'Оля',
);

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  late DateTime now;

  Color accentOf(Mood mood) =>
      MoodColors.forMood(mood, Brightness.light).accent;

  Color appAccent(WidgetTester tester) =>
      MoodColors.of(tester.element(find.byType(MonthScreen))).accent;

  MonthCard card(WidgetTester tester) =>
      tester.widget<MonthCard>(find.byType(MonthCard));

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(MilionchikApp)));

  Future<AppDatabase> startApp(
    WidgetTester tester, {
    bool signedIn = false,
  }) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(360, 800);
    addTearDown(tester.view.reset);
    final db = openTestDatabase();
    await tester.runAsync(() => seedMockupOctober(db));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(Clock(now: () => now)),
          if (signedIn)
            sessionProvider.overrideWithBuild(
              (ref, _) => const SessionActive(_user),
            ),
        ],
        child: const MilionchikApp(),
      ),
    );
    await tester.pumpAndSettle();
    return db;
  }

  testUnmounting('полночь 31.10 → 1.11 при открытом приложении: акцент '
      'Хеллоуина плавно сменяется осенью без перезапуска, карточка октября '
      'перестаёт быть праздничной', (tester) async {
    final logs = LogCapture();
    addTearDown(logs.dispose);
    now = DateTime(2026, 10, 31, 23, 59, 50);
    await startApp(tester);

    expect(appAccent(tester), accentOf(Mood.halloween));
    expect(card(tester).month, YearMonth(2026, 10));
    expect(card(tester).mood, Mood.halloween);
    expect(
      tester
          .widget<MaterialApp>(find.byType(MaterialApp))
          .themeAnimationDuration,
      AppTheme.transition,
    );

    now = DateTime(2026, 11, 1);
    await tester.pump(const Duration(seconds: 10));
    await tester.pump(AppTheme.transition ~/ 2);

    final halfway = appAccent(tester);
    expect(halfway, isNot(accentOf(Mood.halloween)));
    expect(halfway, isNot(accentOf(Mood.autumn)));

    await tester.pumpAndSettle();

    expect(appAccent(tester), accentOf(Mood.autumn));
    expect(card(tester).month, YearMonth(2026, 10));
    expect(card(tester).mood, Mood.autumn);
    expect(
      logs.linesOf('mood', Level.INFO).last,
      contains(
        'mood recalculated trigger=midnight date=2026-11-01 mood=autumn '
        'reason=season',
      ),
    );
  });

  testUnmounting('Хеллоуин только у карточки текущего месяца: сентябрь - '
      'осень, акцент приложения остаётся праздничным', (tester) async {
    now = DateTime(2026, 10, 28, 12);
    await startApp(tester);
    expect(card(tester).mood, Mood.halloween);

    await tester.tap(find.bySemanticsLabel('Предыдущий месяц'));
    await tester.pumpAndSettle();

    expect(card(tester).month, YearMonth(2026, 9));
    expect(card(tester).mood, Mood.autumn);
    expect(appAccent(tester), accentOf(Mood.halloween));
  });

  testUnmounting('настройки аккаунта выключили праздники: тема сезона сразу, '
      'без перезапуска', (tester) async {
    now = DateTime(2026, 10, 31, 12);
    await startApp(tester, signedIn: true);
    expect(appAccent(tester), accentOf(Mood.halloween));

    final applied = await tester.runAsync(
      () =>
          containerOf(tester)
              .read(accountHolidaySettingsProvider.notifier)
              .apply(
                User(
                  id: _user.userId,
                  login: _user.login,
                  displayName: _user.displayName,
                  holidaysEnabled: false,
                  createdAt: DateTime.utc(2026, 10, 1),
                ),
                source: 'test',
              ),
    );
    expect(applied, isTrue);
    await tester.pumpAndSettle();

    expect(appAccent(tester), accentOf(Mood.autumn));
    expect(card(tester).mood, Mood.autumn);
  });
}
