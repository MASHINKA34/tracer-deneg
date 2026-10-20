import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/data/queries/search_queries.dart';
import 'package:shared/shared.dart';

import 'query_fixture.dart';

void main() {
  late QueryHarness h;

  setUp(() async {
    h = QueryHarness();
    await h.seedMockup();
  });

  tearDown(() => h.dispose());

  Future<SearchResult> search(String text) => h.search
      .watchSearch(SearchFilters(budgetId: h.budget.id, text: text))
      .first;

  test('надгробие 4 октября (640 ₽, «кофе», «ёлка», самое свежее) не попадает '
      'ни в один запрос', () async {
    final id = h.budget.id;
    final cafe = h.budget.byName('Кафе').id;

    final days = await h.month.watchDayTotals(id, october).first;
    final total = await h.month.watchMonthTotal(id, october).first;
    final day4 = await h.month.watchDayExpenses(id, october.dayOf(4)).first;
    final categories = await h.stats
        .watchCategoryTotals(id, from: october.firstDay, to: october.lastDay)
        .first;
    final year = await h.stats.watchMonthTotals(id, 2026).first;
    final recent = await h.search.watchRecentComments(id).first;

    expect(days.containsKey(4), isFalse);
    expect(total, const Money.rubles(18300));
    expect(day4, isEmpty);
    expect(
      categories.firstWhere((t) => t.categoryId == cafe).total,
      const Money.rubles(2570),
    );
    expect(year[9], const Money.rubles(18300));
    expect(recent, isNot(contains(deletedComment)));
    expect((await search('удалённый')).count, 0);
    expect((await search('кофе')).count, 7);
    expect((await search('ёлка')).count, 2);
    expect((await search('640')).count, 3);
    expect((await search('')).count, h.live.length);
  });

  test(
    'трата, удалённая через репозиторий, пропадает из всех запросов',
    () async {
      final id = h.budget.id;
      final health = h.live.singleWhere((e) => e.comment == 'Аптека');

      await h.repo.expenses.delete(health.id);

      final days = await h.month.watchDayTotals(id, october).first;
      final total = await h.month.watchMonthTotal(id, october).first;
      final day12 = await h.month.watchDayExpenses(id, october.dayOf(12)).first;
      final categories = await h.stats
          .watchCategoryTotals(id, from: october.firstDay, to: october.lastDay)
          .first;
      final year = await h.stats.watchMonthTotals(id, 2026).first;
      final found = await search('аптека');
      final all = await search('');

      expect(days.containsKey(12), isFalse);
      expect(total, const Money.rubles(15400));
      expect(day12, isEmpty);
      expect(
        categories.map((t) => t.categoryId),
        isNot(contains(health.categoryId)),
      );
      expect(year[9], const Money.rubles(15400));
      expect(found.count, 0);
      expect(all.count, h.live.length - 1);
    },
  );
}
