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
  Database._(this.config, Pool<void> pool, this._connectTimeout)
    : _pool = pool,
      _poolSession = DbSession._(pool);

  /// Создаёт пул без проверки соединения: подключение произойдёт
  /// при первом запросе. Для старта сервера — [connect].
  factory Database.open(
    DatabaseConfig config, {
    Duration connectTimeout = const Duration(seconds: 5),
  }) {
    final pool = Pool<void>.withEndpoints(
      [_endpoint(config)],
      settings: PoolSettings(
        applicationName: _applicationName,
        maxConnectionCount: 10,
        connectTimeout: connectTimeout,
        sslMode: _sslMode(config),
      ),
    );
    return Database._(config, pool, connectTimeout);
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
  final DbSession _poolSession;
  final Duration _connectTimeout;

  /// Выполняет запрос. [what] — короткое описание для лога (по умолчанию
  /// начало SQL). [logParams] — параметры для лога, уже без секретов;
  /// сами [parameters] в лог не попадают.
  Future<Result> execute(
    String sql, {
    Object? parameters,
    String? what,
    Map<String, Object?>? logParams,
    Duration? timeout,
  }) => _poolSession.execute(
    sql,
    parameters: parameters,
    what: what,
    logParams: logParams,
    timeout: timeout,
  );

  Future<T> transaction<T>(
    String what,
    Future<T> Function(DbSession tx) body,
  ) => _runTransaction(_pool, what, body);

  Future<T> withConnection<T>(
    String what,
    Future<T> Function(DbConnection connection) body,
  ) async {
    final target = '${config.host}:${config.port}';
    final sw = Stopwatch()..start();
    _log.fine('opening dedicated connection for $what to $target');
    final Connection connection;
    try {
      connection = await Connection.open(
        _endpoint(config),
        settings: ConnectionSettings(
          applicationName: _applicationName,
          connectTimeout: _connectTimeout,
          sslMode: _sslMode(config),
        ),
      );
    } catch (e) {
      _log.warning(
        'dedicated connection for $what to $target failed '
        'in ${sw.elapsedMilliseconds}ms: ${describeError(e)}',
      );
      rethrow;
    }
    _log.fine(
      'dedicated connection for $what opened in ${sw.elapsedMilliseconds}ms',
    );
    try {
      return await body(DbConnection._(connection));
    } finally {
      final closeSw = Stopwatch()..start();
      try {
        await connection.close().timeout(const Duration(seconds: 5));
        _log.fine(
          'dedicated connection for $what closed '
          'in ${closeSw.elapsedMilliseconds}ms',
        );
      } catch (e, st) {
        _log.warning(
          'dedicated connection for $what close failed '
          'in ${closeSw.elapsedMilliseconds}ms, forcing: ${describeError(e)}',
          e,
          st,
        );
        await connection.close(force: true);
      }
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

class DbSession {
  DbSession._(this._session);

  final Session _session;

  Future<Result> execute(
    String sql, {
    Object? parameters,
    String? what,
    Map<String, Object?>? logParams,
    Duration? timeout,
    QueryMode? queryMode,
  }) async {
    final label = what ?? _shortSql(sql);
    final paramsText = logParams == null ? '' : ' ${formatContext(logParams)}';
    final sw = Stopwatch()..start();
    _log.fine('query $label$paramsText');
    try {
      final result = await _session.execute(
        sql,
        parameters: parameters,
        timeout: timeout,
        queryMode: queryMode,
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
}

class DbConnection extends DbSession {
  DbConnection._(Connection super._session) : _connection = _session, super._();

  final Connection _connection;

  Future<T> transaction<T>(
    String what,
    Future<T> Function(DbSession tx) body,
  ) => _runTransaction(_connection, what, body);
}

Future<T> _runTransaction<T>(
  SessionExecutor executor,
  String what,
  Future<T> Function(DbSession tx) body,
) async {
  final sw = Stopwatch()..start();
  _log.fine('transaction $what begin');
  try {
    final result = await executor.runTx((tx) => body(DbSession._(tx)));
    _log.fine('transaction $what committed in ${sw.elapsedMilliseconds}ms');
    return result;
  } catch (e) {
    _log.warning(
      'transaction $what rolled back in ${sw.elapsedMilliseconds}ms: '
      '${describeError(e)}',
    );
    rethrow;
  }
}

const _applicationName = 'milionchik-server';

Endpoint _endpoint(DatabaseConfig config) => Endpoint(
  host: config.host,
  port: config.port,
  database: config.database,
  username: config.username,
  password: config.password,
);

SslMode _sslMode(DatabaseConfig config) => switch (config.sslMode) {
  'require' => SslMode.require,
  'verify-full' => SslMode.verifyFull,
  _ => SslMode.disable,
};

String _shortSql(String sql) {
  final oneLine = sql.replaceAll(RegExp(r'\s+'), ' ').trim();
  return oneLine.length <= 60 ? '"$oneLine"' : '"${oneLine.substring(0, 60)}…"';
}
