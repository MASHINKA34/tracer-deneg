import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milionchik/core/router.dart';
import 'package:milionchik/features/search/search_results.dart';
import 'package:milionchik/ui/components/chip.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';
import 'search_fixture.dart';

Future<void> _reset(WidgetTester tester) async {
  await tester.tap(find.text('Сбросить фильтры'));
  await settleSearch(tester);
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('ничего не найдено — пустое состояние 46:5355 без итога', (
    tester,
  ) async {
    await openSearch(tester);

    await typeQuery(tester, 'самокат');

    expect(find.byType(SearchEmpty), findsOneWidget);
    expect(find.text('Ничего не нашли'), findsOneWidget);
    expect(
      find.text(
        'Попробуй другое слово или сбрось фильтры. Ищем по комментарию, '
        'названию категории и сумме.',
      ),
      findsOneWidget,
    );
    expect(find.text('Сбросить фильтры'), findsOneWidget);
    expect(foundLine(tester), isNull);
    expect(shownAmounts(tester), isEmpty);
  });

  testWidgets('«Сбросить фильтры» снимает период и категории, а запрос '
      'оставляет', (tester) async {
    final db = openTestDatabase();
    final seed = (await tester.runAsync(() => seedSearchMockup(db)))!;
    final h = await openSearch(
      tester,
      seed: (_) async {},
      database: db,
      location: AppRoutes.searchFor(
        categoryId: seed.categoryIds['Дом']!,
        from: LocalDate(2026, 9, 1),
        to: LocalDate(2026, 9, 30),
      ),
    );
    await typeQuery(tester, 'кофе');
    expect(find.byType(SearchEmpty), findsOneWidget);
    h.records.clear();

    await _reset(tester);

    expect(find.byType(SearchEmpty), findsNothing);
    expect(find.text('кофе'), findsOneWidget);
    expect(shownAmounts(tester), hasLength(5));
    final period = tester.widget<AppChip>(
      inSearch(find.widgetWithText(AppChip, 'За всё время')),
    );
    expect(period.selected, isFalse);
    final categories = tester.widget<AppChip>(
      inSearch(find.widgetWithText(AppChip, 'Все категории')),
    );
    expect(categories.selected, isFalse);
    expect(
      searchDebugLogs(h),
      contains(
        'search reset filters: period custom 2026-09-01..2026-09-30 → all, '
        'categories 1 → 0, query kept length=4',
      ),
    );
  });

  testWidgets('фильтров нет — «Сбросить фильтры» стирает запрос и '
      'показывает все траты', (tester) async {
    final h = await openSearch(tester);
    await typeQuery(tester, 'самокат');
    h.records.clear();

    await _reset(tester);

    expect(find.byType(SearchEmpty), findsNothing);
    expect(find.text('самокат'), findsNothing);
    final field = tester.widget<EditableText>(find.byType(EditableText));
    expect(field.controller.text, isEmpty);
    expect(shownAmounts(tester), hasLength(11));
    expect(
      searchDebugLogs(h),
      contains('search reset: no filters set, query cleared length=7'),
    );
  });
}
