import 'package:drift/drift.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

final _log = Logger('db');

typedef SchemaMigrationSteps = Future<int> Function(
  int version,
  GeneratedDatabase database,
);

class UnknownSchemaVersionException implements Exception {
  const UnknownSchemaVersionException({required this.from, required this.to});

  final int from;
  final int to;

  String get message => from > to
      ? 'database schema version $from is newer than app schema version $to, '
            'downgrade is not supported'
      : 'no migration from database schema version $from '
            'to app schema version $to';

  @override
  String toString() => 'UnknownSchemaVersionException: $message';
}

Future<void> migrateSchema(
  Migrator m, {
  required int from,
  required int to,
  SchemaMigrationSteps? steps,
}) async {
  final sw = Stopwatch()..start();
  _log.info('schema migration started from=$from to=$to');
  try {
    if (from > to || steps == null) {
      throw UnknownSchemaVersionException(from: from, to: to);
    }
    var version = from;
    while (version < to) {
      final stepWatch = Stopwatch()..start();
      _log.fine('schema migration step started from=$version');
      final next = await steps(version, m.database);
      if (next <= version || next > to) {
        throw StateError(
          'schema migration step from=$version returned version $next, '
          'expected ${version + 1}..$to',
        );
      }
      await m.database.customStatement('PRAGMA user_version = $next');
      _log.fine(
        'schema migration step done from=$version to=$next '
        'in ${stepWatch.elapsedMilliseconds}ms',
      );
      version = next;
    }
    _log.info(
      'schema migrated from=$from to=$to in ${sw.elapsedMilliseconds}ms',
    );
  } catch (e, st) {
    _log.severe(
      'schema migration failed from=$from to=$to '
      'after ${sw.elapsedMilliseconds}ms: ${describeError(e)}',
      e,
      st,
    );
    rethrow;
  }
}
