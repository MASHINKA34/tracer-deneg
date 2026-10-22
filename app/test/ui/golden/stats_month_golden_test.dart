import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/core/router.dart';
import 'package:milionchik/data/db/app_database.dart';
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

Future<void> _pump(
  WidgetTester tester, {
  required Brightness brightness,
  required double width,
  required double scale,
  required Future<void> Function(AppDatabase db) seed,
}) async {
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

  final router = buildRouter(initialLocation: AppRoutes.stats);
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
}

Future<void> _scrollToEnd(WidgetTester tester) async {
  final scrollable = tester.state<ScrollableState>(
    find.byType(Scrollable).first,
  );
  scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
  await tester.pumpAndSettle();
  await settleAssets(tester);
}

void main() {
  for (final brightness in Brightness.values) {
    for (final width in const [360.0, 320.0]) {
      for (final scale in const [1.0, 2.0]) {
        final name =
            '${brightness.name}_${width.toInt()}'
            '${scale == 1 ? '' : '_x${scale.toInt()}'}';
        final figma = brightness == Brightness.light ? '12:820' : '15:1468';

        testWidgets('статистика октября $name (Figma $figma)', (tester) async {
          await _pump(
            tester,
            brightness: brightness,
            width: width,
            scale: scale,
            seed: seedMockupOctober,
          );
          expect(tester.takeException(), isNull);

          await expectGolden(tester, 'stats_month', 'october_$name');
        });

        testWidgets('статистика октября $name прокручена до конца списка', (
          tester,
        ) async {
          await _pump(
            tester,
            brightness: brightness,
            width: width,
            scale: scale,
            seed: seedMockupOctober,
          );
          await _scrollToEnd(tester);
          expect(tester.takeException(), isNull);

          await expectGolden(tester, 'stats_month', 'october_${name}_end');
        });

        testWidgets('пустой месяц $name (в духе Figma 47:5951)', (
          tester,
        ) async {
          await _pump(
            tester,
            brightness: brightness,
            width: width,
            scale: scale,
            seed: _emptyBudget,
          );
          expect(tester.takeException(), isNull);

          await expectGolden(tester, 'stats_month', 'empty_$name');
        });
      }
    }
  }
}
