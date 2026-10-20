import 'package:drift/drift.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../db/app_database.dart';
import 'records.dart';

final _log = Logger('repo');

abstract interface class MembersRepository {
  Stream<List<BudgetMember>> watchByBudget(String budgetId);

  Stream<List<MemberProfile>> watchProfiles();

  Stream<MemberProfile?> watchProfile(String userId);

  Future<void> applyMembersFromServer(Iterable<BudgetMember> members);

  Future<void> applyProfilesFromServer(Iterable<MemberProfile> profiles);
}

final class DriftMembersRepository implements MembersRepository {
  DriftMembersRepository(this._db);

  final AppDatabase _db;

  Stream<T> _watch<T>(String entity, String query, Stream<T> stream) =>
      stream.handleError((Object e, StackTrace st) {
        _log.severe('$entity watch failed $query: ${describeError(e)}', e, st);
        Error.throwWithStackTrace(e, st);
      });

  @override
  Stream<List<BudgetMember>> watchByBudget(String budgetId) => _watch(
    'member',
    'budget=$budgetId',
    (_db.select(_db.budgetMembers)
          ..where(
            (m) =>
                m.budgetId.equals(budgetId) &
                m.leftAt.isNull() &
                m.deletedAt.isNull(),
          )
          ..orderBy([
            (m) => OrderingTerm.asc(m.joinedAt),
            (m) => OrderingTerm.asc(m.userId),
          ]))
        .watch()
        .map((rows) => [for (final r in rows) memberFromRow(r)]),
  );

  @override
  Stream<List<MemberProfile>> watchProfiles() => _watch(
    'profile',
    'all',
    (_db.select(_db.memberProfiles)
          ..orderBy([(p) => OrderingTerm.asc(p.userId)]))
        .watch()
        .map((rows) => [for (final r in rows) profileFromRow(r)]),
  );

  @override
  Stream<MemberProfile?> watchProfile(String userId) => _watch(
    'profile',
    'user=$userId',
    (_db.select(_db.memberProfiles)..where((p) => p.userId.equals(userId)))
        .watchSingleOrNull()
        .map((r) => r == null ? null : profileFromRow(r)),
  );

  Future<void> _apply(
    String entity,
    int count,
    void Function(Batch b) write,
  ) async {
    final sw = Stopwatch()..start();
    try {
      await _db.transaction(() => _db.batch(write));
      _log.fine('$entity apply count=$count in ${sw.elapsedMilliseconds}ms');
    } catch (e, st) {
      _log.severe(
        '$entity apply failed count=$count after ${sw.elapsedMilliseconds}ms, '
        'transaction rolled back: ${describeError(e)}',
        e,
        st,
      );
      rethrow;
    }
  }

  @override
  Future<void> applyMembersFromServer(Iterable<BudgetMember> members) {
    final rows = [for (final m in members) memberToRow(m)];
    return _apply(
      'member',
      rows.length,
      (b) => b.insertAllOnConflictUpdate(_db.budgetMembers, rows),
    );
  }

  @override
  Future<void> applyProfilesFromServer(Iterable<MemberProfile> profiles) {
    final rows = [for (final p in profiles) profileToRow(p)];
    return _apply(
      'profile',
      rows.length,
      (b) => b.insertAllOnConflictUpdate(_db.memberProfiles, rows),
    );
  }
}
