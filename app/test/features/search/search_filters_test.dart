import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/router.dart';
import 'package:milionchik/features/search/search_categories_sheet.dart';
import 'package:milionchik/features/search/search_period_sheet.dart';
import 'package:milionchik/ui/components/chip.dart';
import 'package:milionchik/ui/theme/app_theme.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';
import 'search_fixture.dart';

AppChip _chip(WidgetTester tester, String label) =>
    tester.widget<AppChip>(inSearch(find.widgetWithText(AppChip, label)));

Future<void> _tapChip(WidgetTester tester, String label) async {
  await tester.tap(inSearch(find.widgetWithText(AppChip, label)));
  await tester.pumpAndSettle();
}

Future<void> _pickPeriod(WidgetTester tester, String option) async {
  await tester.tap(
    find.descendant(
      of: find.byType(SearchPeriodSheet),
      matching: find.text(option),
    ),
  );
  await settleSearch(tester);
}

Future<void> _toggleCategory(WidgetTester tester, String name) async {
  await tester.tap(
    find.descendant(
      of: find.byType(SearchCategoriesSheet),
      matching: find.text(name),
    ),
  );
  await settleSearch(tester);
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('период: этот месяц, этот год и снова всё время', (tester) async {
    await openSearch(tester);
    expect(shownAmounts(tester), hasLength(11));
    expect(_chip(tester, 'За всё время').selected, isFalse);

    await _tapChip(tester, 'За всё время');
    expect(find.byType(SearchPeriodSheet), findsOneWidget);
    await _pickPeriod(tester, 'Этот месяц');

    expect(find.byType(SearchPeriodSheet), findsNothing);
    expect(_chip(tester, 'Октябрь 2026').selected, isTrue);
    expect(shownAmounts(tester), hasLength(9));
    expect(shownAmounts(tester), isNot(contains('300 ₽')));
    expect(shownAmounts(tester), isNot(contains('1 500 ₽')));

    await _tapChip(tester, 'Октябрь 2026');
    await _pickPeriod(tester, 'Этот год');
    expect(_chip(tester, '2026 год').selected, isTrue);
    expect(shownAmounts(tester), hasLength(10));
    expect(shownAmounts(tester), contains('300 ₽'));

    await _tapChip(tester, '2026 год');
    await _pickPeriod(tester, 'За всё время');
    expect(_chip(tester, 'За всё время').selected, isFalse);
    expect(shownAmounts(tester), hasLength(11));
  });

  testWidgets('свои даты: системный выбор диапазона в цветах приложения, '
      '05.10–15.10 оставляет 5 трат', (tester) async {
    await openSearch(tester);

    await _tapChip(tester, 'За всё время');
    await _pickPeriod(tester, 'Свои даты');
    final dialog = find.byType(DateRangePickerDialog);
    expect(dialog, findsOneWidget);
    final context = tester.element(dialog);
    final picker = Theme.of(context).datePickerTheme;
    expect(picker.rangeSelectionBackgroundColor, context.mood.soft);
    expect(
      picker.dayBackgroundColor?.resolve({WidgetState.selected}),
      context.mood.accent,
    );
    expect(picker.rangePickerBackgroundColor, context.colors.bgApp);

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    final fields = find.descendant(
      of: find.byType(DateRangePickerDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), '05.10.2026');
    await tester.enterText(fields.at(1), '15.10.2026');
    await tester.tap(find.text('ОК'));
    await settleSearch(tester);

    expect(find.byType(DateRangePickerDialog), findsNothing);
    expect(_chip(tester, '05.10.2026 – 15.10.2026').selected, isTrue);
    expect(shownAmounts(tester), [
      '340 ₽',
      '560 ₽',
      '190 ₽',
      '1 640 ₽',
      '6 400 ₽',
    ]);
  });

  testWidgets('категории: можно несколько, чип показывает выбор, «Все '
      'категории» снимает фильтр', (tester) async {
    await openSearch(tester);

    await _tapChip(tester, 'Все категории');
    expect(find.byType(SearchCategoriesSheet), findsOneWidget);
    await _toggleCategory(tester, 'Продукты');
    expect(shownAmounts(tester), ['640 ₽', '560 ₽']);

    await _toggleCategory(tester, 'Кафе');
    expect(shownAmounts(tester), hasLength(6));

    await tester.tap(find.text('Готово'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchCategoriesSheet), findsNothing);
    expect(_chip(tester, '2 категории').selected, isTrue);

    await _tapChip(tester, '2 категории');
    await _toggleCategory(tester, 'Кафе');
    await tester.tap(find.text('Готово'));
    await tester.pumpAndSettle();
    final single = _chip(tester, 'Продукты');
    expect(single.emoji, '🛒');
    expect(single.selected, isTrue);

    await typeQuery(tester, 'кофе');
    expect(shownAmounts(tester), ['560 ₽']);

    await _tapChip(tester, 'Продукты');
    await _toggleCategory(tester, 'Все категории');
    await tester.tap(find.text('Готово'));
    await tester.pumpAndSettle();
    expect(_chip(tester, 'Все категории').selected, isFalse);
    expect(shownAmounts(tester), hasLength(5));
  });

  testWidgets('переход из статистики: категория и период из адреса сразу '
      'применены', (tester) async {
    final db = openTestDatabase();
    final seed = (await tester.runAsync(() => seedSearchMockup(db)))!;
    final h = await openSearch(
      tester,
      seed: (_) async {},
      database: db,
      location: AppRoutes.searchFor(
        categoryId: seed.categoryIds['Кафе']!,
        from: LocalDate(2026, 10, 1),
        to: LocalDate(2026, 10, 31),
      ),
    );

    expect(_chip(tester, 'Кафе').selected, isTrue);
    expect(_chip(tester, 'Кафе').emoji, '☕');
    expect(_chip(tester, 'Октябрь 2026').selected, isTrue);
    expect(shownAmounts(tester), ['210 ₽', '340 ₽', '190 ₽', '170 ₽']);
    expect(
      searchDebugLogs(h),
      contains('search filters from route: period=month categories=1'),
    );
  });

  testWidgets('категория из адреса удалена — warn и поиск без неё', (
    tester,
  ) async {
    final h = await openSearch(
      tester,
      location: AppRoutes.searchFor(
        categoryId: 'gone',
        from: LocalDate(2026, 9, 1),
        to: LocalDate(2026, 9, 30),
      ),
    );

    expect(_chip(tester, 'Все категории').selected, isFalse);
    expect(_chip(tester, 'Сентябрь 2026').selected, isTrue);
    expect(shownAmounts(tester), ['300 ₽']);
    expect(
      [
        for (final r in h.records)
          if (r.level == Level.WARNING && r.loggerName == 'search') r.message,
      ],
      [
        matches(
          r'^search filter category=gone not found among 11 live '
          r'categories of budgetId=\S+, filter dropped$',
        ),
      ],
    );
  });
}
