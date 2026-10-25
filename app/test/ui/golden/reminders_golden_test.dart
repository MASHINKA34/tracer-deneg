import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/core/router.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/session/session_providers.dart';
import 'package:milionchik/data/session/session_state.dart';
import 'package:milionchik/features/reminders/reminder_notifications.dart';
import 'package:milionchik/features/reminders/reminder_settings.dart';
import 'package:milionchik/features/reminders/reminders_screen.dart';
import 'package:milionchik/l10n/app_localizations.dart';
import 'package:milionchik/ui/theme/app_theme.dart';
import 'package:shared/shared.dart';

import '../../features/profile/profile_fixture.dart';
import '../../features/reminders/reminder_fakes.dart';
import '../../support/app_scope.dart';
import '../../support/golden.dart';
import '../../support/test_fonts.dart';

const ReminderSettings mockupReminders = ReminderSettings(enabled: true);

Future<void> pumpReminders(
  WidgetTester tester, {
  required Brightness brightness,
  required double width,
  required double scale,
  ReminderSettings settings = mockupReminders,
  double? height,
}) async {
  await loadTestFonts();
  final db = openTestDatabase();
  debugDisableShadows = false;
  tester.view
    ..devicePixelRatio = goldenPixelRatio
    ..physicalSize = Size(width, height ?? 2000) * goldenPixelRatio
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

  final router = buildRouter(initialLocation: AppRoutes.reminders);
  addTearDown(router.dispose);
  final base = AppTheme.build(brightness, Mood.autumn);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(Clock(now: () => testNow)),
        sessionProvider.overrideWithBuild(
          (ref, _) => const SessionActive(profileUser),
        ),
        reminderNotificationsProvider.overrideWithValue(
          FakeReminderNotifications(),
        ),
        reminderSettingsProvider.overrideWithBuild((ref, _) => settings),
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
  if (height != null) return;
  final content = tester.getSize(
    find
        .descendant(
          of: find.byType(SingleChildScrollView),
          matching: find.byType(Column),
        )
        .first,
  );
  final fitted = (32 + 56 + 4 + content.height + 16).ceilToDouble();
  tester.view.physicalSize = Size(width, fitted) * goldenPixelRatio;
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

        testWidgets('«Напоминания» $name (Figma 47:5492)', (tester) async {
          await pumpReminders(
            tester,
            brightness: brightness,
            width: width,
            scale: scale,
          );
          expect(find.byType(RemindersScreen), findsOneWidget);
          expect(find.text('21:00'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await expectGolden(tester, 'reminders', 'screen_$name');
        });
      }
    }
  }

  testWidgets('«Напоминания» выключены, 07:30 - light_360', (tester) async {
    await pumpReminders(
      tester,
      brightness: Brightness.light,
      width: 360,
      scale: 1,
      settings: const ReminderSettings(time: ReminderTime(7, 30)),
    );
    expect(find.text('07:30'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectGolden(tester, 'reminders', 'screen_off_light_360');
  });
}
