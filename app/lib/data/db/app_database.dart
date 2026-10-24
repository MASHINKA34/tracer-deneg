import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared/shared.dart';

import 'converters.dart';
import 'migrations.dart';
import 'tables.dart';

part 'app_database.g.dart';

final _log = Logger('db');

const String databaseFileName = 'milionchik.sqlite';

const int databaseBusyTimeoutMs = 5000;

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

  OpeningDetails? _opening;

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: _createSchema,
    onUpgrade: _upgradeSchema,
    beforeOpen: _beforeOpen,
  );

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

  Future<void> _upgradeSchema(Migrator m, int from, int to) =>
      migrateSchema(m, from: from, to: to);

  Future<void> _beforeOpen(OpeningDetails details) async {
    _opening = details;
    await customStatement('PRAGMA busy_timeout = $databaseBusyTimeoutMs');
    _log.fine(
      'database before open version=${details.versionNow} '
      'previous=${details.versionBefore ?? '-'} created=${details.wasCreated}',
    );
  }
}

Future<String> _supportDirectory() async =>
    (await getApplicationSupportDirectory()).path;

Future<AppDatabase> openAppDatabase({
  Future<String> Function()? directory,
  Future<String?> Function()? tempDirectory,
}) async {
  final sw = Stopwatch()..start();
  var path = '?';
  AppDatabase? db;
  try {
    final dir = await (directory ?? _supportDirectory)();
    path = '$dir/$databaseFileName';
    _log.info('opening database path=$path');
    final opened = db = AppDatabase(
      driftDatabase(
        name: 'milionchik',
        native: DriftNativeOptions(
          databasePath: () async => path,
          tempDirectoryPath: tempDirectory,
        ),
      ),
    );
    final sqlite = await opened
        .customSelect('SELECT sqlite_version() AS version')
        .getSingle();
    _log.info(
      'database opened path=$path schema=${opened.schemaVersion} '
      'created=${opened._opening?.wasCreated} '
      'sqlite=${sqlite.read<String>('version')} '
      'in ${sw.elapsedMilliseconds}ms',
    );
    final busy = await opened.customSelect('PRAGMA busy_timeout').getSingle();
    final journal = await opened
        .customSelect('PRAGMA journal_mode')
        .getSingle();
    _log.fine(
      'database connection busyTimeout=${busy.data.values.first}ms '
      'journal=${journal.data.values.first}: the app and a background task '
      'open separate connections, a write waits for the other one instead of '
      'failing as locked',
    );
    return opened;
  } catch (e, st) {
    _log.severe(
      'database open failed path=$path after ${sw.elapsedMilliseconds}ms: '
      '${describeError(e)}',
      e,
      st,
    );
    if (db != null) {
      try {
        await db.close();
      } catch (closeError, closeStack) {
        _log.warning(
          'database close after failed open failed path=$path: '
          '${describeError(closeError)}',
          closeError,
          closeStack,
        );
      }
    }
    rethrow;
  }
}
