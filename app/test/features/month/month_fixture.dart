import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/data/current_user.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/dev_seed.dart';
import 'package:milionchik/data/repositories/categories_repository.dart';
import 'package:milionchik/data/repositories/expenses_repository.dart';
import 'package:milionchik/data/repositories/outbox_queue.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:milionchik/ui/catalog/demo_months.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';

Future<String> seedMockupOctober(AppDatabase db) async {
  final result = await DevSeed(
    db,
    currentUser: LocalPrefsCurrentUser(DriftPrefsRepository(db)),
  ).runIfRequested(flag: 'true', debugBuild: true);
  expect(result.status, DevSeedStatus.seeded);
  return (await testBudgets(db).watchAll().first).single.id;
}

Future<String> seedMockupJanuary(AppDatabase db) async {
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
  for (final MapEntry(key: day, value: rubles) in demoWinter.rubles.entries) {
    await expenses.create(
      budgetId: budget.id,
      categoryId: categories.first.id,
      amount: Money.rubles(rubles),
      spentOn: demoWinter.month.dayOf(day),
    );
  }
  return budget.id;
}
