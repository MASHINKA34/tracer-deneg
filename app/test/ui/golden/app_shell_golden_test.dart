import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/app.dart';
import 'package:milionchik/ui/components/bottom_nav.dart';
import 'package:shared/shared.dart';

import '../../support/golden.dart';
import '../../support/test_fonts.dart';

void main() {
  for (final (tab, label, figma) in const [
    ('month', null, '7:7'),
    ('stats', 'Статистика', '12:820'),
  ]) {
    for (final brightness in Brightness.values) {
      for (final width in const [360.0, 320.0]) {
        for (final scale in const [1.0, 2.0]) {
          final name =
              '${tab}_${brightness.name}_${width.toInt()}'
              '${scale == 1 ? '' : '_x${scale.toInt()}'}';
          testWidgets('shell $name (Figma $figma, меню 5:154)', (tester) async {
            await loadTestFonts();
            debugDisableShadows = false;
            WidgetsApp.debugAllowBannerOverride = false;
            addTearDown(() => WidgetsApp.debugAllowBannerOverride = true);
            tester.view
              ..devicePixelRatio = goldenPixelRatio
              ..physicalSize = Size(width, 800) * goldenPixelRatio
              ..viewPadding = const FakeViewPadding(top: 32)
              ..padding = const FakeViewPadding(top: 32);
            addTearDown(tester.view.reset);
            tester.platformDispatcher
              ..platformBrightnessTestValue = brightness
              ..textScaleFactorTestValue = scale;
            addTearDown(tester.platformDispatcher.clearAllTestValues);

            await tester.pumpWidget(
              MilionchikApp(today: LocalDate(2026, 10, 19)),
            );
            await settleAssets(tester);
            if (label != null) {
              await tester.tap(
                find.descendant(
                  of: find.byType(AppBottomNav),
                  matching: find.text(label),
                ),
              );
              await tester.pumpAndSettle();
              await settleAssets(tester);
            }

            try {
              await expectLater(
                find.byType(MilionchikApp),
                matchesGoldenFile(goldenName('shell', name)),
              );
            } finally {
              await tester.pumpWidget(const SizedBox.shrink());
              debugDisableShadows = true;
            }
          });
        }
      }
    }
  }
}
