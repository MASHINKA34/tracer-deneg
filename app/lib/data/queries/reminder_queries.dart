import 'package:drift/drift.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../db/app_database.dart';
import '../db/redact_db_error.dart';
import 'query_runner.dart';

final _log = Logger('query');

abstract interface class ReminderQueries {
  Future<bool> hasOwnExpenseOn(LocalDate day, {required String userId});
}

final class DriftReminderQueries implements ReminderQueries {
  DriftReminderQueries(this._db, {this.slowThreshold = slowQueryThreshold});

  final AppDatabase _db;
  final Duration slowThreshold;

  @override
  Future<bool> hasOwnExpenseOn(LocalDate day, {required String userId}) async {
    final sw = Stopwatch()..start();
    final e = _db.expenses;
    final query = _db.selectOnly(e)
      ..addColumns([e.id])
      ..where(
        e.authorId.equals(userId) &
            e.deletedAt.isNull() &
            e.recurringId.isNull() &
            e.spentOn.equalsValue(day),
      )
      ..limit(1);
    try {
      final found = await query.getSingleOrNull() != null;
      final elapsed = sw.elapsed;
      _log.log(
        elapsed > slowThreshold ? Level.WARNING : Level.FINE,
        'query own-expense-on${elapsed > slowThreshold ? ' slow' : ''} '
        'day=$day userId=$userId found=$found in ${elapsed.inMilliseconds}ms',
      );
      return found;
    } catch (e, st) {
      final error = redactDbError(e);
      _log.severe(
        'query own-expense-on failed day=$day userId=$userId '
        'after ${sw.elapsedMilliseconds}ms: ${describeError(error)}',
        error,
        st,
      );
      rethrow;
    }
  }
}
