import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/queries/category_queries.dart';
import 'package:shared/shared.dart';

import '../../features/categories/categories_fixture.dart';
import '../../support/app_scope.dart';

void main() {
  test('число трат по категориям бюджета за всё время: как в макете 44:4792, '
      '«Подарки» без трат и «Другое» не попадают в ответ', () async {
    final db = openTestDatabase();
    final f = await CategoriesFixture.mockup(db);

    final counts = await DriftCategoryQueries(db)
        .watchExpenseCounts(f.budgetId)
        .first;

    final byName = {for (final c in await f.list()) c.name: c.id};
    expect(counts, {
      for (final (name, count) in mockupCategoryCounts)
        if (count > 0) byName[name]!: count,
    });
    expect(counts.containsKey(byName['Подарки']), isFalse);
    expect(counts.containsKey((await f.other()).id), isFalse);
  });

  test('удалённые траты и траты другого бюджета не считаются; поток '
      'обновляется после новой траты и после удаления категории', () async {
    final db = openTestDatabase();
    final f = await CategoriesFixture.presets(db);
    final cafe = await f.byName('Кафе');
    final other = await f.other();
    await f.addExpenses(cafe.id, 2);
    final gone = await f.expenses.create(
      budgetId: f.budgetId,
      categoryId: cafe.id,
      amount: const Money.rubles(1),
      spentOn: LocalDate(2026, 10, 3),
    );
    await f.expenses.delete(gone.id);

    final at = DateTime.utc(2026, 10, 1);
    var n = 0;
    await testBudgets(db).applyFromServer([
      Budget(
        id: 'shared-1',
        kind: BudgetKind.shared,
        name: 'Семья',
        emoji: '🏡',
        ownerId: 'u2',
        createdAt: at,
        updatedAt: at,
        updatedBy: 'u2',
      ),
    ]);
    final sharedCategories = buildPresetCategories(
      budgetId: 'shared-1',
      updatedBy: 'u2',
      now: at,
      newId: () => 'shared-cat-${n++}',
    );
    await f.categories.applyFromServer(sharedCategories);
    final sharedCafe = sharedCategories.singleWhere((c) => c.name == 'Кафе');
    await f.expenses.create(
      budgetId: 'shared-1',
      categoryId: sharedCafe.id,
      amount: const Money.rubles(7),
      spentOn: LocalDate(2026, 10, 3),
    );

    final values = <Map<String, int>>[];
    final sub = DriftCategoryQueries(db)
        .watchExpenseCounts(f.budgetId)
        .listen(values.add);
    addTearDown(sub.cancel);
    Future<Map<String, int>> next(int length) async {
      for (var i = 0; i < 100 && values.length < length; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      return values.last;
    }

    expect(await next(1), {cafe.id: 2});
    await f.addExpenses(cafe.id, 1);
    expect(await next(2), {cafe.id: 3});
    await f.categories.delete(cafe.id);
    expect(await next(3), {other.id: 3});
  });

  test('в debug-логе query имя запроса, бюджет, число строк и мс', () async {
    final db = openTestDatabase();
    final f = await CategoriesFixture.presets(db);
    await f.addExpenses((await f.byName('Дом')).id, 4);
    final records = <LogRecord>[];
    final previous = Logger.root.level;
    Logger.root.level = Level.ALL;
    final logs = Logger.root.onRecord.listen(records.add);
    addTearDown(() {
      unawaited(logs.cancel());
      Logger.root.level = previous;
    });

    await DriftCategoryQueries(db).watchExpenseCounts(f.budgetId).first;

    expect(
      records.where((r) => r.loggerName == 'query').map((r) => r.message),
      contains(
        matches(
          'query category-expense-counts budget=${f.budgetId} period=all '
          r'rows=1 trigger=listen in \d+ms$',
        ),
      ),
    );
  });
}
