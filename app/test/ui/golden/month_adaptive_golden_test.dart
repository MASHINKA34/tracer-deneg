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

final DateTime _now = DateTime(2026, 10, 19, 18, 40);

Future<void> _pumpMonth(
  WidgetTester tester, {
  required Size size,
  required Brightness brightness,
  double scale = 1,
}) async {
  await loadTestFonts();
  final db = openTestDatabase();
  await tester.runAsync(() => seedMockupOctober(db));
  debugDisableShadows = false;
  tester.view
    ..devicePixelRatio = goldenPixelRatio
    ..physicalSize = size * goldenPixelRatio
    ..viewPadding = const FakeViewPadding(top: 32, bottom: 24)
    ..padding = const FakeViewPadding(top: 32, bottom: 24);
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearAllTestValues);

  final router = buildRouter();
  addTearDown(router.dispose);
  final base = AppTheme.build(
    brightness,
    moodOn(LocalDate.fromDateTime(_now), const HolidaySettings()),
  );

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
      now: _now,
    ),
  );
  await tester.pumpAndSettle();
  await settleAssets(tester);
}

void main() {
  for (final size in const [
    Size(320, 800),
    Size(360, 800),
    Size(412, 915),
    Size(800, 1280),
    Size(1280, 800),
  ]) {
    for (final brightness in Brightness.values) {
      for (final scale in const [1.0, 2.0]) {
        final name =
            'october_${brightness.name}_'
            '${size.width.toInt()}x${size.height.toInt()}'
            '${scale == 1 ? '' : '_x${scale.toInt()}'}';
        testWidgets('главная $name (Figma 7:7, колонка ≤ 480 dp)', (
          tester,
        ) async {
          await _pumpMonth(
            tester,
            size: size,
            brightness: brightness,
            scale: scale,
          );

          await expectGolden(tester, 'month_adaptive', name);
        });
      }
    }
  }

  for (final brightness in Brightness.values) {
    final name = 'october_day_sheet_${brightness.name}_1280x800';
    testWidgets(
      'главная $name: шторка дня 17 октября в колонке (Figma 9:439)',
      (tester) async {
        await _pumpMonth(
          tester,
          size: const Size(1280, 800),
          brightness: brightness,
        );
        await tester.tap(find.bySemanticsLabel(RegExp('^17 октября')));
        await tester.pumpAndSettle();
        await settleAssets(tester);

        await expectGolden(tester, 'month_adaptive', name);
      },
    );
  }
}
