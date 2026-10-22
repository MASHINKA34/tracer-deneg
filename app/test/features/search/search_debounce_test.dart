import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/features/search/search_screen.dart';

import 'search_fixture.dart';

void main() {
  testWidgets('поле в фокусе сразу; без запроса — все траты бюджета', (
    tester,
  ) async {
    await openSearch(tester);

    final field = tester.widget<EditableText>(find.byType(EditableText));
    expect(field.focusNode.hasFocus, isTrue);
    expect(foundLine(tester), 'Найдено 11 трат · 12 014 ₽');
    expect(shownAmounts(tester), hasLength(11));
  });

  testWidgets('поиск уходит через 250 мс после последней буквы, а не на '
      'каждую букву', (tester) async {
    final h = await openSearch(tester);
    h.records.clear();

    for (final text in ['к', 'ко', 'коф', 'кофе']) {
      await tester.enterText(find.byType(EditableText), text);
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      searchDebugLogs(h).where((m) => m.startsWith('search started')),
      isEmpty,
    );

    await tester.pump(const Duration(milliseconds: 149));
    expect(
      searchDebugLogs(h).where((m) => m.startsWith('search started')),
      isEmpty,
    );
    expect(shownAmounts(tester), hasLength(11));

    await tester.pump(const Duration(milliseconds: 1));
    expect(searchDebugLogs(h).where((m) => m.startsWith('search started')), [
      startsWith('search started trigger=typing length=4 '),
    ]);
    await settleSearch(tester);

    expect(shownAmounts(tester), ['210 ₽', '340 ₽', '560 ₽', '190 ₽', '170 ₽']);
    expect(foundLine(tester), 'Найдено 5 трат · 1 470 ₽');
  });

  testWidgets('«Найти» на клавиатуре ищет сразу, без ожидания', (tester) async {
    final h = await openSearch(tester);
    h.records.clear();

    await tester.enterText(find.byType(EditableText), 'метро');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    expect(searchDebugLogs(h).where((m) => m.startsWith('search started')), [
      startsWith('search started trigger=submit length=5 '),
    ]);
    await tester.pump(searchDebounce);
    await settleSearch(tester);

    expect(shownAmounts(tester), ['64 ₽']);
    expect(
      searchDebugLogs(h).where((m) => m.startsWith('search started')),
      hasLength(1),
    );
  });

  testWidgets('крестик стирает запрос сразу и оставляет фокус в поле', (
    tester,
  ) async {
    final h = await openSearch(tester);
    await typeQuery(tester, 'кофе');
    expect(shownAmounts(tester), hasLength(5));
    h.records.clear();

    await tester.tap(find.bySemanticsLabel('Очистить'));
    await settleSearch(tester);

    expect(find.text('кофе'), findsNothing);
    expect(shownAmounts(tester), hasLength(11));
    expect(find.bySemanticsLabel('Очистить'), findsNothing);
    final field = tester.widget<EditableText>(find.byType(EditableText));
    expect(field.focusNode.hasFocus, isTrue);
    expect(
      searchDebugLogs(h),
      containsAll([
        'search query cleared by x button length=4',
        startsWith('search started trigger=clear length=0 '),
      ]),
    );
  });
}
