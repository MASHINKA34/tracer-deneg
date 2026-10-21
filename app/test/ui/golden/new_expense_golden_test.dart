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

Future<void> _pumpNewExpense(
  WidgetTester tester, {
  required Brightness brightness,
  required double width,
  required double scale,
}) async {
  await loadTestFonts();
  final db = openTestDatabase();
  await tester.runAsync(() => seedMockupOctober(db));
  debugDisableShadows = false;
  tester.view
    ..devicePixelRatio = goldenPixelRatio
    ..physicalSize = Size(width, 800) * goldenPixelRatio
    ..viewPadding = const FakeViewPadding(top: 32)
    ..padding = const FakeViewPadding(top: 32);
  addTearDown(tester.view.reset);
  tester.platformDispatcher
    ..textScaleFactorTestValue = scale
    ..accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
      disableAnimations: true,
    );
  addTearDown(tester.platformDispatcher.clearAllTestValues);

  final router = buildRouter(initialLocation: AppRoutes.newExpense);
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
}

Future<void> _type(WidgetTester tester, String keys) async {
  for (final key in keys.split('')) {
    final finder = find.bySemanticsLabel(key);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<void> _scrollTo(WidgetTester tester, {required bool end}) async {
  final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
  final position = scrollable.position;
  position.jumpTo(end ? position.maxScrollExtent : 0);
  await tester.pumpAndSettle();
}

void main() {
  for (final brightness in Brightness.values) {
    for (final width in const [360.0, 320.0]) {
      for (final scale in const [1.0, 2.0]) {
        final name =
            '${brightness.name}_${width.toInt()}'
            '${scale == 1 ? '' : '_x${scale.toInt()}'}';
        final figma = brightness == Brightness.light ? '10:763' : '15:1419';
        testWidgets('«Новая трата» с суммой 1 250 $name (Figma $figma)', (
          tester,
        ) async {
          await _pumpNewExpense(
            tester,
            brightness: brightness,
            width: width,
            scale: scale,
          );
          await _type(tester, '1250');
          await _scrollTo(tester, end: false);
          await settleAssets(tester);

          await expectGolden(tester, 'new_expense', name);
        });

        if (scale != 1) {
          testWidgets('«Новая трата» $name прокручена до конца клавиатуры', (
            tester,
          ) async {
            await _pumpNewExpense(
              tester,
              brightness: brightness,
              width: width,
              scale: scale,
            );
            await _type(tester, '1250');
            await _scrollTo(tester, end: true);
            await settleAssets(tester);

            await expectGolden(tester, 'new_expense', '${name}_end');
          });
        }
      }
    }
  }
}
