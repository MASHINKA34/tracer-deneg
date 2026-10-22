import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:server/config/config.dart';
import 'package:server/db/database.dart';
import 'package:server/logging/log_setup.dart';
import 'package:shared/logging.dart';
import 'package:test/test.dart';

/// Тестовая база из deploy/docker-compose.test.yml (tool/check.ps1 её
/// поднимает). Другой адрес — переменная окружения `TEST_DATABASE_URL`.
String testDatabaseUrl() =>
    Platform.environment['TEST_DATABASE_URL'] ??
    'postgres://milionchik:milionchik@127.0.0.1:5433/milionchik_test?sslmode=disable';

DatabaseConfig testDatabaseConfig() => DatabaseConfig.parse(testDatabaseUrl());

Future<String> createScratchDatabase() async {
  final admin = testDatabaseConfig();
  final name = 'scratch_${generateRequestId()}';
  final db = Database.open(admin);
  try {
    await db.execute('CREATE DATABASE $name', what: 'create $name');
  } finally {
    await db.close(reason: 'scratch database created');
  }
  addTearDown(() async {
    final db = Database.open(admin);
    try {
      await db.execute(
        'DROP DATABASE IF EXISTS $name WITH (FORCE)',
        what: 'drop $name',
      );
    } finally {
      await db.close(reason: 'scratch database dropped');
    }
  });
  final password = admin.password == null
      ? ''
      : ':${Uri.encodeComponent(admin.password!)}';
  return 'postgres://${Uri.encodeComponent(admin.username)}$password'
      '@${admin.host}:${admin.port}/$name?sslmode=${admin.sslMode}';
}

Future<Database> openScratchDatabase() async {
  final db = Database.open(DatabaseConfig.parse(await createScratchDatabase()));
  addTearDown(() => db.close(reason: 'test done'));
  return db;
}

Future<void> waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final sw = Stopwatch()..start();
  while (!condition()) {
    if (sw.elapsed > timeout) {
      throw TimeoutException('condition not met', timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// Конфиг базы на порту, где точно никто не слушает.
Future<DatabaseConfig> deadDatabaseConfig() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return DatabaseConfig.parse(
    'postgres://milionchik:milionchik@127.0.0.1:$port/nothing?sslmode=disable',
  );
}

/// Собирает строки лога, которые пишет сервер, для проверок в тестах.
/// Строки также печатаются — при падении теста видно, что делал сервер.
class LogCapture {
  LogCapture({Level level = Level.FINE}) {
    setupServerLogging(
      level: level,
      writeLine: (line) {
        lines.add(line);
        print(line);
      },
    );
  }

  final List<String> lines = [];

  String get text => lines.join('\n');

  void clear() => lines.clear();
}
