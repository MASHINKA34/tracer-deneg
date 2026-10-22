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
  registerErrorTextFormatter(postgresErrorText);
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
    'detail': detail == null ? null : redactPostgresDetail(detail),
    'hint': hint,
  },
  _ => null,
};

String? postgresErrorText(Object error) {
  if (error is! ServerException) return null;
  final message = (error.code ?? '').startsWith('22')
      ? error.message.replaceAll(RegExp(r'"[^"]*"'), '"…"')
      : error.message;
  final buffer = StringBuffer('${error.severity} ${error.code}: $message');
  if (error.tableName != null) buffer.write(' table: ${error.tableName}');
  if (error.columnName != null) buffer.write(' column: ${error.columnName}');
  if (error.constraintName != null) {
    buffer.write(' constraint ${error.constraintName}');
  }
  return buffer.toString();
}

String redactPostgresDetail(String detail) => detail.replaceAllMapped(
  RegExp(r'(=|contains )\(.*\)', dotAll: true),
  (match) => '${match[1]}(…)',
);
