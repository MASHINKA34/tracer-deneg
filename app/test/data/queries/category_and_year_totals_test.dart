import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/data/queries/stats_queries.dart';
import 'package:milionchik/ui/catalog/demo_months.dart';
import 'package:shared/shared.dart';

import 'query_fixture.dart';

void main() {
  late QueryHarness h;

  setUp(() async {
    h = QueryHarness();
    await h.seedMockup();
  });

  tearDown(() => h.dispose());

  List<String> describe(List<CategoryTotal> totals) => [
    for (final t in totals)
      '${h.categoryNames(h.budget)[t.categoryId]} ${t.total.format()} ×${t.count}',
  ];

  test('категории за октябрь - сумма, число трат, по убыванию суммы', () async {
    final totals = await h.stats
        .watchCategoryTotals(
          h.budget.id,
          from: october.firstDay,
          to: october.lastDay,
        )
        .first;

    expect(describe(totals), [
      'Продукты 7${nbsp}290,10$nbsp₽ ×8',
      'Здоровье 2${nbsp}900$nbsp₽ ×1',
      'Кафе 2${nbsp}570$nbsp₽ ×7',
      'Транспорт 1${nbsp}990$nbsp₽ ×4',
      'Одежда 1${nbsp}640$nbsp₽ ×1',
      'Дом 1${nbsp}360$nbsp₽ ×2',
      'Развлечения 400$nbsp₽ ×1',
      'Связь 149,90$nbsp₽ ×1',
    ]);
    expect(Money.sum(totals.map((t) => t.total)), const Money.rubles(18300));
  });

  test('доли категорий считает shared - целые, в сумме 100', () async {
    final totals = await h.stats
        .watchCategoryTotals(
          h.budget.id,
          from: october.firstDay,
          to: october.lastDay,
        )
        .first;

    final shares = percentShares([for (final t in totals) t.total.kopecks]);

    expect(shares, [40, 16, 14, 11, 9, 7, 2, 1]);
    expect(shares.reduce((a, b) => a + b), 100);
  });

  test('категории за отрезок 1–7 октября и за один день', () async {
    final week = await h.stats
        .watchCategoryTotals(
          h.budget.id,
          from: october.firstDay,
          to: october.dayOf(7),
        )
        .first;
    final day = await h.stats
        .watchCategoryTotals(
          h.budget.id,
          from: october.dayOf(18),
          to: october.dayOf(18),
        )
        .first;

    expect(describe(week), [
      'Продукты 3${nbsp}300,10$nbsp₽ ×2',
      'Транспорт 1${nbsp}310$nbsp₽ ×2',
      'Кафе 940$nbsp₽ ×3',
      'Связь 149,90$nbsp₽ ×1',
    ]);
    expect(describe(day), ['Развлечения 400$nbsp₽ ×1']);
  });

  test('равные суммы - в порядке категорий пользователя', () async {
    final b = h.otherBudget;
    final month = YearMonth(2026, 11);
    await h.seed(b, month, const [
      Spend(2, 'Спорт', Money.rubles(100), '', '10:00'),
      Spend(3, 'Продукты', Money.rubles(100), '', '10:00'),
      Spend(4, 'Кафе', Money.rubles(60), '', '10:00'),
      Spend(5, 'Кафе', Money.rubles(40), '', '10:00'),
    ]);

    final totals = await h.stats
        .watchCategoryTotals(b.id, from: month.firstDay, to: month.lastDay)
        .first;

    expect(
      [for (final t in totals) h.categoryNames(b)[t.categoryId]],
      ['Продукты', 'Кафе', 'Спорт'],
    );
  });

  test('месяцы 2026 года - 12 значений, январь первым', () async {
    final months = await h.stats.watchMonthTotals(h.budget.id, 2026).first;

    expect(months, hasLength(12));
    expect(months, [
      Money.sum(demoWinter.dayTotals.values),
      Money.zero,
      Money.zero,
      Money.sum(demoSpring.dayTotals.values),
      Money.zero,
      Money.zero,
      Money.sum(demoSummer.dayTotals.values),
      Money.zero,
      const Money.rubles(6464),
      const Money.rubles(18300),
      Money.zero,
      Money.zero,
    ]);
  });

  test('месяцы года - граница декабря 2025 и пустой год', () async {
    final previous = await h.stats.watchMonthTotals(h.budget.id, 2025).first;
    final empty = await h.stats.watchMonthTotals(h.budget.id, 2024).first;

    expect(previous.last, const Money.rubles(5000));
    expect(Money.sum(previous), const Money.rubles(5000));
    expect(empty, List.filled(12, Money.zero));
  });

  test('реактивно: удаление категории переносит её итог в «Другое»', () async {
    final totals = Watcher(
      h.stats.watchCategoryTotals(
        h.budget.id,
        from: october.firstDay,
        to: october.lastDay,
      ),
    );
    addTearDown(totals.cancel);
    final before = describe(await totals.next());

    await h.repo.categories.delete(h.budget.byName('Одежда').id);
    final after = describe(await totals.next());

    expect(before, contains('Одежда 1${nbsp}640$nbsp₽ ×1'));
    expect(after, isNot(contains(startsWith('Одежда'))));
    expect(after, contains('Другое 1${nbsp}640$nbsp₽ ×1'));
  });

  test('реактивно: новая трата меняет месяц года', () async {
    final months = Watcher(h.stats.watchMonthTotals(h.budget.id, 2026));
    addTearDown(months.cancel);
    expect((await months.next())[10], Money.zero);

    await h.repo.expenses.create(
      budgetId: h.budget.id,
      categoryId: h.budget.byName('Подарки').id,
      amount: const Money.rubles(1500),
      spentOn: LocalDate(2026, 11, 1),
    );

    expect((await months.next())[10], const Money.rubles(1500));
  });
}
