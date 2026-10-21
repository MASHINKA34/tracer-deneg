import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/core/router.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/features/month/today_block.dart';
import 'package:milionchik/l10n/app_localizations.dart';
import 'package:milionchik/ui/theme/app_theme.dart';
import 'package:shared/shared.dart';

import '../../features/month/month_fixture.dart';
import '../../support/app_scope.dart';
import '../../support/golden.dart';
import '../../support/test_fonts.dart';

Future<void> _emptyBudget(AppDatabase db) async {
  await testBudgets(db).createLocalPersonal();
}

void main() {
  for (final (kind, seed, figma) in [
    ('block', seedMockupOctober, '7:279 в 7:7'),
    ('empty', _emptyBudget, '47:5608 в 47:5524'),
  ]) {
    for (final brightness in Brightness.values) {
      for (final width in const [360.0, 320.0]) {
        for (final scale in const [1.0, 2.0]) {
          final name =
              '${kind}_${brightness.name}_${width.toInt()}'
              '${scale == 1 ? '' : '_x${scale.toInt()}'}';
          testWidgets('блок «Сегодня» $name (Figma $figma)', (tester) async {
            final db = openTestDatabase();
            await tester.runAsync(() => seed(db));
            await pumpGolden(
              tester,
              brightness: brightness,
              width: width,
              textScale: scale,
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
              child: withDatabase(
                db,
                TodayBlock(today: LocalDate(2026, 10, 19)),
              ),
            );
            await tester.pumpAndSettle();
            await settleAssets(tester);
            await expectGolden(tester, 'today_block', name);
          });
        }
      }
    }
  }

  for (final brightness in Brightness.values) {
    final name = 'none_${brightness.name}_360';
    testWidgets('блок «Сегодня» без трат за 4 октября $name', (tester) async {
      final db = openTestDatabase();
      await tester.runAsync(() => seedMockupOctober(db));
      await pumpGolden(
        tester,
        brightness: brightness,
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
        child: withDatabase(db, TodayBlock(today: LocalDate(2026, 10, 4))),
      );
      await tester.pumpAndSettle();
      await settleAssets(tester);
      await expectGolden(tester, 'today_block', name);
    });
  }

  for (final brightness in Brightness.values) {
    final name = 'screen_empty_${brightness.name}_360';
    testWidgets('пустая главная $name (Figma 47:5524)', (tester) async {
      await loadTestFonts();
      final db = openTestDatabase();
      await tester.runAsync(() => _emptyBudget(db));
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
      await settleAssets(tester);

      await expectGolden(tester, 'today_block', name);
    });
  }
}
