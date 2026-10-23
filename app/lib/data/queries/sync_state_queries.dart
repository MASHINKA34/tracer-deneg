import '../db/app_database.dart';
import 'query_runner.dart';

abstract interface class SyncStateQueries {
  Stream<DateTime?> watchLastSyncAt();
}

final class DriftSyncStateQueries implements SyncStateQueries {
  DriftSyncStateQueries(this._db, {Duration slowThreshold = slowQueryThreshold})
    : _runner = QueryRunner(_db, slowThreshold: slowThreshold);

  final AppDatabase _db;
  final QueryRunner _runner;

  @override
  Stream<DateTime?> watchLastSyncAt() {
    final s = _db.syncStates;
    final query = _db.select(s)..where((row) => row.id.equals(0));
    return _runner.watch(
      'last-sync-at',
      'row=0',
      tables: {s},
      rows: (at) => at == null ? 0 : 1,
      run: () async => (await query.getSingleOrNull())?.lastSyncAt,
    );
  }
}
