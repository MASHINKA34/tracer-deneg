import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:shared/logging.dart';
import 'package:shared/logging_io.dart';

StreamSubscription<LogRecord>? _subscription;

/// Настраивает логирование сервера: формат 00-spec §13, вывод в stdout
/// (его ловит docker), уровень [level]. Повторный вызов заменяет вывод.
///
/// [writeLine] — куда писать строки (по умолчанию stdout; тесты подменяют).
void setupServerLogging({
  Level level = Level.INFO,
  void Function(String line)? writeLine,
}) {
  registerIoErrorDetails();
  registerErrorDetailsExtractor(postgresErrorDetails);
  Logger.root.level = level;
  final write = writeLine ?? stdout.writeln;
  unawaited(_subscription?.cancel());
  _subscription = Logger.root.onRecord.listen(
    (record) => write(formatLogRecord(record)),
  );
}

/// SQLSTATE и подробности ошибок PostgreSQL для лога.
Map<String, Object?>? postgresErrorDetails(Object error) => switch (error) {
  ServerException(:final code, :final detail, :final hint) => {
    'sqlState': code,
    'detail': detail,
    'hint': hint,
  },
  _ => null,
};
