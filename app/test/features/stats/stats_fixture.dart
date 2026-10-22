import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/data/current_user.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/repositories/categories_repository.dart';
import 'package:milionchik/data/repositories/expenses_repository.dart';
import 'package:milionchik/data/repositories/outbox_queue.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:milionchik/features/stats/donut_chart.dart';
import 'package:milionchik/ui/components/stat_row.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';
import '../shell/shell_harness.dart';

typedef StatsSpend = (LocalDate day, String category, int rubles);

final class StatsBudget {
  const StatsBudget(this.id, this.categoryIds);

  final String id;
  final Map<String, String> categoryIds;
}

Future<StatsBudget> seedStatsBudget(
  AppDatabase db, [
  List<StatsSpend> spends = const [],
]) async {
  final user = LocalPrefsCurrentUser(DriftPrefsRepository(db));
  final outbox = DriftOutboxQueue(db);
  final budget = await testBudgets(db).createLocalPersonal();
  final categories = await DriftCategoriesRepository(
    db,
    currentUser: user,
    outbox: outbox,
  ).watchByBudget(budget.id).first;
  final ids = {for (final c in categories) c.name: c.id};
  final expenses = DriftExpensesRepository(
    db,
    currentUser: user,
    outbox: outbox,
  );
  for (final (day, category, rubles) in spends) {
    await expenses.create(
      budgetId: budget.id,
      categoryId: ids[category]!,
      amount: Money.rubles(rubles),
      spentOn: day,
    );
  }
  return StatsBudget(budget.id, ids);
}

Future<void> openStatsTab(ShellHarness h) async {
  await h.tapTab('Статистика');
  await h.tester.pumpAndSettle();
}

DonutChart donutOf(WidgetTester tester) =>
    tester.widget<DonutChart>(find.byType(DonutChart));

List<String> statRowNames(WidgetTester tester) => [
  for (final row in tester.widgetList<StatRow>(find.byType(StatRow))) row.name,
];
