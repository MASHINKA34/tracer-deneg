import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/core/router.dart';
import 'package:milionchik/data/queries/month_queries.dart';
import 'package:milionchik/l10n/app_localizations.dart';
import 'package:milionchik/ui/theme/app_theme.dart';
import 'package:shared/shared.dart';

import '../../features/month/month_fixture.dart';
import '../../support/app_scope.dart';
import '../../support/golden.dart';
import '../../support/test_fonts.dart';

Future<void> _pumpExpense(
  WidgetTester tester, {
  required Brightness brightness,
  required double width,
  required double scale,
  bool missing = false,
}) async {
  await loadTestFonts();
  final db = openTestDatabase();
  final id = (await tester.runAsync(() async {
    final budgetId = await seedMockupOctober(db);
    final today = await DriftMonthQueries(
      db,
    ).watchDayExpenses(budgetId, LocalDate(2026, 10, 19)).first;
    return today.singleWhere((e) => e.comment == 'Пятёрочка').id;
  }))!;
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

  final router = buildRouter(
    initialLocation: AppRoutes.expenseOf(missing ? 'no-such-expense' : id),
  );
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
}

String _name(Brightness brightness, double width, double scale) =>
    '${brightness.name}_${width.toInt()}'
    '${scale == 1 ? '' : '_x${scale.toInt()}'}';

void main() {
  for (final brightness in Brightness.values) {
    for (final width in const [360.0, 320.0]) {
      for (final scale in const [1.0, 2.0]) {
        final name = _name(brightness, width, scale);
        testWidgets('«Трата» 640 ₽ · Продукты · сегодня · Пятёрочка $name '
            '(Figma 43:4368)', (tester) async {
          await _pumpExpense(
            tester,
            brightness: brightness,
            width: width,
            scale: scale,
          );

          await expectGolden(tester, 'edit_expense', name);
        });

        if (scale != 1) {
          testWidgets('«Трата» $name прокручена до «Удалить трату»', (
            tester,
          ) async {
            await _pumpExpense(
              tester,
              brightness: brightness,
              width: width,
              scale: scale,
            );
            await _scrollToEnd(tester);
            await settleAssets(tester);

            await expectGolden(tester, 'edit_expense', '${name}_end');
          });
        }
      }
    }

    for (final (width, scale) in const [(360.0, 1.0), (320.0, 2.0)]) {
      final name = _name(brightness, width, scale);
      testWidgets('шторка суммы с 640 $name', (tester) async {
        await _pumpExpense(
          tester,
          brightness: brightness,
          width: width,
          scale: scale,
        );
        await tester.tap(find.byKey(const ValueKey('edit-expense-amount')));
        await tester.pumpAndSettle();
        await settleAssets(tester);

        await expectGolden(tester, 'edit_expense', 'amount_sheet_$name');
      });
    }

    testWidgets('сумма 640 → 1 250 в шторке: «Сохранить» активна '
        '${brightness.name}_360', (tester) async {
      await _pumpExpense(
        tester,
        brightness: brightness,
        width: 360,
        scale: 1,
      );
      await tester.tap(find.byKey(const ValueKey('edit-expense-amount')));
      await tester.pumpAndSettle();
      for (final key in ['Стереть', 'Стереть', 'Стереть', '1', '2', '5', '0']) {
        await tester.tap(find.bySemanticsLabel(key));
        await tester.pump();
      }
      await tester.tap(find.text('Готово'));
      await tester.pumpAndSettle();
      await settleAssets(tester);

      await expectGolden(
        tester,
        'edit_expense',
        'changed_${brightness.name}_360',
      );
    });

    testWidgets('трата не найдена ${brightness.name}_360', (tester) async {
      await _pumpExpense(
        tester,
        brightness: brightness,
        width: 360,
        scale: 1,
        missing: true,
      );

      await expectGolden(tester, 'edit_expense', 'missing_${brightness.name}');
    });
  }
}
