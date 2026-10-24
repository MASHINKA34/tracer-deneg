import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/core/router.dart';
import 'package:milionchik/features/budgets/new_budget_screen.dart';
import 'package:milionchik/l10n/app_localizations.dart';
import 'package:milionchik/ui/components/button.dart';
import 'package:milionchik/ui/theme/app_theme.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';
import '../../support/golden.dart';
import '../../support/test_fonts.dart';

Future<void> _pump(
  WidgetTester tester, {
  required Brightness brightness,
  required double width,
  required double scale,
}) async {
  await loadTestFonts();
  final db = openTestDatabase();
  debugDisableShadows = false;
  EditableText.debugDeterministicCursor = true;
  addTearDown(() => EditableText.debugDeterministicCursor = false);
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

  final router = buildRouter(initialLocation: AppRoutes.newBudget);
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
  expect(find.byType(NewBudgetScreen), findsOneWidget);
}

Future<void> _typeName(WidgetTester tester, String name) async {
  await tester.tap(find.byType(TextField));
  await tester.pump();
  await tester.enterText(find.byType(TextField), name);
  await tester.pumpAndSettle();
}

Future<void> _scrollToEnd(WidgetTester tester) async {
  final scrollable = tester.state<ScrollableState>(
    find.byType(Scrollable).first,
  );
  scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
  await tester.pumpAndSettle();
  await settleAssets(tester);
}

String _name(Brightness brightness, double width, double scale) =>
    '${brightness.name}_${width.toInt()}'
    '${scale == 1 ? '' : '_x${scale.toInt()}'}';

void main() {
  for (final brightness in Brightness.values) {
    for (final width in const [360.0, 320.0]) {
      for (final scale in const [1.0, 2.0]) {
        final name = _name(brightness, width, scale);
        testWidgets('«Новый общий бюджет» Квартира, поле в фокусе $name '
            '(Figma 45:5035)', (tester) async {
          await _pump(
            tester,
            brightness: brightness,
            width: width,
            scale: scale,
          );
          await _typeName(tester, 'Квартира');

          expect(tester.takeException(), isNull);
          await expectGolden(tester, 'new_budget', 'screen_$name');
        });

        if (scale != 1) {
          testWidgets('«Новый общий бюджет» $name, прокручен до кнопки', (
            tester,
          ) async {
            await _pump(
              tester,
              brightness: brightness,
              width: width,
              scale: scale,
            );
            await _typeName(tester, 'Квартира');
            FocusManager.instance.primaryFocus?.unfocus();
            await tester.pumpAndSettle();
            await _scrollToEnd(tester);

            expect(tester.takeException(), isNull);
            await expectGolden(tester, 'new_budget', 'screen_${name}_end');
          });
        }
      }
    }

    final name = brightness.name;
    testWidgets('«Новый общий бюджет» пустое название после «Создать бюджет» '
        '$name', (tester) async {
      await _pump(tester, brightness: brightness, width: 360, scale: 1);
      await tester.tap(find.widgetWithText(AppButton, 'Создать бюджет'));
      await tester.pumpAndSettle();

      expect(find.text('Введи название бюджета'), findsOneWidget);
      await expectGolden(tester, 'new_budget', 'empty_error_$name');
    });
  }
}
