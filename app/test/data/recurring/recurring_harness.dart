import 'package:drift/drift.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/data/recurring_service.dart';
import 'package:milionchik/data/repositories/records.dart';
import 'package:shared/shared.dart';

import '../repositories/repository_harness.dart';

export '../repositories/repository_harness.dart';

const String internetTitle = 'Интернет';

final class RecurringHarness {
  RecurringHarness() : repo = RepositoryHarness();

  final RepositoryHarness repo;
  late final SeededBudget budget;

  LocalDate today = LocalDate(2026, 10, 22);

  Clock get clock =>
      Clock(now: () => DateTime(today.year, today.month, today.day, 9, 30));

  late final RecurringService service = newService();

  RecurringService newService() => RecurringService(
    repo.db,
    expenses: repo.expenses,
    recurring: repo.recurring,
    clock: clock,
  );

  Future<RecurringHarness> seed() async {
    budget = await repo.seedBudget();
    return this;
  }

  Future<RecurringRule> rule({
    int day = 24,
    required YearMonth from,
    Money amount = const Money.rubles(650),
    String title = internetTitle,
  }) => repo.recurring.create(
    budgetId: budget.id,
    categoryId: budget.byName('Связь').id,
    title: title,
    amount: amount,
    dayOfMonth: day,
    startMonth: from,
  );

  Future<RecurringRunResult> run([
    RecurringRunReason reason = RecurringRunReason.startup,
  ]) => service.run(reason);

  Future<List<Expense>> expensesOf(String ruleId) async {
    final rows =
        await (repo.db.select(repo.db.expenses)
              ..where((e) => e.recurringId.equals(ruleId))
              ..orderBy([(e) => OrderingTerm.asc(e.recurringMonth)]))
            .get();
    return [for (final r in rows) expenseFromRow(r)];
  }

  Future<int> expenseCount() => repo.db.expenses.count().getSingle();

  List<LogRecord> logs(String logger, [Level level = Level.ALL]) => [
    for (final r in repo.records)
      if (r.loggerName == logger && r.level >= level) r,
  ];

  List<String> lines(String logger, [Level level = Level.ALL]) => [
    for (final r in logs(logger, level)) formatLogRecord(r),
  ];

  Future<void> dispose() => repo.dispose();
}
