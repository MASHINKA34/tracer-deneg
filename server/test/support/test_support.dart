import 'dart:io';

import 'package:logging/logging.dart';
import 'package:server/config/config.dart';
import 'package:server/logging/log_setup.dart';

/// Тестовая база из deploy/docker-compose.test.yml (tool/check.ps1 её
/// поднимает). Другой адрес — переменная окружения `TEST_DATABASE_URL`.
String testDatabaseUrl() =>
    Platform.environment['TEST_DATABASE_URL'] ??
    'postgres://milionchik:milionchik@127.0.0.1:5433/milionchik_test?sslmode=disable';

DatabaseConfig testDatabaseConfig() => DatabaseConfig.parse(testDatabaseUrl());

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
