import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/core/router.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/session/session_providers.dart';
import 'package:milionchik/data/session/session_state.dart';
import 'package:milionchik/features/profile/profile_screen.dart';
import 'package:milionchik/features/profile/theme_screen.dart';
import 'package:milionchik/l10n/app_localizations.dart';
import 'package:milionchik/ui/theme/app_theme.dart';
import 'package:shared/shared.dart';

import '../../features/profile/profile_fixture.dart';
import '../../support/app_scope.dart';
import '../../support/golden.dart';
import '../../support/test_fonts.dart';

const double _fullHeight = 1232;

Future<void> _pump(
  WidgetTester tester, {
  required Brightness brightness,
  required double width,
  required double height,
  required double scale,
  required String location,
}) async {
  await loadTestFonts();
  final db = openTestDatabase();
  await tester.runAsync(() => ProfileFixture.mockup(db));
  debugDisableShadows = false;
  tester.view
    ..devicePixelRatio = goldenPixelRatio
    ..physicalSize = Size(width, height) * goldenPixelRatio
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

  final router = buildRouter(initialLocation: location);
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
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }
  await settleAssets(tester);
}

Future<bool> _scrollToEnd(WidgetTester tester) async {
  final scrollable = tester.state<ScrollableState>(
    find.byType(Scrollable).first,
  );
  final end = scrollable.position.maxScrollExtent;
  if (end <= 0) return false;
  scrollable.position.jumpTo(end);
  await tester.pumpAndSettle();
  await settleAssets(tester);
  return true;
}

String _name(Brightness brightness, double width, double scale) =>
    '${brightness.name}_${width.toInt()}'
    '${scale == 1 ? '' : '_x${scale.toInt()}'}';

void main() {
  for (final brightness in Brightness.values) {
    for (final width in const [360.0, 320.0]) {
      for (final scale in const [1.0, 2.0]) {
        final name = _name(brightness, width, scale);

        testWidgets('«Профиль» полная длина $name (Figma 47:13952)', (
          tester,
        ) async {
          await _pump(
            tester,
            brightness: brightness,
            width: width,
            height: _fullHeight,
            scale: scale,
            location: AppRoutes.profile,
          );
          expect(find.byType(ProfileScreen), findsOneWidget);
          expect(tester.takeException(), isNull);
          await expectGolden(tester, 'profile', 'profile_$name');
        });

        testWidgets('«Профиль» конец списка $name (Figma 47:13952)', (
          tester,
        ) async {
          await _pump(
            tester,
            brightness: brightness,
            width: width,
            height: _fullHeight,
            scale: scale,
            location: AppRoutes.profile,
          );
          if (!await _scrollToEnd(tester)) {
            await tester.pumpWidget(const SizedBox.shrink());
            debugDisableShadows = true;
            return;
          }
          expect(tester.takeException(), isNull);
          await expectGolden(tester, 'profile', 'profile_${name}_end');
        });

        testWidgets('«Тема» как в системе $name (Figma 47:5458)', (
          tester,
        ) async {
          await _pump(
            tester,
            brightness: brightness,
            width: width,
            height: 800,
            scale: scale,
            location: AppRoutes.theme,
          );
          expect(find.byType(ThemeScreen), findsOneWidget);
          expect(tester.takeException(), isNull);
          await expectGolden(tester, 'profile', 'theme_$name');
        });
      }
    }
  }
}
