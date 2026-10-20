import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/db/migrations.dart';

import 'app_database/generated/schema.dart';

class _StepsDatabase extends AppDatabase {
  _StepsDatabase(super.executor, this.steps);

  final SchemaMigrationSteps? steps;

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) =>
        migrateSchema(m, from: from, to: to, steps: steps),
  );
}

void main() {
  late Directory tmp;
  late List<LogRecord> records;
  late StreamSubscription<LogRecord> sub;
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('milionchik_migration_');
    records = [];
    Logger.root.level = Level.ALL;
    sub = Logger.root.onRecord.listen(records.add);
  });

  tearDown(() async {
    await sub.cancel();
    tmp.deleteSync(recursive: true);
  });

  List<LogRecord> dbLogs(Level level) => [
    for (final r in records)
      if (r.loggerName == 'db' && r.level == level) r,
  ];

  List<String> migrationMessages() => [
    for (final r in records)
      if (r.loggerName == 'db' && r.message.startsWith('schema migr'))
        '${r.level.name} ${r.message}',
  ];

  Future<AppDatabase> open() => openAppDatabase(
    directory: () async => tmp.path,
    tempDirectory: () async => tmp.path,
  );

  test(
    'файл базы новее приложения — понятная ошибка, файл не тронут',
    () async {
      final path = '${tmp.path}/$databaseFileName';
      final created = await open();
      final current = created.schemaVersion;
      final newer = current + 4;
      await created
          .into(created.localPrefs)
          .insert(LocalPrefsCompanion.insert(key: 'theme', value: 'dark'));
      await created.customStatement('PRAGMA user_version = $newer');
      await created.close();
      records.clear();

      await expectLater(
        open(),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'toString',
            'UnknownSchemaVersionException: database schema version $newer is '
                'newer than app schema version $current, '
                'downgrade is not supported',
          ),
        ),
      );

      final errors = dbLogs(Level.SEVERE);
      expect(errors, hasLength(2));
      expect(
        errors.first.message,
        matches(
          RegExp(
            '^schema migration failed from=$newer to=$current '
            r'after \d+ms: UnknownSchemaVersionException: '
            'database schema version $newer is newer',
          ),
        ),
      );
      expect(
        errors.first.error,
        isA<UnknownSchemaVersionException>()
            .having((e) => e.from, 'from', newer)
            .having((e) => e.to, 'to', current),
      );
      expect(errors.first.stackTrace, isNotNull);
      expect(
        errors.last.message,
        startsWith('database open failed path=$path after '),
      );
      expect(
        migrationMessages().first,
        'INFO schema migration started from=$newer to=$current',
      );

      int? versionOnDisk;
      String? theme;
      final probe = AppDatabase(
        NativeDatabase(
          File(path),
          setup: (raw) {
            versionOnDisk = raw.userVersion;
            theme =
                raw.select('SELECT value FROM local_prefs').single['value']
                    as String;
          },
        ),
      );
      await expectLater(
        probe.customSelect('SELECT 1').get(),
        throwsA(isA<UnknownSchemaVersionException>()),
      );
      await probe.close();
      expect(versionOnDisk, newer);
      expect(theme, 'dark');
    },
  );

  test('нет шага миграции для версии — понятная ошибка', () async {
    final schema = await verifier.schemaAt(1);
    final db = _StepsDatabase(schema.newConnection(), null);
    addTearDown(db.close);

    await expectLater(
      db.customSelect('SELECT 1').get(),
      throwsA(
        isA<UnknownSchemaVersionException>().having(
          (e) => e.message,
          'message',
          'no migration from database schema version 1 to app schema version 3',
        ),
      ),
    );
    expect(schema.rawDatabase.userVersion, 1);
    expect(migrationMessages(), [
      'INFO schema migration started from=1 to=3',
      matches(
        RegExp(
          r'^SEVERE schema migration failed from=1 to=3 after \d+ms: '
          r'UnknownSchemaVersionException: no migration from database schema '
          r'version 1 to app schema version 3$',
        ),
      ),
    ]);
  });

  test(
    'шаги по порядку: info было/стало и время, debug на каждый шаг',
    () async {
      final schema = await verifier.schemaAt(1);
      final called = <int>[];
      final db = _StepsDatabase(schema.newConnection(), (
        version,
        database,
      ) async {
        called.add(version);
        await database.customStatement(
          'CREATE TABLE step_$version (id INTEGER)',
        );
        return version + 1;
      });
      addTearDown(db.close);

      await db.customSelect('SELECT 1').get();

      expect(called, [1, 2]);
      expect(schema.rawDatabase.userVersion, 3);
      expect(migrationMessages(), [
        'INFO schema migration started from=1 to=3',
        'FINE schema migration step started from=1',
        matches(
          RegExp(r'^FINE schema migration step done from=1 to=2 in \d+ms$'),
        ),
        'FINE schema migration step started from=2',
        matches(
          RegExp(r'^FINE schema migration step done from=2 to=3 in \d+ms$'),
        ),
        matches(RegExp(r'^INFO schema migrated from=1 to=3 in \d+ms$')),
      ]);
    },
  );

  test(
    'шаг упал — error с версиями и стеком, версия прошлого шага сохранена',
    () async {
      final schema = await verifier.schemaAt(1);
      final db = _StepsDatabase(schema.newConnection(), (
        version,
        database,
      ) async {
        if (version == 2) throw StateError('step 2 broke');
        return version + 1;
      });
      addTearDown(db.close);

      await expectLater(
        db.customSelect('SELECT 1').get(),
        throwsA(isA<StateError>()),
      );

      expect(schema.rawDatabase.userVersion, 2);
      final errors = dbLogs(Level.SEVERE);
      expect(errors, hasLength(1));
      expect(
        errors.single.message,
        matches(
          RegExp(
            r'^schema migration failed from=1 to=3 after \d+ms: '
            r'StateError: Bad state: step 2 broke$',
          ),
        ),
      );
      expect(
        errors.single.stackTrace.toString(),
        contains('schema_migration_test.dart'),
      );
    },
  );

  test('шаг вернул не следующую версию — ошибка вместо зацикливания', () async {
    final schema = await verifier.schemaAt(1);
    final db = _StepsDatabase(
      schema.newConnection(),
      (version, _) async => version,
    );
    addTearDown(db.close);

    await expectLater(
      db.customSelect('SELECT 1').get(),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'schema migration step from=1 returned version 1, expected 2..3',
        ),
      ),
    );
    expect(schema.rawDatabase.userVersion, 1);
  });
}
