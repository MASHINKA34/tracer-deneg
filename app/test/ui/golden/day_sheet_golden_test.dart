import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/core/router.dart';
import 'package:milionchik/features/month/day_sheet.dart';
import 'package:milionchik/l10n/app_localizations.dart';
import 'package:milionchik/ui/components/sheet.dart';
import 'package:milionchik/ui/theme/app_theme.dart';
import 'package:shared/shared.dart';

import '../../features/month/month_fixture.dart';
import '../../support/app_scope.dart';
import '../../support/golden.dart';
import '../../support/test_fonts.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final width in const [360.0, 320.0]) {
      for (final scale in const [1.0, 2.0]) {
        final name =
            'sheet_${brightness.name}_${width.toInt()}'
            '${scale == 1 ? '' : '_x${scale.toInt()}'}';
        testWidgets('шторка дня 17 октября $name (Figma 9:531 в 9:439)', (
          tester,
        ) async {
          final db = openTestDatabase();
          await tester.runAsync(() => seedMockupOctober(db));
          await pumpGolden(
            tester,
            brightness: brightness,
            width: width,
            textScale: scale,
            padding: const EdgeInsets.only(top: 36),
            background: (_) => Colors.transparent,
            child: withDatabase(
              db,
              AppSheet(children: [DaySheet(day: LocalDate(2026, 10, 17))]),
            ),
          );
          await tester.pumpAndSettle();
          await settleAssets(tester);
          await expectGolden(tester, 'day_sheet', name);
        });
      }
    }
  }

  for (final brightness in Brightness.values) {
    final name = 'empty_${brightness.name}_360';
    testWidgets('шторка дня без трат 4 октября $name', (tester) async {
      final db = openTestDatabase();
      await tester.runAsync(() => seedMockupOctober(db));
      await pumpGolden(
        tester,
        brightness: brightness,
        padding: const EdgeInsets.only(top: 36),
        background: (_) => Colors.transparent,
        child: withDatabase(
          db,
          AppSheet(children: [DaySheet(day: LocalDate(2026, 10, 4))]),
        ),
      );
      await tester.pumpAndSettle();
      await settleAssets(tester);
      await expectGolden(tester, 'day_sheet', name);
    });
  }

  for (final brightness in Brightness.values) {
    final name = 'screen_${brightness.name}_360';
    testWidgets('главная с открытой шторкой дня $name (Figma 9:439)', (
      tester,
    ) async {
      await loadTestFonts();
      final db = openTestDatabase();
      await tester.runAsync(() => seedMockupOctober(db));
      debugDisableShadows = false;
      tester.view
        ..devicePixelRatio = goldenPixelRatio
        ..physicalSize = const Size(360, 800) * goldenPixelRatio
        ..viewPadding = const FakeViewPadding(top: 32)
        ..padding = const FakeViewPadding(top: 32);
      addTearDown(tester.view.reset);

      final router = buildRouter();
      addTearDown(router.dispose);
      final base = AppTheme.build(brightness, Mood.autumn);

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
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              routerConfig: router,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel(RegExp('^17 октября')));
      await tester.pumpAndSettle();
      await settleAssets(tester);

      await expectGolden(tester, 'day_sheet', name);
    });
  }
}
