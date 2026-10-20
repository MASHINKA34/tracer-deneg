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

  Future<SearchResult> search(
    String text, {
    LocalDate? from,
    LocalDate? to,
    Set<String> categories = const {},
    String? budgetId,
  }) => h.search
      .watchSearch(
        SearchFilters(
          budgetId: budgetId ?? h.budget.id,
          text: text,
          from: from,
          to: to,
          categoryIds: categories,
        ),
      )
      .first;

  String found(SearchResult r) =>
      describeSpends(r.expenses, h.categoryNames(h.budget));

  String categoryId(String name) => h.budget.byName(name).id;

  test('«кофе» - комментарии без учёта регистра, по убыванию даты, итог '
      'найдено N · сумма', () async {
    final result = await search('кофе');

    expect(
      found(result),
      '19:Кафе:210$nbsp₽, 15:Продукты:420$nbsp₽, 15:Кафе:340$nbsp₽, '
      '11:Кафе:190$nbsp₽, 6:Кафе:320$nbsp₽, 3:Кафе:170$nbsp₽, '
      '1:Кафе:450$nbsp₽',
    );
    expect(result.count, 7);
    expect(result.total, const Money.rubles(2100));
  });

  test('«Кофе» и «  КОФЕ » находят то же, что «кофе»', () async {
    final lower = await search('кофе');
    final upper = await search('Кофе');
    final shouting = await search('  КОФЕ ');

    expect(found(upper), found(lower));
    expect(found(shouting), found(lower));
    expect(upper.count, 7);
  });

  test('«ёлка» и «елка» находят и «Ёлка», и «елка»', () async {
    final yo = await search('ёлка');
    final ye = await search('елка');

    expect(found(yo), '13:Дом:210$nbsp₽, 8:Дом:1${nbsp}150$nbsp₽');
    expect(found(ye), found(yo));
    expect(yo.total, const Money.rubles(1360));
  });

  test('«640» - 640 ₽ и 6 400 ₽ за всё время, без 1 640 ₽ и 64 ₽', () async {
    final result = await search('640');

    expect(
      [for (final e in result.expenses) '${e.spentOn} ${e.amount.format()}'],
      [
        '2026-10-19 640$nbsp₽',
        '2026-09-20 6${nbsp}400$nbsp₽',
        '2026-01-31 640$nbsp₽',
      ],
    );
    expect(result.count, 3);
    expect(result.total, const Money.rubles(7680));
  });

  test('сумма с запятой: рубли точно, копейки по началу', () async {
    final names = h.categoryNames(h.budget);
    for (final query in ['149,9', '149,90', '149.9', '149,', '149']) {
      final result = await search(query);
      expect(
        describeSpends(result.expenses, names),
        '2:Связь:149,90$nbsp₽',
        reason: query,
      );
    }
    expect((await search('149,8')).count, 0);
    expect((await search('14,9')).count, 0);
  });

  test('название категории - «кафе» и «КАФЕ»', () async {
    final result = await search('кафе');

    expect(result.count, 7);
    expect(result.expenses.map(h.categoryOf).toSet(), {'Кафе'});
    expect(found(await search('КАФЕ')), found(result));
  });

  test('фильтры равны по значению, порядок категорий не важен', () {
    final a = SearchFilters(
      budgetId: 'b1',
      text: 'кофе',
      from: october.firstDay,
      categoryIds: {'c1', 'c2'},
    );
    final b = SearchFilters(
      budgetId: 'b1',
      text: 'кофе',
      from: october.firstDay,
      categoryIds: {'c2', 'c1'},
    );

    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(SearchFilters(budgetId: 'b1', text: 'кофе')));
    expect(a.toString(), isNot(contains('кофе')));
  });

  test('% и _ в запросе - обычные символы, а не шаблон LIKE', () async {
    expect(found(await search('50%')), '18:Развлечения:400$nbsp₽');
    expect(found(await search('%')), '18:Развлечения:400$nbsp₽');
    expect(found(await search('_')), '2:Связь:149,90$nbsp₽');
    expect((await search(r'\')).count, 0);
    expect((await search('%%')).count, 0);
    expect(escapeLikePattern(r'50%_\'), r'50\%\_\\');
  });

  test('пустой текст - только фильтры: период, категории', () async {
    final all = await search('');
    final cafeAndTransport = await search(
      '   ',
      from: october.firstDay,
      to: october.lastDay,
      categories: {categoryId('Кафе'), categoryId('Транспорт')},
    );

    expect(all.count, h.live.length);
    expect(all.total, Money.sum(h.live.map((e) => e.amount)));
    expect(cafeAndTransport.count, 11);
    expect(cafeAndTransport.total, const Money.rubles(4560));
    expect(cafeAndTransport.expenses.map(h.categoryOf).toSet(), {
      'Кафе',
      'Транспорт',
    });
  });

  test('текст вместе с периодом, категориями и бюджетом', () async {
    final firstHalf = await search(
      'кофе',
      from: october.firstDay,
      to: october.dayOf(15),
    );
    final onlyGroceries = await search(
      'кофе',
      categories: {categoryId('Продукты')},
    );
    final october640 = await search(
      '640',
      from: october.firstDay,
      to: october.lastDay,
    );
    final otherBudget = await search('кофе', budgetId: h.otherBudget.id);

    expect(firstHalf.count, 6);
    expect(found(onlyGroceries), '15:Продукты:420$nbsp₽');
    expect(found(october640), '19:Продукты:640$nbsp₽');
    expect(otherBudget.count, 1);
    expect(otherBudget.expenses.single.budgetId, h.otherBudget.id);
  });

  test('совпадает с правилом shared expenseMatches на всех тратах', () async {
    final names = h.categoryNames(h.budget);
    final ordered = [...h.live]
      ..sort((a, b) {
        final byDate = b.spentOn.compareTo(a.spentOn);
        if (byDate != 0) return byDate;
        final byCreated = b.createdAt.compareTo(a.createdAt);
        if (byCreated != 0) return byCreated;
        return a.id.compareTo(b.id);
      });
    const queries = [
      'кофе', 'КОФЕ', 'ёлка', 'Елка', 'кафе', 'про', 'пятёрочка', '640', //
      '64', '6', '0', '1', '149,9', '149,', '2,5', '50%', '_', 'тариф_', //
      'метро', 'с собой', 'нет такого', '1 450', '0640',
    ];

    for (final query in queries) {
      final result = await search(query);
      final expected = [
        for (final e in ordered)
          if (expenseMatches(
            query: query,
            comment: e.comment,
            categoryName: names[e.categoryId]!,
            amount: e.amount,
          ))
            e.id,
      ];
      expect(
        result.expenses.map((e) => e.id).toList(),
        expected,
        reason: query,
      );
      expect(result.count, expected.length, reason: query);
    }
  });

  test('реактивно: новая трата и переименование категории', () async {
    final coffee = Watcher(
      h.search.watchSearch(SearchFilters(budgetId: h.budget.id, text: 'кофе')),
    );
    final renamed = Watcher(
      h.search.watchSearch(
        SearchFilters(budgetId: h.budget.id, text: 'кофейня'),
      ),
    );
    addTearDown(() async {
      await coffee.cancel();
      await renamed.cancel();
    });
    expect((await coffee.next()).count, 7);
    expect((await renamed.next()).count, 0);

    await h.repo.expenses.create(
      budgetId: h.budget.id,
      categoryId: categoryId('Транспорт'),
      amount: const Money.rubles(300),
      spentOn: october.dayOf(20),
      comment: 'Кофе на вокзале',
    );
    final afterCreate = await coffee.next();
    expect(afterCreate.count, 8);
    expect(afterCreate.total, const Money.rubles(2400));
    expect(afterCreate.expenses.first.comment, 'Кофе на вокзале');
    expect((await renamed.next()).count, 0);

    await h.repo.categories.update(categoryId('Кафе'), name: 'Кофейня');
    final afterRename = await renamed.next();
    expect(afterRename.count, 7);
    expect(afterRename.total, const Money.rubles(2570));
  });
}
