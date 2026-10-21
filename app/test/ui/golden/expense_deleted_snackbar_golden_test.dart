import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/core/router.dart';
import 'package:milionchik/data/queries/month_queries.dart';
import 'package:milionchik/features/expense/expense_delete_controller.dart';
import 'package:milionchik/features/expense/expense_snackbar_layer.dart';
import 'package:milionchik/features/month/today_block.dart';
import 'package:milionchik/l10n/app_localizations.dart';
import 'package:milionchik/ui/components/snackbar.dart';
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
            '${brightness.name}_${width.toInt()}'
            '${scale == 1 ? '' : '_x${scale.toInt()}'}';
        testWidgets('главная · трата удалена $name (Figma 43:4434)', (
          tester,
        ) async {
          await loadTestFonts();
          final db = openTestDatabase();
          final pyaterochka = (await tester.runAsync(() async {
            final budgetId = await seedMockupOctober(db);
            final day = await DriftMonthQueries(db)
                .watchDayExpenses(budgetId, LocalDate(2026, 10, 19))
                .first;
            return day.singleWhere((e) => e.comment == 'Пятёрочка');
          }))!;
          debugDisableShadows = false;
          tester.view
            ..devicePixelRatio = goldenPixelRatio
            ..physicalSize = Size(width, 800) * goldenPixelRatio
            ..viewPadding = const FakeViewPadding(top: 32)
            ..padding = const FakeViewPadding(top: 32);
          addTearDown(tester.view.reset);
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearAllTestValues);

          final router = buildRouter();
          addTearDown(router.dispose);
          final base = AppTheme.build(
            brightness,
            moodOn(LocalDate(2026, 10, 19), const HolidaySettings()),
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
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  routerConfig: router,
                  builder: (context, child) => ExpenseSnackbarLayer(
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final container = ProviderScope.containerOf(
            tester.element(find.byType(TodayBlock)),
          );
          var deleted = false;
          unawaited(
            container
                .read(expenseDeleteProvider.notifier)
                .delete(pyaterochka, from: 'golden')
                .then((ok) => deleted = ok),
          );
          for (var i = 0; i < 50 && !deleted; i++) {
            await tester.pump(const Duration(milliseconds: 20));
          }
          expect(deleted, isTrue);
          await tester.pumpAndSettle();
          await settleAssets(tester);
          expect(find.byType(AppSnackbar), findsOneWidget);

          await expectGolden(tester, 'expense_deleted', name);
        });
      }
    }
  }
}
