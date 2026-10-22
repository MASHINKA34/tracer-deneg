import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milionchik/features/search/search_period.dart';
import 'package:milionchik/l10n/app_localizations_ru.dart';
import 'package:shared/shared.dart';

Expense _expense(String id, LocalDate day) => Expense(
  id: id,
  budgetId: 'b',
  categoryId: 'c',
  amount: Money.rubles(100),
  spentOn: day,
  authorId: 'u',
  createdAt: DateTime.utc(2026, 10, 19),
  updatedAt: DateTime.utc(2026, 10, 19),
  updatedBy: 'u',
);

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  final today = LocalDate(2026, 10, 19);
  final l10n = AppLocalizationsRu();

  test('диапазон периода считается от сегодняшнего дня', () {
    expect(SearchPeriod.all.rangeOn(today), (from: null, to: null));
    expect(const SearchPeriod.month().rangeOn(today), (
      from: LocalDate(2026, 10, 1),
      to: LocalDate(2026, 10, 31),
    ));
    expect(const SearchPeriod.year().rangeOn(today), (
      from: LocalDate(2026, 1, 1),
      to: LocalDate(2026, 12, 31),
    ));
    expect(
      SearchPeriod.custom(
        LocalDate(2026, 10, 5),
        LocalDate(2026, 10, 15),
      ).rangeOn(today),
      (from: LocalDate(2026, 10, 5), to: LocalDate(2026, 10, 15)),
    );
  });

  test('диапазон из адреса узнаёт этот месяц и этот год, остальное — свои '
      'даты', () {
    SearchPeriod of(LocalDate from, LocalDate to) =>
        SearchPeriod.ofRange(from, to, today: today);

    expect(
      of(LocalDate(2026, 10, 1), LocalDate(2026, 10, 31)),
      const SearchPeriod.month(),
    );
    expect(
      of(LocalDate(2026, 1, 1), LocalDate(2026, 12, 31)),
      const SearchPeriod.year(),
    );
    expect(
      of(LocalDate(2026, 9, 1), LocalDate(2026, 9, 30)).kind,
      SearchPeriodKind.custom,
    );
    expect(
      () => SearchPeriod.custom(LocalDate(2026, 10, 2), LocalDate(2026, 10, 1)),
      throwsArgumentError,
    );
  });

  test('подпись чипа периода', () {
    String label(SearchPeriod p) => searchPeriodChipLabel(l10n, p, today);

    expect(label(SearchPeriod.all), 'За всё время');
    expect(label(const SearchPeriod.month()), 'Октябрь 2026');
    expect(label(const SearchPeriod.year()), '2026 год');
    expect(
      label(SearchPeriod.custom(LocalDate(2026, 9, 1), LocalDate(2026, 9, 30))),
      'Сентябрь 2026',
    );
    expect(
      label(
        SearchPeriod.custom(LocalDate(2025, 1, 1), LocalDate(2025, 12, 31)),
      ),
      '2025 год',
    );
    expect(
      label(
        SearchPeriod.custom(LocalDate(2026, 10, 5), LocalDate(2026, 10, 15)),
      ),
      '05.10.2026 – 15.10.2026',
    );
  });

  test('заголовок дня: без года в этом году, с годом — в другом', () {
    expect(searchDayTitle(LocalDate(2026, 10, 3), today), '3 октября');
    expect(searchDayTitle(LocalDate(2025, 12, 28), today), '28 декабря 2025');
  });

  test('результаты группируются по дням в порядке запроса', () {
    final days = groupSearchResults([
      _expense('a', LocalDate(2026, 10, 19)),
      _expense('b', LocalDate(2026, 10, 15)),
      _expense('c', LocalDate(2026, 10, 15)),
      _expense('d', LocalDate(2026, 10, 3)),
    ]);

    expect(
      [for (final d in days) d.day],
      [
        LocalDate(2026, 10, 19),
        LocalDate(2026, 10, 15),
        LocalDate(2026, 10, 3),
      ],
    );
    expect(
      [for (final d in days) d.expenses.map((e) => e.id).join()],
      ['a', 'bc', 'd'],
    );
    expect(groupSearchResults(const []), isEmpty);
  });
}
