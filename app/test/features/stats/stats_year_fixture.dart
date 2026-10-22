import 'package:milionchik/data/current_user.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/repositories/categories_repository.dart';
import 'package:milionchik/data/repositories/expenses_repository.dart';
import 'package:milionchik/data/repositories/outbox_queue.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';
import 'stats_fixture.dart';

const List<int> mockupYearMonths = [
  21400,
  19900,
  22100,
  17900,
  20750,
  23650,
  24300,
  22750,
  20300,
  18300,
];

const List<(String, int, int)> mockupYearCategories = [
  ('Кафе', 35900, 124),
  ('Спорт', 29000, 10),
  ('Транспорт', 24100, 268),
  ('Дом', 14800, 18),
  ('Здоровье', 11200, 22),
  ('Развлечения', 9650, 26),
  ('Связь', 8300, 14),
  ('Одежда', 6000, 3),
];

const String mockupYearRest = 'Продукты';

const int mockupYearRestCount = 212;

List<int> _split(int total, List<int> weights) {
  final sum = weights.fold(0, (a, b) => a + b);
  final parts = [for (final w in weights) total * w ~/ sum];
  final order = List.generate(weights.length, (i) => i)
    ..sort((a, b) {
      final ra = total * weights[a] % sum;
      final rb = total * weights[b] % sum;
      return ra != rb ? rb.compareTo(ra) : a.compareTo(b);
    });
  var left = total - parts.fold(0, (a, b) => a + b);
  for (final i in order) {
    if (left == 0) break;
    parts[i]++;
    left--;
  }
  return parts;
}

List<int> _activeMonths(int count, int months) {
  if (count >= months) return List.generate(months, (i) => i);
  return [for (var k = 0; k < count; k++) k * months ~/ count];
}

List<StatsSpend> mockupYearSpends({
  int year = 2026,
  List<int> months = mockupYearMonths,
  int lastDay = 19,
}) {
  final n = months.length;
  final byMonth = List.generate(n, (_) => <(String, int, int)>[]);
  final others = List.filled(n, 0);
  for (final (name, total, count) in mockupYearCategories) {
    final active = _activeMonths(count, n);
    final amounts = _split(total, [for (final m in active) months[m]]);
    final counts = _split(count, List.filled(active.length, 1));
    for (final (i, m) in active.indexed) {
      byMonth[m].add((name, amounts[i], counts[i]));
      others[m] += amounts[i];
    }
  }
  final restCounts = _split(mockupYearRestCount, List.filled(n, 1));
  for (var m = 0; m < n; m++) {
    byMonth[m].insert(0, (
      mockupYearRest,
      months[m] - others[m],
      restCounts[m],
    ));
  }
  final spends = <StatsSpend>[];
  for (var m = 0; m < n; m++) {
    final days = m == n - 1 ? lastDay : 28;
    var k = 0;
    for (final (name, amount, count) in byMonth[m]) {
      if (count == 0) continue;
      final parts = _split(amount, List.filled(count, 1));
      for (final part in parts) {
        spends.add((LocalDate(year, m + 1, 1 + k % days), name, part));
        k++;
      }
    }
  }
  return spends;
}

Future<StatsBudget> seedMockupYear(
  AppDatabase db, {
  List<StatsSpend>? spends,
}) async {
  final user = LocalPrefsCurrentUser(DriftPrefsRepository(db));
  final outbox = DriftOutboxQueue(db);
  final budget = await testBudgets(db).createLocalPersonal();
  final categories = await DriftCategoriesRepository(
    db,
    currentUser: user,
    outbox: outbox,
  ).watchByBudget(budget.id).first;
  final ids = {for (final c in categories) c.name: c.id};
  final author = await user.userId();
  final at = DateTime.utc(2026, 10, 19, 15, 40);
  await DriftExpensesRepository(
    db,
    currentUser: user,
    outbox: outbox,
  ).applyFromServer([
    for (final (day, category, rubles) in spends ?? mockupYearSpends())
      Expense(
        id: newId(),
        budgetId: budget.id,
        categoryId: ids[category]!,
        amount: Money.rubles(rubles),
        spentOn: day,
        authorId: author,
        createdAt: at,
        updatedAt: at,
        updatedBy: author,
      ),
  ]);
  return StatsBudget(budget.id, ids);
}
