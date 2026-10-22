import 'package:drift/drift.dart';
import 'package:shared/shared.dart';

import '../db/app_database.dart';
import '../repositories/records.dart';
import 'query_runner.dart';

abstract interface class RecurringQueries {
  Stream<Map<String, Expense>> watchMonthCharges(
    String budgetId,
    YearMonth month,
  );
}

final class DriftRecurringQueries implements RecurringQueries {
  DriftRecurringQueries(this._db, {Duration slowThreshold = slowQueryThreshold})
    : _runner = QueryRunner(_db, slowThreshold: slowThreshold);

  final AppDatabase _db;
  final QueryRunner _runner;

  $ExpensesTable get _e => _db.expenses;

  $RecurringRulesTable get _r => _db.recurringRules;

  @override
  Stream<Map<String, Expense>> watchMonthCharges(
    String budgetId,
    YearMonth month,
  ) {
    final query =
        _db.select(_e).join([innerJoin(_r, _r.id.equalsExp(_e.recurringId))])
          ..where(
            _r.budgetId.equals(budgetId) &
                _e.deletedAt.isNull() &
                _e.recurringMonth.equalsValue(month),
          )
          ..orderBy([OrderingTerm.asc(_e.spentOn), OrderingTerm.asc(_e.id)]);
    return _runner.watch(
      'recurring charges',
      'budget=$budgetId month=$month',
      tables: {_e, _r},
      rows: (result) => result.length,
      run: () async {
        final charges = <String, Expense>{};
        for (final row in await query.get()) {
          final expense = expenseFromRow(row.readTable(_e));
          charges.putIfAbsent(expense.recurringId!, () => expense);
        }
        return charges;
      },
    );
  }
}
