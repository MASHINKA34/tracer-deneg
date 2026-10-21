import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/core/router.dart';
import 'package:milionchik/features/expense/expense_comment_sheet.dart';
import 'package:milionchik/l10n/app_localizations.dart';
import 'package:milionchik/ui/components/chip.dart';
import 'package:milionchik/ui/components/sheet.dart';
import 'package:milionchik/ui/theme/app_theme.dart';
import 'package:shared/shared.dart';

import '../../features/expense/expense_comment_fixture.dart';
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
        testWidgets('шторка комментария «Кофе с собой» с четырьмя недавними '
            '$name (Figma 43:5012 в 43:4962)', (tester) async {
          final db = openTestDatabase();
          final budgetId = (await tester.runAsync(
            () => seedComments(db, mockupRecentComments),
          ))!;
          await pumpGolden(
            tester,
            brightness: brightness,
            width: width,
            textScale: scale,
            padding: const EdgeInsets.only(top: 36),
            background: (_) => Colors.transparent,
            child: withDatabase(
              db,
              AppSheet(
                children: [
                  ExpenseCommentSheet(
                    initial: 'Кофе с собой',
                    budgetId: budgetId,
                  ),
                ],
              ),
            ),
          );
          await tester.pumpAndSettle();
          await settleAssets(tester);
          await expectGolden(tester, 'expense_comment_sheet', name);
        });
      }
    }
  }

  for (final brightness in Brightness.values) {
    final name = 'screen_${brightness.name}_360';
    testWidgets('«Новая трата» 1 250 с открытой шторкой комментария и '
        'недавними из демо-данных $name (Figma 43:4962)', (tester) async {
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
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      EditableText.debugDeterministicCursor = true;
      addTearDown(() => EditableText.debugDeterministicCursor = false);

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
      for (final key in '1250'.split('')) {
        await tester.tap(find.bySemanticsLabel(key));
        await tester.pump();
      }
      await tester.tap(find.widgetWithText(AppChip, 'Комментарий'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(ExpenseCommentSheet),
          matching: find.byType(EditableText),
        ),
        'Кофе с собой',
      );
      await tester.pumpAndSettle();
      await settleAssets(tester);

      await expectGolden(tester, 'expense_comment_sheet', name);
    });
  }
}
