import 'package:logging/logging.dart';

import 'error_details.dart';
import 'log_level.dart';
import 'request_id.dart';

final RegExp _needsQuotes = RegExp(r'[\s"=]');

/// Контекст `key=value` через пробел. Значения с пробелами, кавычками
/// или `=` берутся в кавычки, `null` пропускается.
///
/// `formatContext({'cursor': 1234, 'path': 'a b'})` → `cursor=1234 path="a b"`.
String formatContext(Map<String, Object?> context) {
  final parts = <String>[];
  context.forEach((key, value) {
    if (value == null) return;
    var text = value.toString();
    if (text.isEmpty || _needsQuotes.hasMatch(text)) {
      text =
          '"${text.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll('\n', r'\n')}"';
    }
    parts.add('$key=$text');
  });
  return parts.join(' ');
}

/// Время строки лога: `2026-10-19T18:40:12.345+03:00`.
///
/// По умолчанию — местное время машины со смещением пояса;
/// [utcOffset] задаёт смещение явно (для тестов).
String formatLogTime(DateTime time, {Duration? utcOffset}) {
  final offset = utcOffset ?? time.toLocal().timeZoneOffset;
  final t = time.toUtc().add(offset);
  String two(int v) => v.toString().padLeft(2, '0');
  final sign = offset.isNegative ? '-' : '+';
  final offsetMinutes = offset.inMinutes.abs();
  return '${t.year.toString().padLeft(4, '0')}-${two(t.month)}-${two(t.day)}'
      'T${two(t.hour)}:${two(t.minute)}:${two(t.second)}'
      '.${t.millisecond.toString().padLeft(3, '0')}'
      '$sign${two(offsetMinutes ~/ 60)}:${two(offsetMinutes % 60)}';
}

/// Запись лога по формату 00-spec §13.
///
/// Первая строка: время, уровень, `[модуль]`, сообщение и `rid=…`, если запись
/// сделана внутри [runWithRequestId]. Если есть ошибка — ниже строки
/// `error: <тип: сообщение подробности>` (если этого текста ещё нет
/// в сообщении) и `stack:` с полным стеком.
String formatLogRecord(LogRecord record, {Duration? utcOffset}) {
  final module = record.loggerName.isEmpty ? 'root' : record.loggerName;
  final buffer = StringBuffer()
    ..write(formatLogTime(record.time, utcOffset: utcOffset))
    ..write(' ')
    ..write(logLevelLabel(record.level).padRight(5))
    ..write(' [$module] ')
    ..write(record.message);

  final rid = requestIdOf(record.zone);
  if (rid != null && !record.message.contains('rid=')) {
    buffer.write(' rid=$rid');
  }

  final error = record.error;
  if (error != null) {
    final description = describeError(error);
    if (!record.message.contains(description)) {
      buffer.write('\n  error: $description');
    }
  }

  final stack = record.stackTrace ?? (error is Error ? error.stackTrace : null);
  final stackText = stack?.toString().trimRight() ?? '';
  if (stackText.isNotEmpty) {
    buffer.write('\n  stack:');
    for (final line in stackText.split('\n')) {
      buffer.write('\n    ${line.trimRight()}');
    }
  }
  return buffer.toString();
}
