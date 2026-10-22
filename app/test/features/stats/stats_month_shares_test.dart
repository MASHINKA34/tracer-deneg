import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/data/queries/stats_queries.dart';
import 'package:milionchik/features/stats/stats_month.dart';
import 'package:shared/shared.dart';

final DateTime _at = DateTime.utc(2026, 8, 1);

Category _category(
  String id,
  String emoji,
  String name,
  CategoryColor? color,
  int sortOrder, {
  bool isSystem = false,
}) => Category(
  id: id,
  budgetId: 'b1',
  name: name,
  emoji: emoji,
  color: color,
  sortOrder: sortOrder,
  isSystem: isSystem,
  updatedAt: _at,
  updatedBy: 'u1',
);

final List<Category> _categories = [
  _category('food', '🛒', 'Продукты', CategoryColor.green, 0),
  _category('cafe', '☕', 'Кафе', CategoryColor.orange, 1),
  _category('transport', '🚇', 'Транспорт', CategoryColor.yellow, 2),
  _category('home', '🏠', 'Дом', CategoryColor.blue, 3),
  _category('health', '💊', 'Здоровье', CategoryColor.red, 4),
  _category('sport', '🏋️', 'Спорт', CategoryColor.indigo, 5),
  _category('fun', '🎮', 'Развлечения', CategoryColor.pink, 6),
  _category('phone', '📱', 'Связь', CategoryColor.teal, 8),
  _category('other', '📦', 'Другое', null, 10, isSystem: true),
];

CategoryTotal _total(String id, int rubles, int count) =>
    CategoryTotal(categoryId: id, total: Money.rubles(rubles), count: count);

final List<CategoryTotal> _octoberFigma = [
  _total('food', 6240, 18),
  _total('cafe', 3180, 11),
  _total('sport', 2900, 1),
  _total('transport', 2150, 27),
  _total('fun', 1640, 4),
  _total('phone', 1100, 2),
  _total('health', 1090, 3),
];

Map<int, Money> _days(Map<int, int> rubles) => {
  for (final MapEntry(key: day, value: r) in rubles.entries)
    day: Money.rubles(r),
};

StatsMonth _october({
  List<CategoryTotal>? totals,
  List<Category>? categories,
  Map<int, Money>? days,
  Map<int, Money>? previousDays,
  YearMonth? month,
}) => StatsMonth.of(
  month: month ?? YearMonth(2026, 10),
  today: LocalDate(2026, 10, 19),
  budgetId: 'b1',
  totals: totals ?? _octoberFigma,
  categories: categories ?? _categories,
  days: days ?? _days({3: 10000, 12: 8300}),
  previousDays: previousDays ?? _days({5: 12000, 18: 8400, 25: 5000}),
);

void main() {
  group('доли октября из 12:820 (суммы категорий из макета)', () {
    final stats = _october();

    test('проценты «Продукты 34 %, Кафе 17 % …» и сумма ровно 100', () {
      expect(
        [for (final c in stats.categories) '${c.name} ${c.percent}'],
        [
          'Продукты 34',
          'Кафе 17',
          'Спорт 16',
          'Транспорт 12',
          'Развлечения 9',
          'Связь 6',
          'Здоровье 6',
        ],
      );
      expect(stats.categories.fold(0, (s, c) => s + c.percent), 100);
    });

    test('итог 18 300 ₽, 66 трат, в среднем 963 ₽ в день', () {
      expect(stats.total, Money.rubles(18300));
      expect(stats.total.formatTotal(), '18${nbsp}300$nbsp₽');
      expect(stats.expenseCount, 66);
      expect(stats.average, Money(96316));
      expect(stats.average!.formatTotal(), '963$nbsp₽');
    });

    test('полосы относительно самой большой — как ширины в макете из 308', () {
      expect(
        [for (final c in stats.categories) (308 * c.fraction).round()],
        [308, 157, 143, 106, 81, 54, 54],
      );
      expect(stats.categories.first.fraction, 1);
    });

    test('сравнение 1–19 октября с 1–19 сентября: −10 %, меньше', () {
      final comparison = stats.comparison!;
      expect(comparison.percent, -10);
      expect(comparison.isLess, isTrue);
      expect(comparison.difference, Money.rubles(-2100));
      expect(stats.previous, YearMonth(2026, 9));
    });

    test('эмодзи, цвет и id категории берутся из бюджета', () {
      final cafe = stats.categories[1];
      expect(cafe.id, 'cafe');
      expect(cafe.emoji, '☕');
      expect(cafe.color, CategoryColor.orange);
      expect(cafe.count, 11);
      expect(cafe.total, Money.rubles(3180));
    });
  });

  test('итоги не по порядку — сортировка по убыванию суммы, при равных '
      'суммах — как пришли из запроса', () {
    final stats = _october(
      totals: [
        _total('health', 100, 1),
        _total('cafe', 300, 2),
        _total('fun', 100, 1),
        _total('food', 500, 3),
      ],
    );

    expect(
      [for (final c in stats.categories) c.id],
      ['food', 'cafe', 'health', 'fun'],
    );
    expect([for (final c in stats.categories) c.percent], [50, 30, 10, 10]);
  });

  test('простое округление дало бы не 100: три равные доли — 34 + 33 + 33, '
      'четыре с половинками — 63 + 13 + 12 + 12', () {
    final thirds = _october(
      totals: [
        _total('food', 100, 1),
        _total('cafe', 100, 1),
        _total('fun', 100, 1),
      ],
    );
    final halves = _october(
      totals: [
        _total('cafe', 125, 1),
        _total('fun', 125, 1),
        _total('food', 625, 5),
        _total('phone', 125, 1),
      ],
    );

    expect([for (final c in thirds.categories) c.percent], [34, 33, 33]);
    expect(
      [for (final c in halves.categories) '${c.id} ${c.percent}'],
      ['food 63', 'cafe 13', 'fun 12', 'phone 12'],
    );
  });

  test('дни сентября после 19-го в сравнение текущего октября не '
      'попадают', () {
    final stats = _october(
      days: _days({19: 1000}),
      previousDays: _days({19: 1000, 20: 5000}),
    );

    expect(stats.comparison!.percent, 0);
  });

  test('больше прошлого месяца — положительный процент', () {
    final stats = _october(
      days: _days({1: 1250}),
      previousDays: _days({2: 1000}),
    );

    expect(stats.comparison!.percent, 25);
    expect(stats.comparison!.isMore, isTrue);
  });

  test('в прошлом месяце трат не было — сравнения нет', () {
    final stats = _october(previousDays: const {});

    expect(stats.comparison, isNull);
  });

  test('прошедший месяц сравнивается целиком с целым прошлым', () {
    final stats = StatsMonth.of(
      month: YearMonth(2026, 9),
      today: LocalDate(2026, 10, 19),
      budgetId: 'b1',
      totals: [_total('food', 3000, 2)],
      categories: _categories,
      days: _days({30: 3000}),
      previousDays: _days({31: 2000}),
    );

    expect(stats.comparison!.percent, 50);
    expect(stats.average, Money(10000));
  });

  test('категории нет среди живых — её траты в «Другое», id в списке '
      'неизвестных', () {
    final stats = _october(
      totals: [
        _total('food', 500, 3),
        _total('ghost', 300, 2),
        _total('other', 100, 1),
      ],
    );

    expect(
      [for (final c in stats.categories) '${c.id} ${c.name} ${c.count}'],
      ['food Продукты 3', 'other Другое 3'],
    );
    expect(stats.categories.last.total, Money.rubles(400));
    expect(stats.categories.last.color, isNull);
    expect(stats.unknownCategoryIds, ['ghost']);
    expect([for (final c in stats.categories) c.percent], [56, 44]);
  });

  test('нет трат — пусто: ни категорий, ни среднего, ни сравнения', () {
    final stats = _october(
      totals: const [],
      days: const {},
      previousDays: const {},
    );

    expect(stats.isEmpty, isTrue);
    expect(stats.total, Money.zero);
    expect(stats.expenseCount, 0);
    expect(stats.average, isNull);
    expect(stats.comparison, isNull);
  });

  test('пустая статистика без бюджета', () {
    final stats = StatsMonth.empty(YearMonth(2026, 10), budgetId: null);

    expect(stats.isEmpty, isTrue);
    expect(stats.budgetId, isNull);
    expect(stats.comparison, isNull);
  });
}
