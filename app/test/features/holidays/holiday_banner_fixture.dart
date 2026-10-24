import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/core/router.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/holiday_settings.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:milionchik/data/session/session.dart';
import 'package:milionchik/data/session/session_providers.dart';
import 'package:milionchik/data/session/session_state.dart';
import 'package:milionchik/l10n/app_localizations.dart';
import 'package:milionchik/ui/theme/app_theme.dart';
import 'package:shared/shared.dart';

import '../../support/golden.dart';
import '../month/month_fixture.dart';
import '../../support/test_fonts.dart';

const SessionUser anya = SessionUser(
  userId: 'user-anya-67',
  login: 'anya_67',
  displayName: 'Аня',
);

final MonthDay anyaBirthday = MonthDay(11, 14);

typedef HolidayExample = ({
  HolidayKey key,
  DateTime now,
  String light,
  String dark,
});

final List<HolidayExample> figmaHolidayExamples = [
  (
    key: HolidayKey.newyear,
    now: DateTime(2026, 12, 29, 18, 40),
    light: '31:4031',
    dark: '31:4347',
  ),
  (
    key: HolidayKey.valentine,
    now: DateTime(2026, 2, 11, 18, 40),
    light: '31:4679',
    dark: '31:4945',
  ),
  (
    key: HolidayKey.defender,
    now: DateTime(2026, 2, 23, 18, 40),
    light: '31:5228',
    dark: '31:5483',
  ),
  (
    key: HolidayKey.maslenitsa,
    now: DateTime(2026, 2, 19, 18, 40),
    light: '31:5754',
    dark: '31:6268',
  ),
  (
    key: HolidayKey.women,
    now: DateTime(2027, 3, 5, 18, 40),
    light: '32:6137',
    dark: '32:6445',
  ),
  (
    key: HolidayKey.labour,
    now: DateTime(2026, 5, 4, 18, 40),
    light: '32:6770',
    dark: '32:7108',
  ),
  (
    key: HolidayKey.victory,
    now: DateTime(2026, 5, 8, 18, 40),
    light: '32:7463',
    dark: '32:7858',
  ),
  (
    key: HolidayKey.children,
    now: DateTime(2026, 6, 1, 18, 40),
    light: '32:8270',
    dark: '32:8593',
  ),
  (
    key: HolidayKey.knowledge,
    now: DateTime(2026, 9, 1, 18, 40),
    light: '33:8273',
    dark: '33:8582',
  ),
  (
    key: HolidayKey.halloween,
    now: DateTime(2026, 10, 28, 18, 40),
    light: '33:8908',
    dark: '33:9336',
  ),
  (
    key: HolidayKey.birthday,
    now: DateTime(2026, 11, 11, 18, 40),
    light: '33:9781',
    dark: '33:10144',
  ),
];

Future<void> seedHolidayMonth(AppDatabase db, HolidayKey key) async {
  if (key == HolidayKey.birthday) {
    await DriftPrefsRepository(db).setString(PrefKeys.localUserId, anya.userId);
  }
  await seedMockupOctober(db);
}

HolidaySettings holidaySettingsFor(HolidayKey key) => key == HolidayKey.birthday
    ? HolidaySettings(birthday: anyaBirthday)
    : const HolidaySettings();

List<Override> holidayOverrides(
  AppDatabase db,
  HolidayKey key,
  DateTime Function() now,
) => [
  appDatabaseProvider.overrideWithValue(db),
  clockProvider.overrideWithValue(Clock(now: now)),
  if (key == HolidayKey.birthday) ...[
    sessionProvider.overrideWithBuild((ref, _) => const SessionActive(anya)),
    holidaySettingsProvider.overrideWithValue(holidaySettingsFor(key)),
  ],
];

Future<void> pumpHolidayMonth(
  WidgetTester tester,
  AppDatabase db, {
  required HolidayKey key,
  required DateTime now,
  Brightness brightness = Brightness.light,
  double width = 360,
  double scale = 1,
}) async {
  await loadTestFonts();
  tester.view
    ..devicePixelRatio = goldenPixelRatio
    ..physicalSize = Size(width, 800) * goldenPixelRatio
    ..viewPadding = const FakeViewPadding(top: 32)
    ..padding = const FakeViewPadding(top: 32);
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearAllTestValues);

  final router = buildRouter();
  addTearDown(router.dispose);
  final mood = moodOn(LocalDate.fromDateTime(now), holidaySettingsFor(key));
  final base = AppTheme.build(brightness, mood);

  await tester.pumpWidget(
    ProviderScope(
      overrides: holidayOverrides(db, key, () => now),
      child: RepaintBoundary(
        key: goldenKey,
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: base.copyWith(
            textTheme: base.textTheme.apply(
              fontFamilyFallback: const [testEmojiFamily],
            ),
          ),
          locale: const Locale('ru'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          routerConfig: router,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await settleAssets(tester);
}
