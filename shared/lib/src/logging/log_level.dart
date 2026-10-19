import 'package:logging/logging.dart';

/// Уровни лога проекта и соответствующие им уровни `package:logging`.
///
/// debug → FINE (каждый внутренний шаг), info → INFO (ключевые этапы),
/// warn → WARNING (нештатно, но обработано), error → SEVERE (сломалось).
const Map<String, Level> logLevelsByName = {
  'debug': Level.FINE,
  'info': Level.INFO,
  'warn': Level.WARNING,
  'error': Level.SEVERE,
};

/// Уровень по умолчанию, если `LOG_LEVEL` не задан.
const String defaultLogLevelName = 'info';

/// Разбирает значение `LOG_LEVEL` без учёта регистра и пробелов по краям.
/// Неизвестное значение → `null` (вызывающий пишет warn и берёт info).
Level? parseLogLevel(String? value) {
  if (value == null) return null;
  return logLevelsByName[value.trim().toLowerCase()];
}

/// Имя уровня для строки лога: DEBUG, INFO, WARN или ERROR.
String logLevelLabel(Level level) {
  if (level >= Level.SEVERE) return 'ERROR';
  if (level >= Level.WARNING) return 'WARN';
  if (level >= Level.INFO) return 'INFO';
  return 'DEBUG';
}

/// Имя уровня в формате `LOG_LEVEL` (для лога настроек при старте).
String logLevelName(Level level) => logLevelLabel(level).toLowerCase();
