import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'search_fixture.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('«кофе» и «Кофе» находят одни и те же 5 трат, по датам с '
      'заголовками дней', (tester) async {
    await openSearch(tester);

    await typeQuery(tester, 'кофе');
    final lower = shownAmounts(tester);
    expect(lower, ['210 ₽', '340 ₽', '560 ₽', '190 ₽', '170 ₽']);
    expect(foundLine(tester), 'Найдено 5 трат · 1 470 ₽');
    for (final day in ['19 октября', '15 октября', '11 октября', '3 октября']) {
      expect(inSearch(find.text(day)), findsOneWidget);
    }

    await typeQuery(tester, 'Кофе');
    expect(shownAmounts(tester), lower);
  });

  testWidgets('«ёлка» и «елка» находят «Ёлка на Новый год», дата другого '
      'года — с годом', (tester) async {
    await openSearch(tester);

    await typeQuery(tester, 'ёлка');
    expect(shownAmounts(tester), ['1 500 ₽']);
    expect(inSearch(find.text('28 декабря 2025')), findsOneWidget);

    await typeQuery(tester, 'елка');
    expect(shownAmounts(tester), ['1 500 ₽']);
    expect(foundLine(tester), 'Найдена 1 трата · 1 500 ₽');
  });

  testWidgets('«640» находит 640 ₽ и 6 400 ₽, но не 64 ₽ и не 1 640 ₽', (
    tester,
  ) async {
    await openSearch(tester);

    await typeQuery(tester, '640');

    expect(shownAmounts(tester), ['640 ₽', '6 400 ₽']);
    expect(foundLine(tester), 'Найдено 2 траты · 7 040 ₽');
  });

  testWidgets('название категории: «кафе» находит все траты «Кафе»', (
    tester,
  ) async {
    await openSearch(tester);

    await typeQuery(tester, 'кафе');

    expect(shownAmounts(tester), ['210 ₽', '340 ₽', '190 ₽', '170 ₽']);
  });
}
