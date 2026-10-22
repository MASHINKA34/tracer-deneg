import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/core/router.dart';
import 'package:milionchik/features/search/search_screen.dart';
import 'package:milionchik/l10n/app_localizations.dart';
import 'package:milionchik/ui/theme/app_theme.dart';
import 'package:shared/shared.dart';

import '../../features/search/search_fixture.dart';
import '../../support/app_scope.dart';
import '../../support/golden.dart';
import '../../support/test_fonts.dart';

Future<void> _pump(
  WidgetTester tester, {
  required Brightness brightness,
  required double width,
  required double scale,
  required String query,
}) async {
  await loadTestFonts();
  final db = openTestDatabase();
  await tester.runAsync(() => seedSearchMockup(db));
  EditableText.debugDeterministicCursor = true;
  addTearDown(() => EditableText.debugDeterministicCursor = false);
  debugDisableShadows = false;
  tester.view
    ..devicePixelRatio = goldenPixelRatio
    ..physicalSize = Size(width, 800) * goldenPixelRatio
    ..viewPadding = const FakeViewPadding(top: 32)
    ..padding = const FakeViewPadding(top: 32);
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearAllTestValues);

  final router = buildRouter(initialLocation: AppRoutes.search);
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
  await settleSearch(tester);
  await tester.enterText(find.byType(EditableText), query);
  await tester.pump(searchDebounce);
  await settleSearch(tester);
  await settleAssets(tester);
}

void main() {
  for (final brightness in Brightness.values) {
    for (final width in const [360.0, 320.0]) {
      for (final scale in const [1.0, 2.0]) {
        final name =
            '${brightness.name}_${width.toInt()}'
            '${scale == 1 ? '' : '_x${scale.toInt()}'}';

        testWidgets('поиск «кофе» $name (Figma 46:5267)', (tester) async {
          await _pump(
            tester,
            brightness: brightness,
            width: width,
            scale: scale,
            query: 'кофе',
          );
          expect(tester.takeException(), isNull);

          await expectGolden(tester, 'search', 'results_$name');
        });

        testWidgets('поиск «самокат» — ничего не найдено $name '
            '(Figma 46:5355)', (tester) async {
          await _pump(
            tester,
            brightness: brightness,
            width: width,
            scale: scale,
            query: 'самокат',
          );
          expect(tester.takeException(), isNull);

          await expectGolden(tester, 'search', 'empty_$name');
        });
      }
    }
  }
}
