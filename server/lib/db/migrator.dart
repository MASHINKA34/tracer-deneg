import 'dart:io';
import 'dart:math';

import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:shared/logging.dart';

import '../logging/log_setup.dart';
import 'database.dart';

final _log = Logger('db');

const int migrationLockKey = 0x6d696c696f6e6d67;

final RegExp _migrationFileName = RegExp(r'^(\d{4})_([a-z0-9_]+)\.sql$');

const String _createMigrationsTable = '''
CREATE TABLE IF NOT EXISTS schema_migrations (
  version integer PRIMARY KEY,
  name text NOT NULL,
  applied_at timestamptz NOT NULL DEFAULT now()
)''';

class MigrationException implements Exception {
  MigrationException(this.message, {this.file, this.cause});

  final String message;
  final String? file;
  final Object? cause;

  @override
  String toString() => 'MigrationException: $message';
}

class MigrationFile {
  const MigrationFile({
    required this.version,
    required this.name,
    required this.path,
  });

  final int version;
  final String name;
  final String path;
}

class MigrationResult {
  MigrationResult({
    required List<String> applied,
    required this.alreadyApplied,
    required this.schemaVersion,
  }) : applied = List.unmodifiable(applied);

  final List<String> applied;
  final int alreadyApplied;
  final int schemaVersion;
}

class Migrator {
  Migrator(this._db, {required this.directory});

  final Database _db;
  final Directory directory;

  Future<MigrationResult> run() async {
    final total = Stopwatch()..start();
    try {
      final files = readMigrationFiles();
      return await _db.withConnection(
        'migrations',
        (connection) => _migrate(connection, files, total),
      );
    } on MigrationException {
      rethrow;
    } catch (e, st) {
      _log.severe(
        'migrations failed after ${total.elapsedMilliseconds}ms: '
        '${describeError(e)}',
        e,
        st,
      );
      rethrow;
    }
  }

  List<MigrationFile> readMigrationFiles() {
    final dir = directory.absolute;
    if (!dir.existsSync()) {
      _fail('migrations directory not found: ${dir.path} (set MIGRATIONS_DIR)');
    }
    final files = <MigrationFile>[];
    final names = <int, String>{};
    for (final entity in dir.listSync()) {
      if (entity is! File) {
        _log.fine('migrations: skipping ${entity.path} (not a file)');
        continue;
      }
      final name = entity.uri.pathSegments.last;
      if (!name.endsWith('.sql')) {
        _log.fine('migrations: skipping $name (not .sql)');
        continue;
      }
      final match = _migrationFileName.firstMatch(name);
      if (match == null) {
        _fail(
          'unexpected migration file name $name in ${dir.path}: '
          'expected NNNN_name.sql ([a-z0-9_] after the number)',
          file: name,
        );
      }
      final version = int.parse(match.group(1)!);
      final clash = names[version];
      if (clash != null) {
        _fail(
          'duplicate migration version $version: $clash and $name',
          file: name,
        );
      }
      names[version] = name;
      files.add(MigrationFile(version: version, name: name, path: entity.path));
    }
    if (files.isEmpty) {
      _fail('no migration files (NNNN_name.sql) in ${dir.path}');
    }
    files.sort((a, b) => a.version.compareTo(b.version));
    _log.info(
      'migrations: found ${files.length} file(s) in ${dir.path}: '
      '${files.map((f) => f.name).join(',')}',
    );
    return files;
  }

  Future<MigrationResult> _migrate(
    DbConnection connection,
    List<MigrationFile> files,
    Stopwatch total,
  ) async {
    await _lock(connection);
    final held = Stopwatch()..start();
    try {
      await connection.execute(
        _createMigrationsTable,
        what: 'create schema_migrations if missing',
      );
      final rows = await connection.execute(
        'SELECT version, name FROM schema_migrations ORDER BY version',
        what: 'applied migrations',
      );
      final applied = {
        for (final row in rows) row[0]! as int: row[1]! as String,
      };
      _warnAboutMismatches(files, applied);

      final pending = [
        for (final file in files)
          if (!applied.containsKey(file.version)) file,
      ];
      final latestApplied = applied.isEmpty ? 0 : applied.keys.reduce(max);
      if (pending.isEmpty) {
        _log.info(
          'migrations: nothing to apply, ${applied.length} already applied, '
          'schema version $latestApplied (${applied[latestApplied]}) '
          'in ${total.elapsedMilliseconds}ms',
        );
        return MigrationResult(
          applied: const [],
          alreadyApplied: applied.length,
          schemaVersion: latestApplied,
        );
      }

      _log.info(
        'migrations: ${pending.length} to apply '
        '(${pending.map((f) => f.name).join(',')}), '
        '${applied.length} already applied',
      );
      for (var i = 0; i < pending.length; i++) {
        final file = pending[i];
        if (file.version < latestApplied) {
          _log.warning(
            'migrations: applying ${file.name} out of order, '
            'version $latestApplied is already applied',
          );
        }
        await _apply(connection, file, i + 1, pending.length);
      }
      final schemaVersion = max(latestApplied, pending.last.version);
      _log.info(
        'migrations: applied ${pending.length} in '
        '${total.elapsedMilliseconds}ms, schema version $schemaVersion',
      );
      return MigrationResult(
        applied: [for (final file in pending) file.name],
        alreadyApplied: applied.length,
        schemaVersion: schemaVersion,
      );
    } finally {
      await _unlock(connection, held);
    }
  }

  Future<void> _lock(DbConnection connection) async {
    final sw = Stopwatch()..start();
    final tried = await connection.execute(
      'SELECT pg_try_advisory_lock($migrationLockKey)',
      what: 'try migration lock',
    );
    if (tried.first.first == true) {
      _log.info(
        'migration lock acquired in ${sw.elapsedMilliseconds}ms '
        'key=$migrationLockKey waited=false',
      );
      return;
    }
    _log.info(
      'migration lock busy (another server is migrating) → waiting '
      'key=$migrationLockKey',
    );
    await connection.execute(
      'SELECT pg_advisory_lock($migrationLockKey)',
      what: 'wait for migration lock',
    );
    _log.info(
      'migration lock acquired after waiting ${sw.elapsedMilliseconds}ms '
      'key=$migrationLockKey waited=true',
    );
  }

  Future<void> _unlock(DbConnection connection, Stopwatch held) async {
    try {
      final released = await connection.execute(
        'SELECT pg_advisory_unlock($migrationLockKey)',
        what: 'release migration lock',
      );
      if (released.first.first == true) {
        _log.info(
          'migration lock released key=$migrationLockKey '
          'held ${held.elapsedMilliseconds}ms',
        );
      } else {
        _log.warning(
          'migration lock was not held at release key=$migrationLockKey',
        );
      }
    } catch (e, st) {
      _log.warning(
        'migration lock release failed key=$migrationLockKey, it is released '
        'when the connection closes: ${describeError(e)}',
        e,
        st,
      );
    }
  }

  Future<void> _apply(
    DbConnection connection,
    MigrationFile file,
    int index,
    int count,
  ) async {
    final sw = Stopwatch()..start();
    _log.info('migration ${file.name} applying ($index/$count)');
    final String sql;
    try {
      sql = await File(file.path).readAsString();
    } catch (e, st) {
      _log.severe(
        'migration ${file.name} could not be read from ${file.path}: '
        '${describeError(e)}',
        e,
        st,
      );
      throw MigrationException(
        'cannot read ${file.name}',
        file: file.name,
        cause: e,
      );
    }
    try {
      await connection.transaction('migration ${file.name}', (tx) async {
        await tx.execute(sql, what: file.name, queryMode: QueryMode.simple);
        await tx.execute(
          r'INSERT INTO schema_migrations (version, name) VALUES ($1, $2)',
          parameters: [file.version, file.name],
          what: 'record migration',
          logParams: {'version': file.version, 'name': file.name},
        );
      });
    } catch (e, st) {
      final described = describeError(e);
      final context = formatContext({
        'file': file.name,
        'line': _errorLine(sql, e),
        if (!described.contains('sqlState='))
          'sqlState': postgresErrorDetails(e)?['sqlState'],
      });
      _log.severe(
        'migration failed $context in ${sw.elapsedMilliseconds}ms, '
        'rolled back: $described',
        e,
        st,
      );
      throw MigrationException(
        'migration ${file.name} failed',
        file: file.name,
        cause: e,
      );
    }
    _log.info(
      'migration ${file.name} applied in ${sw.elapsedMilliseconds}ms '
      '($index/$count)',
    );
  }

  void _warnAboutMismatches(
    List<MigrationFile> files,
    Map<int, String> applied,
  ) {
    final onDisk = {for (final file in files) file.version: file.name};
    applied.forEach((version, name) {
      final diskName = onDisk[version];
      if (diskName == null) {
        _log.warning(
          'migrations: $name is applied but missing in ${directory.path} '
          '(database is newer than this server?)',
        );
      } else if (diskName != name) {
        _log.warning(
          'migrations: version $version applied as $name, '
          'file on disk is $diskName (renamed?)',
        );
      }
    });
  }
}

Never _fail(String message, {String? file}) {
  _log.severe('migrations failed: $message', null, StackTrace.current);
  throw MigrationException(message, file: file);
}

int? _errorLine(String sql, Object error) {
  if (error is! ServerException) return null;
  final position = error.position;
  if (position == null || position < 1) return null;
  final end = min(position - 1, sql.length);
  return '\n'.allMatches(sql.substring(0, end)).length + 1;
}
