import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milionchik/features/search/search_categories_sheet.dart';
import 'package:milionchik/features/search/search_period_sheet.dart';
import 'package:milionchik/ui/components/chip.dart';

import 'search_fixture.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  for (final width in const [320.0, 360.0]) {
    testWidgets('$width dp, шрифт 2.0: чипы, шторка периода и шторка '
        'категорий без переполнений, «Готово» докручивается и нажимается', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await openSearch(tester, size: Size(width, 640));
      expect(tester.takeException(), isNull);

      final period = inSearch(find.widgetWithText(AppChip, 'За всё время'));
      expect(tester.getSize(period).height, greaterThanOrEqualTo(48));
      await tester.tap(period);
      await tester.pumpAndSettle();
      expect(find.byType(SearchPeriodSheet), findsOneWidget);
      expect(tester.takeException(), isNull);
      final custom = find.descendant(
        of: find.byType(SearchPeriodSheet),
        matching: find.text('Этот год'),
      );
      await tester.ensureVisible(custom);
      await tester.pumpAndSettle();
      await tester.tap(custom);
      await settleSearch(tester);
      expect(find.byType(SearchPeriodSheet), findsNothing);
      expect(
        tester
            .widget<AppChip>(inSearch(find.widgetWithText(AppChip, '2026 год')))
            .selected,
        isTrue,
      );

      final categories = inSearch(
        find.widgetWithText(AppChip, 'Все категории'),
      );
      await tester.ensureVisible(categories);
      await tester.pumpAndSettle();
      await tester.tap(categories);
      await tester.pumpAndSettle();
      expect(find.byType(SearchCategoriesSheet), findsOneWidget);
      expect(tester.takeException(), isNull);
      final done = find.text('Готово');
      expect(done, findsOneWidget);
      await tester.tap(done);
      await tester.pumpAndSettle();
      expect(find.byType(SearchCategoriesSheet), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
