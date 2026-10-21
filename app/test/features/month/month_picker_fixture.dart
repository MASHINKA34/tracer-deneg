import 'package:milionchik/data/current_user.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/repositories/categories_repository.dart';
import 'package:milionchik/data/repositories/expenses_repository.dart';
import 'package:milionchik/data/repositories/outbox_queue.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:milionchik/ui/catalog/demo_months.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';

const Map<int, Map<int, int>> mockupYearRubles = {
  1: {10: 21260},
  2: {10: 19740},
  3: {10: 22020},
  4: {10: 17850},
  5: {10: 20880},
  6: {10: 23540},
  7: {10: 24300},
  8: {10: 22780},
  9: {12: 20400, 25: 100},
};

const List<double> mockupBarHeights = [
  56,
  52,
  58,
  47,
  55,
  62,
  64,
  60,
  54,
  48,
  0,
  0,
];

Future<String> seedMockupYear(AppDatabase db) async {
  final user = LocalPrefsCurrentUser(DriftPrefsRepository(db));
  final outbox = DriftOutboxQueue(db);
  final budget = await testBudgets(db).createLocalPersonal();
  final categories = await DriftCategoriesRepository(
    db,
    currentUser: user,
    outbox: outbox,
  ).watchByBudget(budget.id).first;
  final expenses = DriftExpensesRepository(
    db,
    currentUser: user,
    outbox: outbox,
  );
  final year = <int, Map<int, int>>{...mockupYearRubles, 10: demoAutumn.rubles};
  for (final MapEntry(key: month, value: days) in year.entries) {
    for (final MapEntry(key: day, value: rubles) in days.entries) {
      await expenses.create(
        budgetId: budget.id,
        categoryId: categories.first.id,
        amount: Money.rubles(rubles),
        spentOn: LocalDate(2026, month, day),
      );
    }
  }
  return budget.id;
}
