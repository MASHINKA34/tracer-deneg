import 'log_format.dart';

/// Достаёт из ошибки поля, которых нет в `toString()` (код, errno, cause…).
/// Возвращает `null`, если ошибка не его типа.
typedef ErrorDetailsExtractor = Map<String, Object?>? Function(Object error);

final List<ErrorDetailsExtractor> _extractors = [];

typedef ErrorTextFormatter = String? Function(Object error);

final List<ErrorTextFormatter> _formatters = [];

void registerErrorTextFormatter(ErrorTextFormatter formatter) {
  if (!_formatters.contains(formatter)) _formatters.add(formatter);
}

String? _formattedText(Object error) {
  for (final formatter in _formatters) {
    try {
      final text = formatter(error);
      if (text != null) return text;
    } catch (e) {
      return '<text formatter failed: ${e.runtimeType}: $e>';
    }
  }
  return null;
}

/// Регистрирует извлекатель подробностей. Платформенный код (сервер,
/// приложение) добавляет свои: ошибки `dart:io`, Postgres, платформенные каналы.
void registerErrorDetailsExtractor(ErrorDetailsExtractor extractor) {
  if (!_extractors.contains(extractor)) _extractors.add(extractor);
}

/// Подробности ошибки от всех зарегистрированных извлекателей.
///
/// Если извлекатель сам упал, его падение попадает в результат
/// (`detailsError=…`), а не теряется.
Map<String, Object?> errorDetails(Object error) {
  final result = <String, Object?>{};
  for (final extractor in _extractors) {
    try {
      final details = extractor(error);
      if (details != null) result.addAll(details);
    } catch (e) {
      result['detailsError'] = '${e.runtimeType}: $e';
    }
  }
  return result;
}

/// Ошибка одной строкой: тип, сообщение и подробности.
///
/// Пример: `StateError: Bad state: boom`,
/// `SocketException: Connection refused (…) errno=10061`.
String describeError(Object? error) {
  if (error == null) return 'null';
  final type = error.runtimeType.toString();
  String text;
  final formatted = _formattedText(error);
  if (formatted != null) {
    text = formatted;
  } else {
    try {
      text = error.toString();
    } catch (e) {
      text = '<toString() failed: ${e.runtimeType}: $e>';
    }
  }
  if (text.startsWith('$type: ')) text = text.substring(type.length + 2);
  if (text == type) text = '';

  final buffer = StringBuffer(type);
  if (text.isNotEmpty) buffer.write(': $text');
  final details = errorDetails(error);
  if (details.isNotEmpty) buffer.write(' ${formatContext(details)}');
  return buffer.toString();
}
