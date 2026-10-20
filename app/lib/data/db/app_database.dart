import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import 'converters.dart';
import 'tables.dart';

part 'app_database.g.dart';

final _log = Logger('db');

@DriftDatabase(
  tables: [
    Budgets,
    BudgetMembers,
    Categories,
    Expenses,
    RecurringRules,
    MemberProfiles,
    Outbox,
    SyncStates,
    LocalPrefs,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  AppDatabase.memory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration =>
      MigrationStrategy(onCreate: _createSchema, beforeOpen: _beforeOpen);

  Future<void> _createSchema(Migrator m) async {
    final sw = Stopwatch()..start();
    await m.createAll();
    await into(syncStates).insert(const SyncStatesCompanion(id: Value(0)));
    final tables = allTables.map((t) => t.actualTableName).join(',');
    final indexes = allSchemaEntities
        .whereType<Index>()
        .map((i) => i.entityName)
        .join(',');
    _log.info(
      'schema created version=$schemaVersion tables=$tables '
      'indexes=$indexes in ${sw.elapsedMilliseconds}ms',
    );
  }

  Future<void> _beforeOpen(OpeningDetails details) async {
    _log.fine(
      'database before open version=${details.versionNow} '
      'previous=${details.versionBefore ?? '-'} created=${details.wasCreated}',
    );
  }
}
