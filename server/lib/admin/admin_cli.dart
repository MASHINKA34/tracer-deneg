import 'dart:io';

import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:shared/logging.dart';

import '../client_errors/client_error_store.dart';
import '../config/config.dart';
import '../config/dotenv.dart';
import '../db/database.dart';
import '../jobs/daily_job_list.dart';
import '../jobs/daily_jobs.dart';
import 'errors_table.dart';

final _log = Logger('admin');

const int adminExitOk = 0;
const int adminExitFailure = 1;
const int adminExitUsage = 64;
const int errorsDefaultLimit = 50;
const int errorsMaxLimit = 1000;

const String adminUsage =
    '''
Usage: dart run bin/admin.dart <command> [options]

Commands:
  errors --since <age> [--limit <N>]
      Client error reports received during the last <age>, newest first.
      <age>: number with unit m (minutes), h (hours) or d (days): 30m, 12h, 1d.
      <N>: 1..$errorsMaxLimit, default $errorsDefaultLimit.
  jobs
      Run every daily job of the server once now (old client error reports,
      expired and revoked invites, sessions ended more than 90 days ago).
      Exit code 1 if any job failed; the other jobs still run.
  help
      This text.

Reads DATABASE_URL (and LOG_LEVEL) from the environment or server/.env,
like the server. Logs go to stderr, the table and job results to stdout.''';

class AdminUsageException implements Exception {
  AdminUsageException(this.message);

  final String message;

  @override
  String toString() => 'AdminUsageException: $message';
}

final class ErrorsQuery {
  const ErrorsQuery({
    required this.since,
    required this.sinceText,
    required this.limit,
  });

  final Duration since;
  final String sinceText;
  final int limit;
}

final RegExp _age = RegExp(r'^(\d{1,6})([mhd])$');

Duration parseAge(String text) {
  final match = _age.firstMatch(text.trim().toLowerCase());
  if (match == null) {
    throw AdminUsageException(
      '--since must look like 30m, 12h or 1d, got "${terminalSafe(text, maxChars: 32)}"',
    );
  }
  final amount = int.parse(match[1]!);
  if (amount == 0) {
    throw AdminUsageException('--since must be greater than zero');
  }
  return switch (match[2]) {
    'm' => Duration(minutes: amount),
    'h' => Duration(hours: amount),
    _ => Duration(days: amount),
  };
}

ErrorsQuery parseErrorsArgs(List<String> args) {
  String? since;
  String? limit;
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    final eq = arg.indexOf('=');
    final name = arg.startsWith('--') && eq > 0 ? arg.substring(0, eq) : arg;
    String value() {
      if (eq > 0 && arg.startsWith('--')) return arg.substring(eq + 1);
      if (i + 1 >= args.length) {
        throw AdminUsageException('$name needs a value');
      }
      return args[++i];
    }

    switch (name) {
      case '--since':
        since = value();
      case '--limit':
        limit = value();
      default:
        throw AdminUsageException(
          'unknown option "${terminalSafe(arg, maxChars: 32)}" for errors',
        );
    }
  }
  if (since == null) throw AdminUsageException('errors needs --since <age>');
  final age = parseAge(since);
  var count = errorsDefaultLimit;
  if (limit != null) {
    final parsed = int.tryParse(limit.trim());
    if (parsed == null || parsed < 1 || parsed > errorsMaxLimit) {
      throw AdminUsageException(
        '--limit must be a number 1..$errorsMaxLimit, '
        'got "${terminalSafe(limit, maxChars: 32)}"',
      );
    }
    count = parsed;
  }
  return ErrorsQuery(since: age, sinceText: since.trim(), limit: count);
}

Future<int> runAdmin(
  List<String> args, {
  required Map<String, String> environment,
  File? envFile,
  required void Function(String line) out,
  void Function(Level level)? setLogLevel,
  DateTime Function() now = DateTime.now,
  int connectAttempts = 1,
}) async {
  if (args.isEmpty || const ['help', '--help', '-h'].contains(args.first)) {
    out(adminUsage);
    return args.isEmpty ? adminExitUsage : adminExitOk;
  }
  final command = args.first;
  if (command != 'errors' && command != 'jobs') {
    _log.severe(
      'unknown command "${terminalSafe(command, maxChars: 32)}" '
      '→ see usage below',
    );
    out(adminUsage);
    return adminExitUsage;
  }

  ErrorsQuery? query;
  try {
    if (command == 'errors') {
      query = parseErrorsArgs(args.sublist(1));
    } else {
      _checkJobsArgs(args.sublist(1));
    }
  } on AdminUsageException catch (e) {
    _log.severe('$command: ${e.message} → see usage below');
    out(adminUsage);
    return adminExitUsage;
  }

  final settings = _readSettings(environment, envFile);
  final level = settings['LOG_LEVEL'];
  if (level != null) {
    final parsed = parseLogLevel(level);
    if (parsed == null) {
      _log.warning(
        'LOG_LEVEL "${terminalSafe(level, maxChars: 16)}" is not one of '
        '${logLevelsByName.keys.join('|')} → keeping info',
      );
    } else {
      setLogLevel?.call(parsed);
    }
  }
  final url = settings['DATABASE_URL'];
  if (url == null) {
    _log.severe(
      'DATABASE_URL is not set: put it into the environment or '
      'server/.env (postgres://user:password@host:5434/db)',
    );
    return adminExitFailure;
  }
  final DatabaseConfig config;
  try {
    config = DatabaseConfig.parse(url);
  } on FormatException catch (e) {
    _log.severe('DATABASE_URL is invalid: ${e.message}');
    return adminExitFailure;
  }

  if (query == null) {
    return _runJobs(
      config,
      now: now,
      out: out,
      connectAttempts: connectAttempts,
    );
  }

  final sw = Stopwatch()..start();
  final since = now().toUtc().subtract(query.since);
  _log.info(
    'admin errors since=${query.sinceText} (${formatLogTime(since)}) '
    'limit=${query.limit} db=${config.masked}',
  );

  final db = await _connect(config, connectAttempts);
  if (db == null) return adminExitFailure;
  try {
    final page = await ClientErrorStore(db)
        .listSince(since, limit: query.limit);
    for (final line in formatErrorsTable(
      page,
      since: since,
      sinceText: query.sinceText,
    )) {
      out(line);
    }
    _log.info(
      'admin errors done found=${page.total} shown=${page.rows.length} '
      'in ${sw.elapsedMilliseconds}ms',
    );
    return adminExitOk;
  } on ServerException catch (e, st) {
    if (e.code == '42P01') {
      _log.severe(
        'table client_errors does not exist in db=${config.database}: '
        'migrations are not applied → start the server once '
        '(dart run bin/server.dart) to apply them',
      );
    } else {
      _log.severe(
        'listing client errors failed in ${sw.elapsedMilliseconds}ms: '
        '${describeError(e)}',
        e,
        st,
      );
    }
    return adminExitFailure;
  } catch (e, st) {
    _log.severe(
      'listing client errors failed in ${sw.elapsedMilliseconds}ms: '
      '${describeError(e)}',
      e,
      st,
    );
    return adminExitFailure;
  } finally {
    await db.close(reason: 'admin errors done');
  }
}

void _checkJobsArgs(List<String> args) {
  if (args.isEmpty) return;
  throw AdminUsageException(
    'jobs takes no options, got "${terminalSafe(args.first, maxChars: 32)}"',
  );
}

Future<Database?> _connect(DatabaseConfig config, int attempts) async {
  try {
    return await Database.connect(config, attempts: attempts);
  } catch (e) {
    _log.severe(
      'cannot connect to Postgres ${config.host}:${config.port} '
      'db=${config.database}: ${describeError(e)} → is the database '
      'running? (docker compose -f deploy/docker-compose.dev.yml up -d '
      '--wait) Is DATABASE_URL right?',
    );
    return null;
  }
}

Future<int> _runJobs(
  DatabaseConfig config, {
  required DateTime Function() now,
  required void Function(String line) out,
  required int connectAttempts,
}) async {
  final sw = Stopwatch()..start();
  _log.info('admin jobs: running daily jobs once now db=${config.masked}');
  final db = await _connect(config, connectAttempts);
  if (db == null) return adminExitFailure;
  try {
    final results = <String, String>{};
    final jobs = DailyJobs([
      for (final job in dailyJobList(db, now: now))
        DailyJob(job.name, () async => results[job.name] = await job.run()),
    ], now: now);
    final run = await jobs.runNow('admin');
    for (final job in jobs.jobs) {
      final result = results[job.name];
      out(
        '${job.name}: '
        '${result == null ? 'FAILED, see the error in the log' : 'ok $result'}',
      );
    }
    final failed = run.failed;
    _log.log(
      failed.isEmpty ? Level.INFO : Level.SEVERE,
      'admin jobs done ok=${run.ok.length} failed=${failed.length}'
      '${failed.isEmpty ? '' : ' (${failed.join(',')})'} '
      'in ${sw.elapsedMilliseconds}ms → exit '
      '${failed.isEmpty ? adminExitOk : adminExitFailure}',
    );
    return failed.isEmpty ? adminExitOk : adminExitFailure;
  } finally {
    await db.close(reason: 'admin jobs done');
  }
}

Map<String, String> _readSettings(
  Map<String, String> environment,
  File? envFile,
) {
  final values = <String, String>{};
  if (envFile != null) {
    if (!envFile.existsSync()) {
      _log.info(
        'env file ${envFile.absolute.path} not found → using environment only',
      );
    } else {
      final parsed = parseDotEnv(envFile.readAsStringSync());
      for (final warning in parsed.warnings) {
        _log.warning(
          'env file ${envFile.absolute.path}: $warning (line skipped)',
        );
      }
      _log.fine(
        'env file ${envFile.absolute.path} read: ${parsed.values.length} keys',
      );
      values.addAll(parsed.values);
    }
  }
  for (final key in const ['DATABASE_URL', 'LOG_LEVEL']) {
    final value = environment[key];
    if (value != null) values[key] = value;
  }
  values.removeWhere((_, value) => value.trim().isEmpty);
  return values.map((key, value) => MapEntry(key, value.trim()));
}
