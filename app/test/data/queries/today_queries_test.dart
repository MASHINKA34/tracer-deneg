import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/queries/today_queries.dart';
import 'package:shared/shared.dart';

import 'query_fixture.dart';

void main() {
  late QueryHarness h;
  late DriftTodayQueries queries;

  setUp(() async {
    h = QueryHarness();
    await h.seedMockup();
    queries = DriftTodayQueries(h.db);
  });

  tearDown(() => h.dispose());

  String row(Expense e) => '${h.categoryOf(e)} ${e.amount.format()}';

  test('19 октября: три траты бюджета, свежая первой (20:00, 18:40, '
      '09:15), трата другого бюджета не попадает', () async {
    final result = await queries.watchToday(h.budget.id, today).first;

    expect(result.expenses.map(row), [
      'Транспорт 250$nbsp₽',
      'Продукты 640$nbsp₽',
      'Кафе 210$nbsp₽',
    ]);
    expect(result.budgetHasExpenses, isTrue);
    expect(result.expenses.every((e) => e.budgetId == h.budget.id), isTrue);
  });

  test('4 октября только удалённая трата: сегодня пусто, но траты в бюджете '
      'есть', () async {
    final result = await queries
        .watchToday(h.budget.id, october.dayOf(4))
        .first;

    expect(result.expenses, isEmpty);
    expect(result.budgetHasExpenses, isTrue);
  });

  test('бюджет без трат и бюджет только с удалённой тратой — трат нет за всё '
      'время', () async {
    final empty = await h.repo.seedBudget(id: 'budget-empty');
    final deletedOnly = await h.repo.seedBudget(id: 'budget-deleted');
    await h.seedDeleted(deletedOnly, today);

    final none = await queries.watchToday(empty.id, today).first;
    final deleted = await queries.watchToday(deletedOnly.id, today).first;

    expect(none.expenses, isEmpty);
    expect(none.budgetHasExpenses, isFalse);
    expect(deleted.expenses, isEmpty);
    expect(deleted.budgetHasExpenses, isFalse);
  });

  test(
    'первая трата появляется сразу, после её удаления трат снова нет',
    () async {
      final empty = await h.repo.seedBudget(id: 'budget-first');
      final watcher = Watcher(queries.watchToday(empty.id, today));
      addTearDown(watcher.cancel);

      final before = await watcher.next();
      final created = await h.repo.expenses.create(
        budgetId: empty.id,
        categoryId: empty.byName('Кафе').id,
        amount: const Money.rubles(150),
        spentOn: today,
      );
      final added = await watcher.next();
      await h.repo.expenses.delete(created.id);
      final removed = await watcher.next();

      expect(before.budgetHasExpenses, isFalse);
      expect(added.expenses.map((e) => e.id), [created.id]);
      expect(added.budgetHasExpenses, isTrue);
      expect(removed.expenses, isEmpty);
      expect(removed.budgetHasExpenses, isFalse);
    },
  );

  test('трата не сегодня в пустом бюджете: сегодня пусто, траты в бюджете '
      'есть', () async {
    final b = await h.repo.seedBudget(id: 'budget-past');
    await h.seed(b, october, const [
      Spend(2, 'Дом', Money.rubles(300), '', '10:00'),
    ]);

    final result = await queries.watchToday(b.id, today).first;

    expect(result.expenses, isEmpty);
    expect(result.budgetHasExpenses, isTrue);
  });

  test('запрос в debug-логе [query] с бюджетом, днём и числом строк, без '
      'сумм и комментариев', () async {
    await queries.watchToday(h.budget.id, today).first;

    final lines = [
      for (final r in h.queryLogs(Level.FINE))
        if (r.message.startsWith('query today ')) r.message,
    ];
    expect(
      lines,
      contains(
        matches(
          RegExp(
            r'^query today budget=budget-main period=2026-10-19\.\.2026-10-19 '
            r'rows=3 trigger=listen in \d+ms$',
          ),
        ),
      ),
    );
    for (final line in lines) {
      expect(line, isNot(contains('Кофе')));
      expect(line, isNot(contains('640')));
    }
  });
}
