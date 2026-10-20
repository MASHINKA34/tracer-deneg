import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

import 'query_fixture.dart';

void main() {
  late QueryHarness h;

  setUp(() async {
    h = QueryHarness();
    await h.seedMockup();
  });

  tearDown(() => h.dispose());

  const latestSix = [
    'Пятёрочка',
    'Кофе с собой',
    'Кино 50% скидка',
    'ВкусВилл',
    'Обед с коллегами',
    'Метро',
  ];

  test(
    'шесть последних уникальных непустых комментариев, свежие первыми',
    () async {
      final comments = await h.search.watchRecentComments(h.budget.id).first;

      expect(comments, latestSix);
      expect(comments.toSet(), hasLength(6));
    },
  );

  test('без удалённых, пустых, из пробелов и чужого бюджета', () async {
    await h.seed(h.budget, october, const [
      Spend(19, 'Связь', Money.rubles(300), '   ', '23:30'),
    ]);

    final comments = await h.search.watchRecentComments(h.budget.id).first;

    expect(comments, latestSix);
    expect(comments, isNot(contains(deletedComment)));
    expect(comments, isNot(contains('Кофе из другого бюджета')));
  });

  test('чужой бюджет, пустой бюджет и свой лимит', () async {
    final other = await h.search.watchRecentComments(h.otherBudget.id).first;
    final empty = await h.search.watchRecentComments('budget-none').first;
    final two = await h.search.watchRecentComments(h.budget.id, limit: 2).first;

    expect(other, ['Кофе из другого бюджета']);
    expect(empty, isEmpty);
    expect(two, ['Пятёрочка', 'Кофе с собой']);
  });

  test('реактивно: повтор старого комментария поднимает его наверх без '
      'дубля', () async {
    final recent = Watcher(h.search.watchRecentComments(h.budget.id));
    addTearDown(recent.cancel);
    expect(await recent.next(), latestSix);

    final repeated = await h.repo.expenses.create(
      budgetId: h.budget.id,
      categoryId: h.budget.byName('Кафе').id,
      amount: const Money.rubles(900),
      spentOn: october.dayOf(20),
      comment: 'Обед с коллегами',
    );

    expect(await recent.next(), [
      'Обед с коллегами',
      'Пятёрочка',
      'Кофе с собой',
      'Кино 50% скидка',
      'ВкусВилл',
      'Метро',
    ]);

    await h.repo.expenses.delete(repeated.id);

    expect(await recent.next(), latestSix);
  });
}
