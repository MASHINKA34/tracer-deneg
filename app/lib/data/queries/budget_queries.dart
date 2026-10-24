import 'package:drift/drift.dart';
import 'package:shared/shared.dart';

import '../db/app_database.dart';
import '../repositories/records.dart';
import 'query_runner.dart';

abstract interface class BudgetQueries {
  Stream<List<Expense>> watchRecentExpenses(
    String budgetId, {
    required int limit,
  });
}

final class DriftBudgetQueries implements BudgetQueries {
  DriftBudgetQueries(this._db, {Duration slowThreshold = slowQueryThreshold})
    : _runner = QueryRunner(_db, slowThreshold: slowThreshold);

  final AppDatabase _db;
  final QueryRunner _runner;

  $ExpensesTable get _e => _db.expenses;

  @override
  Stream<List<Expense>> watchRecentExpenses(
    String budgetId, {
    required int limit,
  }) {
    final query = _db.select(_e)
      ..where((e) => e.budgetId.equals(budgetId) & e.deletedAt.isNull())
      ..orderBy([
        (e) => OrderingTerm.desc(e.spentOn),
        (e) => OrderingTerm.desc(e.createdAt),
        (e) => OrderingTerm.asc(e.id),
      ])
      ..limit(limit);
    return _runner.watch(
      'recent expenses',
      'budget=$budgetId limit=$limit',
      tables: {_e},
      rows: (expenses) => expenses.length,
      run: () async => [for (final r in await query.get()) expenseFromRow(r)],
    );
  }
}
