import 'package:logging/logging.dart';
import 'package:shared/logging.dart';

import '../limits/trusted_proxies.dart';

/// Конфиг не прошёл проверку. [problems] — все найденные ошибки сразу,
/// чтобы не чинить их по одной за запуск.
class ConfigException implements Exception {
  ConfigException(this.problems);

  final List<String> problems;

  @override
  String toString() => 'ConfigException: ${problems.join('; ')}';
}

/// Подключение к PostgreSQL из `DATABASE_URL`
/// (`postgres://user:password@host:5432/db?sslmode=disable`).
class DatabaseConfig {
  const DatabaseConfig({
    required this.host,
    required this.port,
    required this.database,
    required this.username,
    required this.password,
    required this.sslMode,
  });

  /// Допустимые значения `sslmode`.
  static const sslModes = ['disable', 'require', 'verify-full'];

  final String host;
  final int port;
  final String database;
  final String username;
  final String? password;
  final String sslMode;

  /// Разбирает URL; при ошибке — [FormatException] с понятным текстом
  /// (без пароля).
  factory DatabaseConfig.parse(String url) {
    final Uri uri;
    try {
      uri = Uri.parse(url);
    } on FormatException catch (e) {
      throw FormatException('not a valid URL: ${e.message}');
    }
    if (uri.scheme != 'postgres' && uri.scheme != 'postgresql') {
      throw FormatException(
        'scheme must be postgres:// or postgresql://, got "${uri.scheme}"',
      );
    }
    if (uri.host.isEmpty) throw const FormatException('host is missing');
    final database = uri.path.startsWith('/')
        ? uri.path.substring(1)
        : uri.path;
    if (database.isEmpty) {
      throw const FormatException('database name is missing (…/dbname)');
    }
    final userInfo = uri.userInfo;
    final colon = userInfo.indexOf(':');
    final username = Uri.decodeComponent(
      colon >= 0 ? userInfo.substring(0, colon) : userInfo,
    );
    if (username.isEmpty) throw const FormatException('username is missing');
    final password = colon >= 0
        ? Uri.decodeComponent(userInfo.substring(colon + 1))
        : null;
    final sslMode = uri.queryParameters['sslmode'] ?? 'disable';
    if (!sslModes.contains(sslMode)) {
      throw FormatException(
        'sslmode must be one of ${sslModes.join('|')}, got "$sslMode"',
      );
    }
    return DatabaseConfig(
      host: uri.host,
      port: uri.hasPort ? uri.port : 5432,
      database: database,
      username: username,
      password: password,
      sslMode: sslMode,
    );
  }

  /// URL для лога: пароль заменён на `***`.
  String get masked {
    final auth = password == null ? username : '$username:***';
    return 'postgres://$auth@$host:$port/$database?sslmode=$sslMode';
  }
}

/// Настройки сервера из переменных окружения и `server/.env`.
class ServerConfig {
  const ServerConfig({
    required this.host,
    required this.port,
    required this.database,
    required this.logLevel,
    required this.jwtSecret,
    required this.inviteCodeSecret,
    this.migrationsDir = defaultMigrationsDir,
    this.trustedProxies = TrustedProxies.none,
    this.privacyContact,
    this.privacyOperator,
  });

  static const defaultHost = '0.0.0.0';
  static const defaultPort = 8080;
  static const minJwtSecretLength = 32;
  static const minInviteCodeSecretLength = 32;
  static const defaultMigrationsDir = 'migrations';

  final String host;
  final int port;
  final DatabaseConfig database;
  final Level logLevel;
  final String jwtSecret;
  final String inviteCodeSecret;
  final String migrationsDir;
  final TrustedProxies trustedProxies;
  final String? privacyContact;
  final String? privacyOperator;

  /// Разбирает и проверяет конфиг. [environment] (переменные окружения)
  /// важнее [dotEnv] (значения из файла `.env`).
  ///
  /// Обязательные: `DATABASE_URL`, `JWT_SECRET`. Необязательные: `HOST`
  /// (0.0.0.0), `PORT` (8080), `LOG_LEVEL` (info).
  factory ServerConfig.load({
    required Map<String, String> environment,
    Map<String, String> dotEnv = const {},
  }) {
    String? value(String key) {
      final v = environment[key] ?? dotEnv[key];
      return (v == null || v.trim().isEmpty) ? null : v.trim();
    }

    final problems = <String>[];

    final host = value('HOST') ?? defaultHost;

    var port = defaultPort;
    final rawPort = value('PORT');
    if (rawPort != null) {
      final parsed = int.tryParse(rawPort);
      if (parsed == null || parsed < 0 || parsed > 65535) {
        problems.add('PORT must be a number 0..65535, got "$rawPort"');
      } else {
        port = parsed;
      }
    }

    var logLevel = Level.INFO;
    final rawLevel = value('LOG_LEVEL');
    if (rawLevel != null) {
      final parsed = parseLogLevel(rawLevel);
      if (parsed == null) {
        problems.add(
          'LOG_LEVEL must be one of ${logLevelsByName.keys.join('|')}, got "$rawLevel"',
        );
      } else {
        logLevel = parsed;
      }
    }

    DatabaseConfig? database;
    final rawUrl = value('DATABASE_URL');
    if (rawUrl == null) {
      problems.add(
        'DATABASE_URL is required (postgres://user:password@host:5432/db)',
      );
    } else {
      try {
        database = DatabaseConfig.parse(rawUrl);
      } on FormatException catch (e) {
        problems.add('DATABASE_URL is invalid: ${e.message}');
      }
    }

    final jwtSecret = value('JWT_SECRET');
    if (jwtSecret == null) {
      problems.add(
        'JWT_SECRET is required (random string, ≥ $minJwtSecretLength chars)',
      );
    } else if (jwtSecret.length < minJwtSecretLength) {
      problems.add(
        'JWT_SECRET is too short (${jwtSecret.length} chars), need ≥ $minJwtSecretLength',
      );
    }

    final inviteCodeSecret = value('INVITE_CODE_SECRET');
    if (inviteCodeSecret == null) {
      problems.add(
        'INVITE_CODE_SECRET is required (random string, '
        '≥ $minInviteCodeSecretLength chars)',
      );
    } else if (inviteCodeSecret.length < minInviteCodeSecretLength) {
      problems.add(
        'INVITE_CODE_SECRET is too short (${inviteCodeSecret.length} chars), '
        'need ≥ $minInviteCodeSecretLength',
      );
    }

    var trustedProxies = TrustedProxies.none;
    try {
      trustedProxies = TrustedProxies.parse(value('TRUSTED_PROXIES'));
    } on FormatException catch (e) {
      problems.add('TRUSTED_PROXIES is invalid: ${e.message}');
    }

    if (problems.isNotEmpty) throw ConfigException(problems);
    return ServerConfig(
      host: host,
      port: port,
      database: database!,
      logLevel: logLevel,
      jwtSecret: jwtSecret!,
      inviteCodeSecret: inviteCodeSecret!,
      migrationsDir: value('MIGRATIONS_DIR') ?? defaultMigrationsDir,
      trustedProxies: trustedProxies,
      privacyContact: value('PRIVACY_CONTACT'),
      privacyOperator: value('PRIVACY_OPERATOR'),
    );
  }

  /// Настройки для лога старта — секреты замаскированы.
  Map<String, Object?> toLogContext() => {
    'host': host,
    'port': port,
    'log': logLevelName(logLevel),
    'db': database.masked,
    'jwtSecret': maskToken(jwtSecret),
    'inviteCodeSecret': maskToken(inviteCodeSecret),
    'migrations': migrationsDir,
    'trustedProxies': trustedProxies.describe(),
    'privacyContact': privacyContact == null ? 'empty' : 'set',
    'privacyOperator': privacyOperator == null ? 'empty' : 'set',
  };
}
