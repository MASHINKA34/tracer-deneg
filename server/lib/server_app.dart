import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:shared/logging.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'auth/auth_service.dart';
import 'auth/password_hasher.dart';
import 'auth/tokens.dart';
import 'config/config.dart';
import 'config/dotenv.dart';
import 'db/database.dart';
import 'db/migrator.dart';
import 'http/router.dart';
import 'version.dart';

final _log = Logger('server');

/// Запущенный сервер: HTTP и пул БД. [shutdown] закрывает всё по порядку.
class RunningServer {
  RunningServer._(this.http, this.db);

  final HttpServer http;
  final Database db;

  int get port => http.port;

  /// Корректная остановка: HTTP (ждём активные запросы до 10 с) → пул БД.
  Future<void> shutdown(String reason) async {
    final total = Stopwatch()..start();
    _log.info('shutting down: $reason');

    final httpSw = Stopwatch()..start();
    final active = http.connectionsInfo().active;
    _log.info('closing HTTP server (active connections=$active)');
    try {
      await http.close().timeout(const Duration(seconds: 10));
    } on TimeoutException {
      _log.warning(
        'HTTP server close timed out after 10s '
        '(active connections=${http.connectionsInfo().active}), forcing',
      );
      await http.close(force: true);
    }
    _log.info('HTTP server closed in ${httpSw.elapsedMilliseconds}ms');

    final dbSw = Stopwatch()..start();
    _log.info('closing Postgres pool');
    await db.close();
    _log.info('Postgres pool closed in ${dbSw.elapsedMilliseconds}ms');

    _log.info('shutdown complete in ${total.elapsedMilliseconds}ms');
  }
}

/// Подключается к базе и начинает слушать порт. Ошибка любого шага
/// пишется в лог и пробрасывается (уже открытое закрывается).
Future<RunningServer> startServer(
  ServerConfig config, {
  int dbConnectAttempts = 5,
  List<Duration>? dbRetryDelays,
}) async {
  final db = dbRetryDelays == null
      ? await Database.connect(config.database, attempts: dbConnectAttempts)
      : await Database.connect(
          config.database,
          attempts: dbConnectAttempts,
          delays: dbRetryDelays,
        );

  try {
    await Migrator(db, directory: Directory(config.migrationsDir)).run();
  } catch (e) {
    _log.severe('migrations failed → HTTP server not started');
    await db.close(reason: 'migrations failed');
    rethrow;
  }

  final hasher = PasswordHasher();
  final auth = AuthService(
    db: db,
    hasher: hasher,
    accessTokens: AccessTokens(config.jwtSecret),
  );
  _log.info(
    'auth ready: argon2id ${hasher.params.phc} '
    'access=${accessTokenTtl.inMinutes}m refresh=${refreshTokenTtl.inDays}d',
  );

  final sw = Stopwatch()..start();
  _log.info('starting HTTP server on ${config.host}:${config.port}');
  try {
    final http = await shelf_io.serve(
      buildHandler(db: db, auth: auth),
      config.host,
      config.port,
    );
    _log.info(
      'HTTP server listening on ${http.address.address}:${http.port} '
      'in ${sw.elapsedMilliseconds}ms',
    );
    return RunningServer._(http, db);
  } catch (e, st) {
    _log.severe(
      'HTTP server failed to bind ${config.host}:${config.port}: '
      '${describeError(e)}',
      e,
      st,
    );
    await db.close(reason: 'HTTP bind failed');
    rethrow;
  }
}

/// Весь жизненный цикл процесса: конфиг → старт → ждём сигнал → остановка.
/// Возвращает код выхода. [stopSignal] по умолчанию — SIGINT/SIGTERM.
///
/// [environment] — переменные окружения, [envFile] — `.env` (если есть;
/// переменные окружения важнее), [setLogLevel] применяет `LOG_LEVEL`.
Future<int> runServerProcess({
  required Map<String, String> environment,
  File? envFile,
  required void Function(Level level) setLogLevel,
  Future<String>? stopSignal,
}) async {
  final total = Stopwatch()..start();
  _log.info(
    'milionchik server $serverVersion starting '
    'dart=${Platform.version.split(' ').first} '
    'os=${Platform.operatingSystem} pid=$pid',
  );

  // Шаг 1: конфиг.
  final ServerConfig config;
  try {
    final dotEnv = _readEnvFile(envFile);
    config = ServerConfig.load(environment: environment, dotEnv: dotEnv);
    final fromEnv = dotEnv.keys.where(environment.containsKey).toList();
    _log.info(
      'config loaded ${formatContext(config.toLogContext())}'
      '${fromEnv.isEmpty ? '' : ' overriddenByEnv=${fromEnv.join(',')}'}',
    );
  } on ConfigException catch (e) {
    _log.severe('config invalid: ${e.problems.join('; ')}');
    return 1;
  } catch (e, st) {
    _log.severe('config load failed: ${describeError(e)}', e, st);
    return 1;
  }
  setLogLevel(config.logLevel);

  // Шаг 2–3: база и HTTP.
  final RunningServer server;
  try {
    server = await startServer(config);
  } catch (e) {
    // Подробности (тип, стек) уже в логе шага, который упал.
    _log.severe(
      'server start failed after ${total.elapsedMilliseconds}ms → exit 1',
    );
    return 1;
  }
  _log.info(
    'server started in ${total.elapsedMilliseconds}ms '
    'url=http://${config.host}:${server.port}/api/v1/health',
  );

  // Шаг 4: ждём сигнал и останавливаемся.
  final signal = await (stopSignal ?? waitForShutdownSignal());
  try {
    await server.shutdown('received $signal');
    return 0;
  } catch (e, st) {
    _log.severe('shutdown failed: ${describeError(e)}', e, st);
    return 1;
  }
}

/// Первый SIGINT (Ctrl+C) или SIGTERM (docker stop) → имя сигнала.
/// Повторный сигнал во время остановки — немедленный выход с кодом 130.
/// SIGTERM на Windows Dart не поддерживает — там только SIGINT.
Future<String> waitForShutdownSignal() {
  final completer = Completer<String>();
  void onSignal(ProcessSignal signal) {
    if (!completer.isCompleted) {
      completer.complete(signal.toString());
      return;
    }
    _log.warning('second $signal during shutdown → forcing exit 130');
    unawaited(stdout.flush().whenComplete(() => exit(130)));
  }

  ProcessSignal.sigint.watch().listen(onSignal);
  if (!Platform.isWindows) ProcessSignal.sigterm.watch().listen(onSignal);
  _log.fine('waiting for ${Platform.isWindows ? 'SIGINT' : 'SIGINT/SIGTERM'}');
  return completer.future;
}

Map<String, String> _readEnvFile(File? file) {
  if (file == null) return const {};
  if (!file.existsSync()) {
    _log.info(
      'env file ${file.absolute.path} not found → using environment only',
    );
    return const {};
  }
  final parsed = parseDotEnv(file.readAsStringSync());
  for (final warning in parsed.warnings) {
    _log.warning('env file ${file.absolute.path}: $warning (line skipped)');
  }
  _log.info(
    'env file ${file.absolute.path} read: ${parsed.values.length} keys '
    '(${parsed.values.keys.join(',')})',
  );
  return parsed.values;
}
