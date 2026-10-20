import 'package:drift/drift.dart';
import 'package:shared/shared.dart';

import '../db/app_database.dart';
import '../db/converters.dart';
import '../repositories/records.dart';
import 'query_runner.dart';

abstract interface class MonthQueries {
  Stream<Map<int, Money>> watchDayTotals(String budgetId, YearMonth month);

  Stream<Money> watchMonthTotal(String budgetId, YearMonth month);

  Stream<List<Expense>> watchDayExpenses(String budgetId, LocalDate day);
}

final class DriftMonthQueries implements MonthQueries {
  DriftMonthQueries(this._db, {Duration slowThreshold = slowQueryThreshold})
    : _runner = QueryRunner(_db, slowThreshold: slowThreshold);

  static const LocalDateConverter _dates = LocalDateConverter();

  final AppDatabase _db;
  final QueryRunner _runner;

  $ExpensesTable get _e => _db.expenses;

  Expression<bool> _liveInMonth(String budgetId, YearMonth month) =>
      _e.budgetId.equals(budgetId) &
      _e.deletedAt.isNull() &
      _e.spentOn.isBetweenValues(
        _dates.toSql(month.firstDay),
        _dates.toSql(month.lastDay),
      );

  String _params(String budgetId, LocalDate from, LocalDate to) =>
      'budget=$budgetId period=${describePeriod(from, to)}';

  @override
  Stream<Map<int, Money>> watchDayTotals(String budgetId, YearMonth month) {
    final total = _e.amountKopecks.sum();
    final query = _db.selectOnly(_e)
      ..addColumns([_e.spentOn, total])
      ..where(_liveInMonth(budgetId, month))
      ..groupBy([_e.spentOn]);
    return _runner.watch(
      'day-totals',
      _params(budgetId, month.firstDay, month.lastDay),
      tables: {_e},
      rows: (totals) => totals.length,
      run: () async => {
        for (final row in await query.get())
          row.readWithConverter<LocalDate, String>(_e.spentOn)!.day: Money(
            row.read(total)!,
          ),
      },
    );
  }

  @override
  Stream<Money> watchMonthTotal(String budgetId, YearMonth month) {
    final total = _e.amountKopecks.sum();
    final query = _db.selectOnly(_e)
      ..addColumns([total])
      ..where(_liveInMonth(budgetId, month));
    return _runner.watch(
      'month-total',
      _params(budgetId, month.firstDay, month.lastDay),
      tables: {_e},
      rows: (_) => 1,
      run: () async => Money((await query.getSingle()).read(total) ?? 0),
    );
  }

  @override
  Stream<List<Expense>> watchDayExpenses(String budgetId, LocalDate day) {
    final query = _db.select(_e)
      ..where(
        (e) =>
            e.budgetId.equals(budgetId) &
            e.deletedAt.isNull() &
            e.spentOn.equalsValue(day),
      )
      ..orderBy([
        (e) => OrderingTerm.asc(e.createdAt),
        (e) => OrderingTerm.asc(e.id),
      ]);
    return _runner.watch(
      'day-expenses',
      _params(budgetId, day, day),
      tables: {_e},
      rows: (expenses) => expenses.length,
      run: () async => [for (final r in await query.get()) expenseFromRow(r)],
    );
  }
}
