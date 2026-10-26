import 'dart:io';

import 'package:server/config/config.dart';
import 'package:server/db/database.dart';
import 'package:server/db/migrator.dart';
import 'package:server/server_app.dart';
import 'package:test/test.dart';

import 'support/test_support.dart';

final _migrations = Directory('migrations');

Directory _tempMigrations(Map<String, String> files) {
  final dir = Directory.systemTemp.createTempSync('milionchik_migrations_');
  addTearDown(() => dir.deleteSync(recursive: true));
  files.forEach(
    (name, sql) => File('${dir.path}/$name').writeAsStringSync(sql),
  );
  return dir;
}

Future<List<List<Object?>>> _appliedRows(Database db) async {
  final rows = await db.execute(
    'SELECT version, name FROM schema_migrations ORDER BY version',
  );
  return [for (final row in rows) row.toList()];
}

Future<bool> _tableExists(Database db, String table) async {
  final rows = await db.execute(
    r'SELECT to_regclass($1) IS NOT NULL',
    parameters: ['public.$table'],
  );
  return rows.first.first! as bool;
}

void main() {
  late LogCapture logs;
  setUp(() => logs = LogCapture());

  group('Migrator.run', () {
    test('чистая база → 0001 применена с логом имени и мс, повторный запуск ничего не применяет', () async {
      final db = await openScratchDatabase();

      final first = await Migrator(db, directory: _migrations).run();
      expect(first.applied, [
        '0001_init.sql',
        '0002_used_refresh_tokens.sql',
        '0003_sync_seq_gate.sql',
      ]);
      expect(first.alreadyApplied, 0);
      expect(first.schemaVersion, 3);
      expect(await _appliedRows(db), [
        [1, '0001_init.sql'],
        [2, '0002_used_refresh_tokens.sql'],
        [3, '0003_sync_seq_gate.sql'],
      ]);
      expect(
        logs.text,
        contains(
          RegExp(
            r'INFO  \[db\] migration lock acquired in \d+ms key=\d+ waited=false',
          ),
        ),
      );
      expect(
        logs.text,
        contains(
          RegExp(r'INFO  \[db\] migration 0001_init\.sql applied in \d+ms'),
        ),
      );
      expect(
        logs.text,
        contains(RegExp(r'INFO  \[db\] migration lock released key=\d+')),
      );

      logs.clear();
      final second = await Migrator(db, directory: _migrations).run();
      expect(second.applied, isEmpty);
      expect(second.alreadyApplied, 3);
      expect(second.schemaVersion, 3);
      expect(
        logs.text,
        contains(
          'INFO  [db] migrations: nothing to apply, 3 already applied, '
          'schema version 3 (0003_sync_seq_gate.sql)',
        ),
      );
      expect(logs.text, isNot(contains('applying')));
      expect(await _appliedRows(db), hasLength(3));
    });

    test('файлы применяются по номеру, а не по порядку в папке', () async {
      final db = await openScratchDatabase();
      final dir = _tempMigrations({
        '0010_c.sql': 'CREATE TABLE c (id integer REFERENCES b (id));',
        '0002_b.sql':
            'CREATE TABLE b (id integer PRIMARY KEY REFERENCES a (id));',
        '0001_a.sql': 'CREATE TABLE a (id integer PRIMARY KEY);',
        'README.txt': 'не миграция',
      });

      final result = await Migrator(db, directory: dir).run();

      expect(result.applied, ['0001_a.sql', '0002_b.sql', '0010_c.sql']);
      expect(result.schemaVersion, 10);
      expect(await _appliedRows(db), [
        [1, '0001_a.sql'],
        [2, '0002_b.sql'],
        [10, '0010_c.sql'],
      ]);
      expect(logs.text, contains('migration 0002_b.sql applying (2/3)'));
    });

    test('ошибка в миграции: её транзакция откатывается, ERROR с файлом, строкой, SQLSTATE и стеком, блокировка отпущена', () async {
      final db = await openScratchDatabase();
      final dir = _tempMigrations({
        '0001_a.sql': 'CREATE TABLE a (id integer PRIMARY KEY);',
        '0002_bad.sql':
            'CREATE TABLE half (id integer);\n'
            'CREATE TABL broken (id integer);\n',
      });

      await expectLater(
        Migrator(db, directory: dir).run(),
        throwsA(
          isA<MigrationException>().having(
            (e) => e.file,
            'file',
            '0002_bad.sql',
          ),
        ),
      );

      expect(await _appliedRows(db), [
        [1, '0001_a.sql'],
      ]);
      expect(await _tableExists(db, 'a'), isTrue);
      expect(await _tableExists(db, 'half'), isFalse);
      expect(
        logs.text,
        contains(
          RegExp(
            r'ERROR \[db\] migration failed file=0002_bad\.sql line=2 in \d+ms, rolled back: ServerException: .*sqlState=42601',
          ),
        ),
      );
      final errorAt = logs.lines.indexWhere(
        (line) => line.contains('ERROR [db] migration failed'),
      );
      expect(logs.lines[errorAt], contains('  stack:'));
      expect(logs.text, contains('migration lock released'));

      final lockFree = await db.withConnection('check lock', (c) async {
        final rows = await c.execute(
          'SELECT pg_try_advisory_lock($migrationLockKey)',
        );
        await c.execute('SELECT pg_advisory_unlock($migrationLockKey)');
        return rows.first.first;
      });
      expect(lockFree, isTrue);

      File('${dir.path}/0002_bad.sql')
          .writeAsStringSync('CREATE TABLE fixed (id integer);');
      final retry = await Migrator(db, directory: dir).run();
      expect(retry.applied, ['0002_bad.sql']);
      expect(await _tableExists(db, 'fixed'), isTrue);
    });

    test('скрипт и запись в schema_migrations — одна транзакция: не записалась → откат скрипта', () async {
      final db = await openScratchDatabase();
      final dir = _tempMigrations({
        '0001_a.sql': 'CREATE TABLE a (id integer PRIMARY KEY);',
        '0002_sneaky.sql':
            'CREATE TABLE sneaky (id integer);\n'
            "INSERT INTO schema_migrations (version, name) VALUES (2, 'x');\n",
      });

      await expectLater(
        Migrator(db, directory: dir).run(),
        throwsA(isA<MigrationException>()),
      );

      expect(await _tableExists(db, 'sneaky'), isFalse);
      expect(await _appliedRows(db), [
        [1, '0001_a.sql'],
      ]);
      expect(
        logs.text,
        contains(
          RegExp(
            r'ERROR \[db\] migration failed file=0002_sneaky\.sql in \d+ms, rolled back: .*sqlState=23505',
          ),
        ),
      );
    });

    test('два мигратора одновременно: миграция применяется один раз', () async {
      final url = await createScratchDatabase();
      final first = Database.open(DatabaseConfig.parse(url));
      final second = Database.open(DatabaseConfig.parse(url));
      addTearDown(first.close);
      addTearDown(second.close);

      final results = await Future.wait([
        Migrator(first, directory: _migrations).run(),
        Migrator(second, directory: _migrations).run(),
      ]);

      expect(
        results.map((r) => r.applied).toList(),
        unorderedEquals([
          [
            '0001_init.sql',
            '0002_used_refresh_tokens.sql',
            '0003_sync_seq_gate.sql',
          ],
          <String>[],
        ]),
      );
      expect(results.map((r) => r.schemaVersion), everyElement(3));
      expect(await _appliedRows(first), hasLength(3));
      expect(logs.text, isNot(contains('ERROR')));
    });

    test(
      'блокировка занята: мигратор ждёт с логом и применяет после освобождения',
      () async {
        final db = await openScratchDatabase();

        await db.withConnection('lock holder', (holder) async {
          await holder.execute('SELECT pg_advisory_lock($migrationLockKey)');
          final run = Migrator(db, directory: _migrations).run();

          await waitUntil(() => logs.text.contains('migration lock busy'));
          await Future<void>.delayed(const Duration(milliseconds: 300));
          final early = await holder.execute(
            "SELECT to_regclass('public.schema_migrations') IS NULL",
          );
          expect(early.first.first, isTrue);
          expect(logs.text, isNot(contains('applying')));

          await holder.execute('SELECT pg_advisory_unlock($migrationLockKey)');
          final result = await run;
          expect(result.applied, [
            '0001_init.sql',
            '0002_used_refresh_tokens.sql',
            '0003_sync_seq_gate.sql',
          ]);
        });

        expect(
          logs.text,
          contains(
            RegExp(
              r'INFO  \[db\] migration lock busy \(another server is migrating\) → waiting key=\d+',
            ),
          ),
        );
        final acquired = RegExp(
          r'migration lock acquired after waiting (\d+)ms key=\d+ waited=true',
        ).firstMatch(logs.text);
        expect(acquired, isNotNull);
        expect(int.parse(acquired!.group(1)!), greaterThanOrEqualTo(300));
      },
    );
  });

  group('файлы миграций', () {
    test('нет папки → ошибка с путём и подсказкой про MIGRATIONS_DIR', () {
      final missing = Directory('${Directory.systemTemp.path}/no_such_dir_42');
      final db = Database.open(testDatabaseConfig());
      addTearDown(db.close);
      final migrator = Migrator(db, directory: missing);
      expect(migrator.readMigrationFiles, throwsA(isA<MigrationException>()));
      expect(
        logs.text,
        contains(
          'ERROR [db] migrations failed: migrations directory not found: '
          '${missing.absolute.path} (set MIGRATIONS_DIR)',
        ),
      );
    });

    test('неверное имя .sql-файла и повтор номера — ошибка, а не пропуск', () {
      final db = Database.open(testDatabaseConfig());
      addTearDown(db.close);
      final badName = _tempMigrations({'0001-init.sql': 'SELECT 1;'});
      expect(
        Migrator(db, directory: badName).readMigrationFiles,
        throwsA(
          isA<MigrationException>().having(
            (e) => e.file,
            'file',
            '0001-init.sql',
          ),
        ),
      );
      final duplicate = _tempMigrations({
        '0001_a.sql': 'SELECT 1;',
        '0001_b.sql': 'SELECT 1;',
      });
      expect(
        Migrator(db, directory: duplicate).readMigrationFiles,
        throwsA(isA<MigrationException>()),
      );
      expect(
        logs.text,
        contains('unexpected migration file name 0001-init.sql'),
      );
      expect(logs.text, contains('duplicate migration version 1'));
    });

    test('пустая папка — ошибка', () {
      final db = Database.open(testDatabaseConfig());
      addTearDown(db.close);
      final empty = _tempMigrations({});
      expect(
        Migrator(db, directory: empty).readMigrationFiles,
        throwsA(isA<MigrationException>()),
      );
      expect(logs.text, contains('no migration files'));
    });
  });

  group('старт сервера', () {
    test('миграции идут шагом после подключения к базе и до HTTP', () async {
      final url = await createScratchDatabase();
      final server = await startServer(
        ServerConfig.load(
          environment: {
            'HOST': '127.0.0.1',
            'PORT': '0',
            'DATABASE_URL': url,
            'JWT_SECRET': 'x' * 32,
            'INVITE_CODE_SECRET': 'invite-code-secret-0123456789-abcdef',
          },
        ),
        dbConnectAttempts: 1,
      );
      addTearDown(() => server.shutdown('test'));

      expect(await _appliedRows(server.db), [
        [1, '0001_init.sql'],
        [2, '0002_used_refresh_tokens.sql'],
        [3, '0003_sync_seq_gate.sql'],
      ]);
      int at(String text) =>
          logs.lines.indexWhere((line) => line.contains(text));
      expect(at('Postgres connected in'), greaterThanOrEqualTo(0));
      expect(
        at('migration 0001_init.sql applied'),
        greaterThan(at('Postgres connected in')),
      );
      expect(
        at('HTTP server listening'),
        greaterThan(at('migration 0001_init.sql applied')),
      );
    });

    test('ошибка миграции → сервер не стартует, код выхода 1', () async {
      final url = await createScratchDatabase();
      final dir = _tempMigrations({'0001_bad.sql': 'CREATE TABL x ();'});

      final code = await runServerProcess(
        environment: {
          'HOST': '127.0.0.1',
          'PORT': '0',
          'DATABASE_URL': url,
          'JWT_SECRET': 'x' * 32,
          'INVITE_CODE_SECRET': 'invite-code-secret-0123456789-abcdef',
          'MIGRATIONS_DIR': dir.path,
        },
        setLogLevel: (_) {},
      );

      expect(code, 1);
      expect(
        logs.text,
        contains('ERROR [db] migration failed file=0001_bad.sql'),
      );
      expect(
        logs.text,
        contains('ERROR [server] migrations failed → HTTP server not started'),
      );
      expect(logs.text, contains('ERROR [server] server start failed'));
      expect(logs.text, isNot(contains('HTTP server listening')));
    });
  });
}
