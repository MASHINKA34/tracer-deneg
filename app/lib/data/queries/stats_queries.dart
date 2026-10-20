import 'package:drift/drift.dart';
import 'package:shared/shared.dart';

import '../db/app_database.dart';
import '../db/converters.dart';
import 'query_runner.dart';

final class CategoryTotal {
  const CategoryTotal({
    required this.categoryId,
    required this.total,
    required this.count,
  });

  final String categoryId;
  final Money total;
  final int count;

  @override
  bool operator ==(Object other) =>
      other is CategoryTotal &&
      other.categoryId == categoryId &&
      other.total == total &&
      other.count == count;

  @override
  int get hashCode => Object.hash(categoryId, total, count);

  @override
  String toString() => 'CategoryTotal($categoryId, $total, count=$count)';
}

abstract interface class StatsQueries {
  Stream<List<CategoryTotal>> watchCategoryTotals(
    String budgetId, {
    required LocalDate from,
    required LocalDate to,
  });

  Stream<List<Money>> watchMonthTotals(String budgetId, int year);
}

final class DriftStatsQueries implements StatsQueries {
  DriftStatsQueries(this._db, {Duration slowThreshold = slowQueryThreshold})
    : _runner = QueryRunner(_db, slowThreshold: slowThreshold);

  static const LocalDateConverter _dates = LocalDateConverter();

  final AppDatabase _db;
  final QueryRunner _runner;

  $ExpensesTable get _e => _db.expenses;

  Expression<bool> _live(String budgetId, LocalDate from, LocalDate to) =>
      _e.budgetId.equals(budgetId) &
      _e.deletedAt.isNull() &
      _e.spentOn.isBetweenValues(_dates.toSql(from), _dates.toSql(to));

  String _params(String budgetId, LocalDate from, LocalDate to) =>
      'budget=$budgetId period=${describePeriod(from, to)}';

  @override
  Stream<List<CategoryTotal>> watchCategoryTotals(
    String budgetId, {
    required LocalDate from,
    required LocalDate to,
  }) {
    final c = _db.categories;
    final total = _e.amountKopecks.sum();
    final count = countAll();
    final query = _db.selectOnly(_e)
      ..join([
        leftOuterJoin(c, c.id.equalsExp(_e.categoryId), useColumns: false),
      ])
      ..addColumns([_e.categoryId, total, count])
      ..where(_live(budgetId, from, to))
      ..groupBy([_e.categoryId])
      ..orderBy([
        OrderingTerm.desc(total),
        OrderingTerm.asc(c.sortOrder),
        OrderingTerm.asc(_e.categoryId),
      ]);
    return _runner.watch(
      'category-totals',
      _params(budgetId, from, to),
      tables: {_e, c},
      rows: (totals) => totals.length,
      run: () async => [
        for (final row in await query.get())
          CategoryTotal(
            categoryId: row.read(_e.categoryId)!,
            total: Money(row.read(total)!),
            count: row.read(count)!,
          ),
      ],
    );
  }

  @override
  Stream<List<Money>> watchMonthTotals(String budgetId, int year) {
    final from = LocalDate(year, 1, 1);
    final to = LocalDate(year, 12, 31);
    final month = _e.spentOn.substr(1, 7);
    final total = _e.amountKopecks.sum();
    final query = _db.selectOnly(_e)
      ..addColumns([month, total])
      ..where(_live(budgetId, from, to))
      ..groupBy([month]);
    return _runner.watch(
      'month-totals',
      _params(budgetId, from, to),
      tables: {_e},
      rows: (totals) => totals.where((m) => !m.isZero).length,
      run: () async {
        final totals = List<Money>.filled(12, Money.zero);
        for (final row in await query.get()) {
          final key = YearMonth.parse(row.read(month)!);
          totals[key.month - 1] = Money(row.read(total)!);
        }
        return List.unmodifiable(totals);
      },
    );
  }
}
