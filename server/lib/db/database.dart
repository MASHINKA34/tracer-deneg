import 'dart:async';
import 'dart:math';

import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:shared/logging.dart';

import '../config/config.dart';

final _log = Logger('db');

/// Пул соединений с PostgreSQL. Каждый запрос пишется в лог на уровне debug:
/// что выполняли, сколько строк вернулось, сколько заняло.
class Database {
  Database._(this.config, this._pool);

  /// Создаёт пул без проверки соединения: подключение произойдёт
  /// при первом запросе. Для старта сервера — [connect].
  factory Database.open(
    DatabaseConfig config, {
    Duration connectTimeout = const Duration(seconds: 5),
  }) {
    final pool = Pool<void>.withEndpoints(
      [
        Endpoint(
          host: config.host,
          port: config.port,
          database: config.database,
          username: config.username,
          password: config.password,
        ),
      ],
      settings: PoolSettings(
        applicationName: 'milionchik-server',
        maxConnectionCount: 10,
        connectTimeout: connectTimeout,
        sslMode: switch (config.sslMode) {
          'require' => SslMode.require,
          'verify-full' => SslMode.verifyFull,
          _ => SslMode.disable,
        },
      ),
    );
    return Database._(config, pool);
  }

  /// Подключается с повторами: [attempts] попыток, паузы [delays]
  /// (последняя пауза повторяется). Не вышло — пробрасывает последнюю ошибку.
  static Future<Database> connect(
    DatabaseConfig config, {
    int attempts = 5,
    List<Duration> delays = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
    ],
    Duration connectTimeout = const Duration(seconds: 5),
  }) async {
    final target = '${config.host}:${config.port}';
    _log.info(
      'connecting to Postgres $target db=${config.database} '
      'user=${config.username} ssl=${config.sslMode}',
    );
    final total = Stopwatch()..start();
    for (var attempt = 1; ; attempt++) {
      final db = Database.open(config, connectTimeout: connectTimeout);
      final sw = Stopwatch()..start();
      try {
        final version = await db.serverVersion();
        _log.info(
          'Postgres connected in ${sw.elapsedMilliseconds}ms '
          '(attempt $attempt/$attempts, total ${total.elapsedMilliseconds}ms) '
          'server=$version',
        );
        return db;
      } catch (e, st) {
        await db.close(reason: 'connect attempt $attempt failed');
        if (attempt >= attempts) {
          _log.severe(
            'Postgres connect failed $target (attempt $attempt/$attempts), '
            'giving up after ${total.elapsedMilliseconds}ms: ${describeError(e)}',
            e,
            st,
          );
          rethrow;
        }
        final delay = delays[min(attempt - 1, delays.length - 1)];
        _log.warning(
          'Postgres connect failed $target (attempt $attempt/$attempts) '
          'in ${sw.elapsedMilliseconds}ms: ${describeError(e)}; '
          'retry in ${delay.inMilliseconds}ms',
        );
        await Future<void>.delayed(delay);
      }
    }
  }

  final DatabaseConfig config;
  final Pool<void> _pool;

  /// Выполняет запрос. [what] — короткое описание для лога (по умолчанию
  /// начало SQL). [logParams] — параметры для лога, уже без секретов;
  /// сами [parameters] в лог не попадают.
  Future<Result> execute(
    String sql, {
    Object? parameters,
    String? what,
    Map<String, Object?>? logParams,
    Duration? timeout,
  }) async {
    final label = what ?? _shortSql(sql);
    final paramsText = logParams == null ? '' : ' ${formatContext(logParams)}';
    final sw = Stopwatch()..start();
    _log.fine('query $label$paramsText');
    try {
      final result = await _pool.execute(
        sql,
        parameters: parameters,
        timeout: timeout,
      );
      _log.fine(
        'query $label done rows=${result.length} '
        'affected=${result.affectedRows} in ${sw.elapsedMilliseconds}ms',
      );
      return result;
    } catch (e) {
      // Тип, сообщение и код — здесь; полный стек пишет вызывающий,
      // который решает, что делать с ошибкой (повтор, 503, 500).
      _log.warning(
        'query $label failed in ${sw.elapsedMilliseconds}ms: ${describeError(e)}',
      );
      rethrow;
    }
  }

  /// Проверка соединения для health: `SELECT 1` с таймаутом.
  Future<void> ping({Duration timeout = const Duration(seconds: 3)}) async {
    await execute('SELECT 1', what: 'ping', timeout: timeout).timeout(
      timeout,
      onTimeout: () =>
          throw TimeoutException('database ping timed out', timeout),
    );
  }

  /// Версия сервера PostgreSQL (`18.6`).
  Future<String> serverVersion() async {
    final result = await execute('SHOW server_version', what: 'server_version');
    return result.first.first.toString();
  }

  /// Закрывает пул. Ошибка закрытия пишется в лог и не пробрасывается:
  /// закрываемся мы всё равно.
  Future<void> close({String reason = 'shutdown'}) async {
    final sw = Stopwatch()..start();
    try {
      await _pool.close().timeout(const Duration(seconds: 5));
      _log.fine(
        'Postgres pool closed ($reason) in ${sw.elapsedMilliseconds}ms',
      );
    } catch (e, st) {
      _log.warning(
        'Postgres pool close failed ($reason) in ${sw.elapsedMilliseconds}ms, '
        'forcing: ${describeError(e)}',
        e,
        st,
      );
      await _pool.close(force: true);
    }
  }
}

String _shortSql(String sql) {
  final oneLine = sql.replaceAll(RegExp(r'\s+'), ' ').trim();
  return oneLine.length <= 60 ? '"$oneLine"' : '"${oneLine.substring(0, 60)}…"';
}
