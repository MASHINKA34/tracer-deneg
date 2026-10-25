import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/core/router.dart';
import 'package:milionchik/data/holiday_settings.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/session/session_providers.dart';
import 'package:milionchik/data/session/session_state.dart';
import 'package:milionchik/features/holidays/birthday_sheet.dart';
import 'package:milionchik/features/holidays/holiday_settings_screen.dart';
import 'package:milionchik/l10n/app_localizations.dart';
import 'package:milionchik/ui/theme/app_theme.dart';
import 'package:shared/shared.dart';

import '../../features/profile/profile_fixture.dart';
import '../../support/app_scope.dart';
import '../../support/golden.dart';
import '../../support/test_fonts.dart';

final CachedHolidaySettings mockupHolidaySettings = CachedHolidaySettings(
  userId: profileUserId,
  settings: HolidaySettings(
    disabled: const {HolidayKey.knowledge},
    birthday: MonthDay(11, 14),
  ),
);

Future<void> pumpHolidaySettings(
  WidgetTester tester, {
  required Brightness brightness,
  required double width,
  required double scale,
  Mood mood = Mood.halloween,
  CachedHolidaySettings? settings,
}) async {
  await loadTestFonts();
  final db = openTestDatabase();
  debugDisableShadows = false;
  tester.view
    ..devicePixelRatio = goldenPixelRatio
    ..physicalSize = Size(width, 4000) * goldenPixelRatio
    ..viewPadding = const FakeViewPadding(top: 32)
    ..padding = const FakeViewPadding(top: 32);
  addTearDown(tester.view.reset);
  tester.platformDispatcher
    ..textScaleFactorTestValue = scale
    ..platformBrightnessTestValue = brightness
    ..accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
      disableAnimations: true,
    );
  addTearDown(tester.platformDispatcher.clearAllTestValues);

  final router = buildRouter(initialLocation: AppRoutes.holidays);
  addTearDown(router.dispose);
  final base = AppTheme.build(brightness, mood);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(Clock(now: () => testNow)),
        sessionProvider.overrideWithBuild(
          (ref, _) => const SessionActive(profileUser),
        ),
        startupHolidaySettingsProvider.overrideWithValue(
          settings ?? mockupHolidaySettings,
        ),
      ],
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
  final content = tester.getSize(
    find
        .descendant(
          of: find.byType(SingleChildScrollView),
          matching: find.byType(Column),
        )
        .first,
  );
  final height = (32 + 56 + 4 + content.height + 24).ceilToDouble();
  tester.view.physicalSize = Size(width, height) * goldenPixelRatio;
  await tester.pumpAndSettle();
  await settleAssets(tester);
}

String _name(Brightness brightness, double width, double scale) =>
    '${brightness.name}_${width.toInt()}'
    '${scale == 1 ? '' : '_x${scale.toInt()}'}';

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  for (final brightness in Brightness.values) {
    for (final width in const [360.0, 320.0]) {
      for (final scale in const [1.0, 2.0]) {
        final name = _name(brightness, width, scale);

        testWidgets('«Настройки · Праздники» $name (Figma 35:11485)', (
          tester,
        ) async {
          await pumpHolidaySettings(
            tester,
            brightness: brightness,
            width: width,
            scale: scale,
          );
          expect(find.byType(HolidaySettingsScreen), findsOneWidget);
          expect(find.text('14 ноября'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await expectGolden(tester, 'holiday_settings', 'screen_$name');
        });

        testWidgets('шторка «Мой день рождения» $name', (tester) async {
          await pumpHolidaySettings(
            tester,
            brightness: brightness,
            width: width,
            scale: scale,
          );
          tester.view.physicalSize =
              Size(width, scale == 1 ? 800 : 1400) * goldenPixelRatio;
          await tester.pumpAndSettle();
          await tester.tap(find.text('Мой день рождения'));
          await tester.pumpAndSettle();
          await settleAssets(tester);
          expect(find.byType(BirthdaySheet), findsOneWidget);
          expect(tester.takeException(), isNull);
          await expectGolden(tester, 'holiday_settings', 'birthday_sheet_$name');
        });
      }
    }
  }
}
