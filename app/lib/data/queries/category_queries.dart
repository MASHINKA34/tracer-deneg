import 'package:drift/drift.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../db/app_database.dart';
import '../db/redact_db_error.dart';
import 'query_runner.dart';

final _log = Logger('query');

abstract interface class CategoryQueries {
  Stream<Map<String, int>> watchExpenseCounts(String budgetId);

  Future<int> countExpenses(String categoryId);
}

final class DriftCategoryQueries implements CategoryQueries {
  DriftCategoryQueries(this._db, {Duration slowThreshold = slowQueryThreshold})
    : _runner = QueryRunner(_db, slowThreshold: slowThreshold);

  final AppDatabase _db;
  final QueryRunner _runner;

  @override
  Stream<Map<String, int>> watchExpenseCounts(String budgetId) {
    final e = _db.expenses;
    final c = _db.categories;
    final count = countAll();
    final query = _db.selectOnly(e)
      ..join([innerJoin(c, c.id.equalsExp(e.categoryId), useColumns: false)])
      ..addColumns([e.categoryId, count])
      ..where(c.budgetId.equals(budgetId) & e.deletedAt.isNull())
      ..groupBy([e.categoryId]);
    return _runner.watch(
      'category-expense-counts',
      'budget=$budgetId period=${describePeriod(null, null)}',
      tables: {e, c},
      rows: (counts) => counts.length,
      run: () async => Map.unmodifiable({
        for (final row in await query.get())
          row.read(e.categoryId)!: row.read(count)!,
      }),
    );
  }

  @override
  Future<int> countExpenses(String categoryId) async {
    final sw = Stopwatch()..start();
    final e = _db.expenses;
    final count = countAll();
    final query = _db.selectOnly(e)
      ..addColumns([count])
      ..where(e.categoryId.equals(categoryId) & e.deletedAt.isNull());
    try {
      final result = (await query.getSingle()).read(count)!;
      _log.fine(
        'query category-expense-count category=$categoryId count=$result '
        'in ${sw.elapsedMilliseconds}ms',
      );
      return result;
    } catch (error, st) {
      final redacted = redactDbError(error);
      _log.severe(
        'query category-expense-count failed category=$categoryId after '
        '${sw.elapsedMilliseconds}ms: ${describeError(redacted)}',
        redacted,
        st,
      );
      rethrow;
    }
  }
}
