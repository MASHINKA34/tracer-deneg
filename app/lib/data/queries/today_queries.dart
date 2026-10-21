import 'package:drift/drift.dart';
import 'package:shared/shared.dart';

import '../db/app_database.dart';
import '../repositories/records.dart';
import 'query_runner.dart';

final class TodayExpenses {
  const TodayExpenses({
    required this.expenses,
    required this.budgetHasExpenses,
  });

  final List<Expense> expenses;
  final bool budgetHasExpenses;
}

abstract interface class TodayQueries {
  Stream<TodayExpenses> watchToday(String budgetId, LocalDate day);
}

final class DriftTodayQueries implements TodayQueries {
  DriftTodayQueries(this._db, {Duration slowThreshold = slowQueryThreshold})
    : _runner = QueryRunner(_db, slowThreshold: slowThreshold);

  final AppDatabase _db;
  final QueryRunner _runner;

  $ExpensesTable get _e => _db.expenses;

  @override
  Stream<TodayExpenses> watchToday(String budgetId, LocalDate day) {
    final today = _db.select(_e)
      ..where(
        (e) =>
            e.budgetId.equals(budgetId) &
            e.deletedAt.isNull() &
            e.spentOn.equalsValue(day),
      )
      ..orderBy([
        (e) => OrderingTerm.desc(e.createdAt),
        (e) => OrderingTerm.desc(e.id),
      ]);
    final any = _db.selectOnly(_e)
      ..addColumns([_e.id])
      ..where(_e.budgetId.equals(budgetId) & _e.deletedAt.isNull())
      ..limit(1);
    return _runner.watch(
      'today',
      'budget=$budgetId period=${describePeriod(day, day)}',
      tables: {_e},
      rows: (result) => result.expenses.length,
      run: () async {
        final expenses = [for (final r in await today.get()) expenseFromRow(r)];
        return TodayExpenses(
          expenses: expenses,
          budgetHasExpenses:
              expenses.isNotEmpty || await any.getSingleOrNull() != null,
        );
      },
    );
  }
}
