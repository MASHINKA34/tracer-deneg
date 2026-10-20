import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/data/dev_seed.dart';
import 'package:milionchik/data/queries/search_queries.dart';
import 'package:milionchik/data/queries/stats_queries.dart';
import 'package:milionchik/ui/catalog/demo_months.dart';
import 'package:shared/shared.dart';

import 'queries/query_fixture.dart';

String _hhmm(DateTime t) {
  final local = t.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

void main() {
  late QueryHarness h;
  late Budget budget;
  late Map<String, String> names;

  setUp(() async {
    h = QueryHarness();
    final result = await DevSeed(
      h.db,
      currentUser: h.repo.user,
    ).runIfRequested(flag: 'true', debugBuild: true);
    expect(result.status, DevSeedStatus.seeded);
    budget = (await h.repo.budgets.watchAll().first).single;
    names = {
      for (final c in await h.repo.categories.watchByBudget(budget.id).first)
        c.id: c.name,
    };
  });

  tearDown(() => h.dispose());

  List<String> rows(List<Expense> expenses) => [
    for (final e in expenses)
      '${names[e.categoryId]} · ${e.amount.format()} · ${e.comment} · '
          '${_hhmm(e.createdAt)}',
  ];

  Future<List<CategoryTotal>> categoryTotals(LocalDate from, LocalDate to) =>
      h.stats.watchCategoryTotals(budget.id, from: from, to: to).first;

  Future<Money> spent(LocalDate from, LocalDate to) async =>
      Money.sum([for (final t in await categoryTotals(from, to)) t.total]);

  test('октябрь как карточка 7:7: суммы по дням как demoAutumn, итог '
      '18 300 ₽ и 963 ₽ в день', () async {
    final days = await h.month.watchDayTotals(budget.id, october).first;
    final total = await h.month.watchMonthTotal(budget.id, october).first;

    expect(days, demoAutumn.dayTotals);
    expect(total.formatTotal(), '18${nbsp}300$nbsp₽');
    expect(
      averagePerDay(
        monthTotal: total,
        month: october,
        today: demoAutumn.today,
      )!.formatTotal(),
      '963$nbsp₽',
    );
  });

  test('17 октября как шторка 9:439: две траты на 1 450 ₽ со временем, '
      'больше среднего на 487 ₽', () async {
    final day = october.dayOf(17);
    final expenses = await h.month.watchDayExpenses(budget.id, day).first;
    final days = await h.month.watchDayTotals(budget.id, october).first;
    final average = averagePerDay(
      monthTotal: await h.month.watchMonthTotal(budget.id, october).first,
      month: october,
      today: demoAutumn.today,
    )!;

    expect(rows(expenses), [
      'Кафе · 890$nbsp₽ · Обед с коллегами · 13:30',
      'Продукты · 560$nbsp₽ · ВкусВилл · 19:10',
    ]);
    for (final e in expenses) {
      expect(LocalDate.fromDateTime(e.createdAt.toLocal()), day);
    }
    expect(days[17]!.formatTotal(), '1${nbsp}450$nbsp₽');
    expect(
      differenceFromAverage(daySum: days[17]!, average: average).formatTotal(),
      '487$nbsp₽',
    );
  });

  test('19 октября как блок «Сегодня» на 7:7: Пятёрочка 640 ₽ в 18:40, '
      'метро 250 ₽ и кофе 210 ₽ в 09:15', () async {
    final expenses = await h.month
        .watchDayExpenses(budget.id, demoAutumn.today)
        .first;

    expect(rows(expenses), [
      'Кафе · 210$nbsp₽ · Кофе с собой · 09:15',
      'Транспорт · 250$nbsp₽ · Метро, 2 поездки · 12:40',
      'Продукты · 640$nbsp₽ · Пятёрочка · 18:40',
    ]);
  });

  test('категории октября как статистика 12:820: семь категорий, суммы, '
      'доли 34/17/16/12/9/6/6 и число трат', () async {
    final totals = await categoryTotals(october.firstDay, october.lastDay);

    expect(
      [for (final t in totals) '${names[t.categoryId]} ${t.total.format()}'],
      [
        'Продукты 6${nbsp}240$nbsp₽',
        'Кафе 3${nbsp}180$nbsp₽',
        'Спорт 2${nbsp}900$nbsp₽',
        'Транспорт 2${nbsp}150$nbsp₽',
        'Развлечения 1${nbsp}640$nbsp₽',
        'Связь 1${nbsp}100$nbsp₽',
        'Здоровье 1${nbsp}090$nbsp₽',
      ],
    );
    expect(percentShares([for (final t in totals) t.total.kopecks]), [
      34,
      17,
      16,
      12,
      9,
      6,
      6,
    ]);
    expect([for (final t in totals) t.count], [18, 11, 1, 6, 4, 2, 1]);
  });

  test('сравнение с сентябрём на 19 октября как 9:257 и 12:820: на 2 100 ₽ '
      'меньше, −10%', () async {
    final period = comparisonPeriod(october, demoAutumn.today);
    final comparison = compareMonths(
      current: await spent(period.currentFrom, period.currentTo),
      previous: await spent(period.previousFrom, period.previousTo),
    )!;

    expect(comparison.difference, const Money.rubles(-2100));
    expect(comparison.percent, -10);
  });

  test('три месяца: траты только в августе, сентябре и октябре 2026, '
      'в октябре не позже 19-го', () async {
    final months = await h.stats.watchMonthTotals(budget.id, 2026).first;
    final previousYear = await h.stats.watchMonthTotals(budget.id, 2025).first;
    final days = await h.month.watchDayTotals(budget.id, october).first;

    expect(
      [
        for (final (i, total) in months.indexed)
          if (total.kopecks > 0) i + 1,
      ],
      [8, 9, 10],
    );
    expect(months[9], const Money.rubles(18300));
    expect(previousYear.every((m) => m == Money.zero), isTrue);
    expect(days.keys.reduce((a, b) => a > b ? a : b), 19);
  });

  test('личный бюджет с 11 готовыми категориями, траты от текущего '
      'пользователя, каждая запись в outbox', () async {
    final expenses = await h.db.select(h.db.expenses).get();
    final outbox = await h.repo.outboxRows();

    expect(budget.kind, BudgetKind.personal);
    expect(budget.ownerId, meId);
    expect(names.values, [for (final p in presetCategories) p.name]);
    expect(expenses, isNotEmpty);
    expect(expenses.every((e) => e.authorId == meId), isTrue);
    expect(expenses.every((e) => e.deletedAt == null), isTrue);
    expect(
      [
        for (final e in SyncEntity.values)
          outbox.where((o) => o.entity == e).length,
      ],
      [
        for (final e in SyncEntity.values)
          switch (e) {
            SyncEntity.budget => 1,
            SyncEntity.category => 11,
            SyncEntity.expense => expenses.length,
            _ => 0,
          },
      ],
    );
  });

  test('комментарии для поиска: «кофе» в разных категориях и регистрах, '
      '«пятерочка» через ё, «640» находит 640 ₽ и 6 400 ₽', () async {
    Future<SearchResult> find(String text) => h.search
        .watchSearch(SearchFilters(budgetId: budget.id, text: text))
        .first;

    final coffee = await find('кофе');
    final shop = await find('пятерочка');
    final amount = await find('640');

    expect(coffee.count, greaterThanOrEqualTo(10));
    expect(
      coffee.expenses.map((e) => e.comment),
      containsAll(['КОФЕ И ПИРОГ', 'Кофе с собой', 'Кофе в зёрнах']),
    );
    expect(
      {for (final e in coffee.expenses) names[e.categoryId]},
      {'Кафе', 'Продукты'},
    );
    expect(shop.count, greaterThanOrEqualTo(5));
    expect(shop.expenses.every((e) => e.comment == 'Пятёрочка'), isTrue);
    expect(
      {for (final e in amount.expenses) e.amount},
      {const Money.rubles(640), const Money.rubles(6400)},
    );
  });
}
