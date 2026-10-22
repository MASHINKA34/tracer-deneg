import 'package:drift/drift.dart' show BooleanExpressionOperators, Value;
import 'package:milionchik/data/current_user.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/repositories/categories_repository.dart';
import 'package:milionchik/data/repositories/expenses_repository.dart';
import 'package:milionchik/data/repositories/outbox_queue.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:milionchik/data/repositories/records.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';

const List<(String, int)> mockupCategoryCounts = [
  ('Продукты', 58),
  ('Кафе', 11),
  ('Транспорт', 27),
  ('Дом', 6),
  ('Здоровье', 3),
  ('Одежда', 2),
  ('Развлечения', 4),
  ('Связь', 2),
  ('Спорт', 1),
  ('Подарки', 0),
];

final class CategoriesFixture {
  CategoriesFixture(this.db, this.budgetId);

  final AppDatabase db;
  final String budgetId;

  CurrentUser get user => LocalPrefsCurrentUser(DriftPrefsRepository(db));

  CategoriesRepository get categories => DriftCategoriesRepository(
    db,
    currentUser: user,
    outbox: DriftOutboxQueue(db),
  );

  ExpensesRepository get expenses => DriftExpensesRepository(
    db,
    currentUser: user,
    outbox: DriftOutboxQueue(db),
  );

  Future<List<Category>> list() => categories.watchByBudget(budgetId).first;

  Future<Category> byName(String name) async =>
      (await list()).singleWhere((c) => c.name == name);

  Future<Category> other() async =>
      (await list()).singleWhere((c) => c.isSystem);

  Future<List<Expense>> expensesOf(String categoryId) async {
    final rows =
        await (db.select(db.expenses)..where(
              (e) => e.categoryId.equals(categoryId) & e.deletedAt.isNull(),
            ))
            .get();
    return [for (final r in rows) expenseFromRow(r)];
  }

  Future<void> addExpenses(
    String categoryId,
    int count, {
    int rubles = 100,
  }) async {
    for (var i = 0; i < count; i++) {
      await expenses.create(
        budgetId: budgetId,
        categoryId: categoryId,
        amount: Money.rubles(rubles + i),
        spentOn: LocalDate(2026, 10, 1 + i % 19),
      );
    }
  }

  static Future<CategoriesFixture> presets(AppDatabase db) async {
    final budget = await testBudgets(db).createLocalPersonal();
    return CategoriesFixture(db, budget.id);
  }

  static Future<CategoriesFixture> mockup(AppDatabase db) async {
    final fixture = await presets(db);
    final byName = {for (final c in await fixture.list()) c.name: c};
    for (final (i, (name, count)) in mockupCategoryCounts.indexed) {
      final category = byName[name]!;
      await (db.update(db.categories)..where((c) => c.id.equals(category.id)))
          .write(CategoriesCompanion(sortOrder: Value(i)));
      await fixture.addExpenses(category.id, count);
    }
    return fixture;
  }
}
