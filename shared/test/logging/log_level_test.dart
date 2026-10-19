import 'package:logging/logging.dart';
import 'package:shared/logging.dart';
import 'package:test/test.dart';

void main() {
  test('parseLogLevel: четыре уровня без учёта регистра', () {
    expect(parseLogLevel('debug'), Level.FINE);
    expect(parseLogLevel('INFO'), Level.INFO);
    expect(parseLogLevel(' Warn '), Level.WARNING);
    expect(parseLogLevel('error'), Level.SEVERE);
  });

  test('parseLogLevel: неизвестное и пустое → null', () {
    expect(parseLogLevel('verbose'), isNull);
    expect(parseLogLevel(''), isNull);
    expect(parseLogLevel(null), isNull);
  });

  test('logLevelName возвращает имя для LOG_LEVEL', () {
    for (final entry in logLevelsByName.entries) {
      expect(logLevelName(entry.value), entry.key);
    }
  });

  test('уровень по умолчанию — info', () {
    expect(parseLogLevel(defaultLogLevelName), Level.INFO);
  });
}
