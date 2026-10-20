import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/queries/search_queries.dart';
import 'package:shared/shared.dart';

import 'query_fixture.dart';

const List<String> _comments = [
  'Кофе с собой',
  'Пятёрочка',
  'Метро',
  'ВкусВилл',
  'Обед',
  '',
  'Такси',
  'Аптека',
  'Ёлка',
  'Кино',
  'кофе в зёрнах',
  'Подарок',
];

final RegExp _debugLine = RegExp(
  r'^query (\S+) .* rows=(\d+) trigger=\S+ in (\d+)ms$',
);

void main() {
  late QueryHarness h;
  late SeededBudget b;
  late List<Expense> seeded;

  setUp(() async {
    h = QueryHarness();
    b = await h.repo.seedBudget(id: 'budget-speed');
    h.budget = b;
    seeded = [];
    for (final month in [
      YearMonth(2026, 8),
      YearMonth(2026, 9),
      YearMonth(2026, 10),
    ]) {
      seeded.addAll(
        await h.seed(b, month, [
          for (var day = 1; day <= month.daysInMonth; day++)
            for (var i = 0; i < 6; i++)
              Spend(
                day,
                b.categories[(day + i) % b.categories.length].name,
                Money(
                  (day * 3700 + i * 11300 + month.month * 900) % 300000 + 5000,
                ),
                _comments[(day * 5 + i) % _comments.length],
                '${8 + i * 2}:${day % 6}0'.padLeft(5, '0'),
              ),
        ]),
      );
    }
    h.repo.records.clear();
  });

  tearDown(() => h.dispose());

  test('три месяца по 6 трат в день - все запросы, строки и самый медленный', () async {
    final id = b.id;
    final october = YearMonth(2026, 10);
    final from = LocalDate(2026, 8, 1);
    final to = LocalDate(2026, 10, 31);

    final days = await h.month.watchDayTotals(id, october).first;
    final total = await h.month.watchMonthTotal(id, october).first;
    final day = await h.month.watchDayExpenses(id, october.dayOf(19)).first;
    final categories = await h.stats
        .watchCategoryTotals(id, from: from, to: to)
        .first;
    final year = await h.stats.watchMonthTotals(id, 2026).first;
    final recent = await h.search.watchRecentComments(id).first;
    final coffee = await h.search
        .watchSearch(SearchFilters(budgetId: id, text: 'кофе'))
        .first;
    final amount = await h.search
        .watchSearch(SearchFilters(budgetId: id, text: '640'))
        .first;
    final filtered = await h.search
        .watchSearch(
          SearchFilters(
            budgetId: id,
            from: october.firstDay,
            to: october.lastDay,
            categoryIds: {b.byName('Кафе').id, b.byName('Продукты').id},
          ),
        )
        .first;

    final inOctober = seeded.where((e) => october.contains(e.spentOn));
    expect(seeded, hasLength(92 * 6));
    expect(days, hasLength(31));
    expect(total, Money.sum(inOctober.map((e) => e.amount)));
    expect(day, hasLength(6));
    expect(categories, hasLength(11));
    expect(Money.sum(categories.map((c) => c.total)), Money.sum(year));
    expect(Money.sum(year), Money.sum(seeded.map((e) => e.amount)));
    expect(recent, hasLength(6));
    expect(
      coffee.count,
      seeded.where((e) => textMatches('кофе', e.comment)).length,
    );
    expect(
      amount.count,
      seeded.where((e) {
        final name = b.categories.firstWhere((c) => c.id == e.categoryId).name;
        return expenseMatches(
          query: '640',
          comment: e.comment,
          categoryName: name,
          amount: e.amount,
        );
      }).length,
    );
    expect(filtered.count, greaterThan(0));

    final timings = <String, int>{};
    for (final r in h.queryLogs(Level.FINE)) {
      final match = _debugLine.firstMatch(r.message);
      if (match == null) continue;
      final name = match.group(1)!;
      final ms = int.parse(match.group(3)!);
      timings[name] = ms > (timings[name] ?? -1) ? ms : timings[name]!;
    }
    expect(timings.keys.toSet(), {
      'day-totals',
      'month-total',
      'day-expenses',
      'category-totals',
      'month-totals',
      'recent-comments',
      'search',
    });
    final slowest = timings.entries.reduce((a, b) => b.value > a.value ? b : a);
    debugPrint(
      'three months: expenses=${seeded.length} slowest=${slowest.key} '
      'in ${slowest.value}ms all=${timings.entries.map((e) => '${e.key}:${e.value}ms').join(',')}',
    );
  });
}
