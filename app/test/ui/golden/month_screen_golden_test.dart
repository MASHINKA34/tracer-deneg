import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/core/router.dart';
import 'package:milionchik/l10n/app_localizations.dart';
import 'package:milionchik/ui/theme/app_theme.dart';
import 'package:shared/shared.dart';

import '../../features/month/month_fixture.dart';
import '../../support/app_scope.dart';
import '../../support/golden.dart';
import '../../support/test_fonts.dart';

void main() {
  for (final (screen, now, seed, figma) in [
    ('october', DateTime(2026, 10, 19, 18, 40), seedMockupOctober, '7:7'),
    ('january', DateTime(2026, 1, 31, 20), seedMockupJanuary, '16:3161'),
  ]) {
    for (final brightness in Brightness.values) {
      for (final width in const [360.0, 320.0]) {
        for (final scale in const [1.0, 2.0]) {
          final name =
              '${screen}_${brightness.name}_${width.toInt()}'
              '${scale == 1 ? '' : '_x${scale.toInt()}'}';
          testWidgets('главная $name (Figma $figma)', (tester) async {
            await loadTestFonts();
            final db = openTestDatabase();
            await tester.runAsync(() => seed(db));
            debugDisableShadows = false;
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
            final mood = moodOn(
              LocalDate.fromDateTime(now),
              const HolidaySettings(),
            );
            final base = AppTheme.build(brightness, mood);

            await tester.pumpWidget(
              withDatabase(
                db,
                RepaintBoundary(
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
                    localizationsDelegates:
                        AppLocalizations.localizationsDelegates,
                    routerConfig: router,
                  ),
                ),
                now: now,
              ),
            );
            await tester.pumpAndSettle();
            await settleAssets(tester);

            await expectGolden(tester, 'month_screen', name);
          });
        }
      }
    }
  }
}
