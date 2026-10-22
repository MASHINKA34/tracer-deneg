import 'package:logging/logging.dart';
import 'package:shared/logging.dart';
import 'package:test/test.dart';

class _LeakyError implements Exception {
  _LeakyError(this.secret);

  final String secret;

  @override
  String toString() => '_LeakyError: row contains $secret';
}

class _BrokenFormatterError implements Exception {
  @override
  String toString() => '_BrokenFormatterError: secret-in-toString';
}

void main() {
  setUpAll(() {
    registerErrorTextFormatter(
      (e) => e is _LeakyError ? '_LeakyError: row contains (…)' : null,
    );
    registerErrorTextFormatter(
      (e) => e is _BrokenFormatterError ? throw StateError('oops') : null,
    );
  });

  test('текст ошибки берётся из форматтера вместо toString()', () {
    expect(
      describeError(_LeakyError('hunter2')),
      '_LeakyError: row contains (…)',
    );
  });

  test('форматтер вернул null → обычный toString()', () {
    expect(
      describeError(const FormatException('bad input')),
      'FormatException: bad input',
    );
  });

  test('строка error: в записи лога тоже без toString()', () {
    final record = LogRecord(
      Level.SEVERE,
      'query failed',
      'db',
      _LeakyError('hunter2'),
      StackTrace.current,
    );
    final text = formatLogRecord(record, utcOffset: Duration.zero);
    expect(text, contains('  error: _LeakyError: row contains (…)'));
    expect(text, isNot(contains('hunter2')));
  });

  test('упавший форматтер не откатывается на toString() с секретом', () {
    final text = describeError(_BrokenFormatterError());
    expect(
      text,
      contains('text formatter failed: StateError: Bad state: oops'),
    );
    expect(text, isNot(contains('secret-in-toString')));
  });

  test('повторная регистрация того же форматтера не дублирует его', () {
    var calls = 0;
    String? formatter(Object e) {
      calls++;
      return null;
    }

    registerErrorTextFormatter(formatter);
    registerErrorTextFormatter(formatter);
    expect(describeError(StateError('x')), 'StateError: Bad state: x');
    expect(calls, 1);
  });
}
