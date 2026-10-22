import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milionchik/core/router.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/l10n/app_localizations.dart';
import 'package:milionchik/ui/components/button.dart';
import 'package:milionchik/ui/theme/app_theme.dart';
import 'package:shared/shared.dart';

import '../../features/recurring/recurring_fixture.dart';
import '../../support/app_scope.dart';
import '../../support/golden.dart';
import '../../support/test_fonts.dart';

Future<void> _pump(
  WidgetTester tester, {
  required Brightness brightness,
  required double width,
  required double scale,
  required Future<String> Function(AppDatabase db) location,
}) async {
  await loadTestFonts();
  final db = openTestDatabase();
  final initial = (await tester.runAsync(() => location(db)))!;
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

  final router = buildRouter(initialLocation: initial);
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

Future<void> _openDaySheet(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel(RegExp('^День списания, ')));
  await tester.pumpAndSettle();
  await settleAssets(tester);
}

Future<void> _openDeleteDialog(WidgetTester tester) async {
  final delete = find.widgetWithText(AppButton, 'Удалить регулярную трату');
  await tester.ensureVisible(delete);
  await tester.pumpAndSettle();
  await tester.tap(delete);
  await tester.pumpAndSettle();
  final scrollable = tester.state<ScrollableState>(
    find.byType(Scrollable).first,
  );
  scrollable.position.jumpTo(0);
  await tester.pumpAndSettle();
  await settleAssets(tester);
}

Future<String> _gym(AppDatabase db) async {
  final budget = await seedRecurringMockup(db);
  return AppRoutes.recurringRuleOf(budget.rules['Спортзал «Территория»']!.id);
}

Future<String> _new(AppDatabase db) async {
  await seedRecurringBudget(db);
  return AppRoutes.newRecurring;
}

String _name(Brightness brightness, double width, double scale) =>
    '${brightness.name}_${width.toInt()}'
    '${scale == 1 ? '' : '_x${scale.toInt()}'}';

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  for (final brightness in Brightness.values) {
    for (final width in const [360.0, 320.0]) {
      for (final scale in const [1.0, 2.0]) {
        final name = _name(brightness, width, scale);

        testWidgets('«Регулярная трата» спортзал $name (Figma 44:5102)', (
          tester,
        ) async {
          await _pump(
            tester,
            brightness: brightness,
            width: width,
            scale: scale,
            location: _gym,
          );
          expect(tester.takeException(), isNull);

          await expectGolden(tester, 'recurring_editor', 'editor_$name');
        });

        testWidgets('«Новая регулярная трата» пустая $name', (tester) async {
          await _pump(
            tester,
            brightness: brightness,
            width: width,
            scale: scale,
            location: _new,
          );
          expect(tester.takeException(), isNull);

          await expectGolden(tester, 'recurring_editor', 'new_$name');
        });

        testWidgets('шторка «День списания» спортзала $name', (tester) async {
          await _pump(
            tester,
            brightness: brightness,
            width: width,
            scale: scale,
            location: _gym,
          );
          await _openDaySheet(tester);
          expect(tester.takeException(), isNull);

          await expectGolden(tester, 'recurring_editor', 'day_sheet_$name');
        });

        testWidgets('диалог «Удалить регулярную трату?» спортзала $name', (
          tester,
        ) async {
          await _pump(
            tester,
            brightness: brightness,
            width: width,
            scale: scale,
            location: _gym,
          );
          await _openDeleteDialog(tester);
          expect(tester.takeException(), isNull);

          await expectGolden(tester, 'recurring_editor', 'delete_$name');
        });

        if (scale != 1) {
          testWidgets('«Регулярная трата» спортзал $name прокручена до конца', (
            tester,
          ) async {
            await _pump(
              tester,
              brightness: brightness,
              width: width,
              scale: scale,
              location: _gym,
            );
            await _scrollToEnd(tester);
            expect(tester.takeException(), isNull);

            await expectGolden(
              tester,
              'recurring_editor',
              'editor_${name}_end',
            );
          });
        }
      }
    }
  }
}
