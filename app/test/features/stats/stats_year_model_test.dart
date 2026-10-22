import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/data/queries/stats_queries.dart';
import 'package:milionchik/features/stats/stats_year.dart';
import 'package:milionchik/features/stats/year_chart.dart';
import 'package:shared/shared.dart';

import 'stats_year_fixture.dart';

const String _budget = 'budget-1';

Category _category(String id, String name, CategoryColor? color, int order) =>
    Category(
      id: id,
      budgetId: _budget,
      name: name,
      emoji: '🙂',
      color: color,
      sortOrder: order,
      isSystem: color == null,
      updatedAt: DateTime.utc(2026),
      updatedBy: 'user',
    );

final List<Category> _categories = [
  _category('food', 'Продукты', CategoryColor.green, 0),
  _category('cafe', 'Кафе', CategoryColor.orange, 1),
  _category('other', 'Другое', null, 10),
];

List<Money> _months(List<int> rubles) => [
  for (var i = 0; i < 12; i++)
    i < rubles.length ? Money.rubles(rubles[i]) : Money.zero,
];

StatsYear _of({
  int year = 2026,
  LocalDate? today,
  required List<int> months,
  List<CategoryTotal> totals = const [],
}) => StatsYear.of(
  year: year,
  today: today ?? LocalDate(2026, 10, 19),
  budgetId: _budget,
  monthTotals: _months(months),
  totals: totals,
  categories: _categories,
);

void main() {
  group('год как 46:5398', () {
    final stats = _of(
      months: mockupYearMonths,
      totals: [
        CategoryTotal(
          categoryId: 'food',
          total: const Money.rubles(72400),
          count: 212,
        ),
        CategoryTotal(
          categoryId: 'cafe',
          total: const Money.rubles(35900),
          count: 124,
        ),
        CategoryTotal(
          categoryId: 'gone',
          total: const Money.rubles(103050),
          count: 361,
        ),
      ],
    );

    test('итог 211 350 ₽ — сумма месяцев, в среднем 21 135 ₽ за 10 '
        'прошедших месяцев', () {
      expect(stats.total, const Money.rubles(211350));
      expect(stats.average, const Money.rubles(21135));
      expect(stats.monthsWithSpending, 10);
      expect(stats.isEmpty, isFalse);
    });

    test('самый дорогой — июль 24 300 ₽, подпись «24,3к»', () {
      expect(stats.priciest, 7);
      expect(stats.months[6].formatCell(), '24,3к');
    });

    test('высоты столбиков как в макете из 110', () {
      expect(yearBarHeights(stats.months), [
        97,
        90,
        100,
        81,
        94,
        107,
        110,
        103,
        92,
        83,
        0,
        0,
      ]);
    });

    test('категории по убыванию с долями, удалённая — в «Другое»', () {
      expect(
        [for (final c in stats.categories) c.id],
        ['other', 'food', 'cafe'],
      );
      expect([for (final c in stats.categories) c.percent], [49, 34, 17]);
      expect(stats.expenseCount, 697);
      expect(stats.unknownCategoryIds, ['gone']);
    });

    test('период поиска — весь год', () {
      expect(stats.from, LocalDate(2026, 1, 1));
      expect(stats.to, LocalDate(2026, 12, 31));
    });
  });

  test('месяцы: до текущего — прошлые, текущий, после — будущие', () {
    final today = LocalDate(2026, 10, 19);
    expect(
      [
        for (var m = 1; m <= 12; m++)
          statsYearMonthKind(YearMonth(2026, m), today),
      ],
      [
        ...List.filled(9, StatsYearMonthKind.past),
        StatsYearMonthKind.current,
        StatsYearMonthKind.future,
        StatsYearMonthKind.future,
      ],
    );
    expect(
      statsYearMonthKind(YearMonth(2025, 12), today),
      StatsYearMonthKind.past,
    );
    expect(
      statsYearMonthKind(YearMonth(2027, 1), today),
      StatsYearMonthKind.future,
    );
  });

  test('среднее — только по прошедшим месяцам, включая текущий: трата '
      'только в октябре делится на 10', () {
    final stats = _of(months: [0, 0, 0, 0, 0, 0, 0, 0, 0, 18300]);
    expect(stats.average, const Money.rubles(1830));
  });

  test('прошлый год — среднее на 12 месяцев', () {
    final stats = _of(year: 2025, months: List.filled(12, 1000));
    expect(stats.total, const Money.rubles(12000));
    expect(stats.average, const Money.rubles(1000));
  });

  test('нет трат — пусто, среднего и самого дорогого нет', () {
    final stats = _of(months: const []);
    expect(stats.isEmpty, isTrue);
    expect(stats.average, isNull);
    expect(stats.priciest, isNull);
    expect(yearBarHeights(stats.months), List.filled(12, 0));
    expect(StatsYear.empty(2026, budgetId: null).isEmpty, isTrue);
  });

  test('не 12 месяцев — ошибка входных данных', () {
    expect(
      () => StatsYear.of(
        year: 2026,
        today: LocalDate(2026, 10, 19),
        budgetId: _budget,
        monthTotals: const [Money.zero],
        totals: const [],
        categories: _categories,
      ),
      throwsArgumentError,
    );
  });

  test('фикстура макета: итоги месяцев и категорий как в 46:5398', () {
    final spends = mockupYearSpends();
    expect(spends, hasLength(697));
    final byMonth = List.filled(10, 0);
    final byCategory = <String, (int, int)>{};
    for (final (day, category, rubles) in spends) {
      expect(rubles, greaterThan(0));
      expect(day.year, 2026);
      byMonth[day.month - 1] += rubles;
      final (sum, count) = byCategory[category] ?? (0, 0);
      byCategory[category] = (sum + rubles, count + 1);
    }
    expect(byMonth, mockupYearMonths);
    expect(byCategory['Продукты'], (72400, 212));
    expect(byCategory['Кафе'], (35900, 124));
    expect(byCategory['Спорт'], (29000, 10));
    expect(byCategory['Транспорт'], (24100, 268));
    expect(
      spends.where((s) => s.$1.month == 10).every((s) => s.$1.day <= 19),
      isTrue,
    );
  });
}
