import 'dart:async';

import 'package:logging/logging.dart';
import 'package:shared/logging.dart';
import 'package:test/test.dart';

class _CodedError implements Exception {
  _CodedError(this.code);
  final String code;
  @override
  String toString() => '_CodedError: failed';
}

void main() {
  group('formatLogTime', () {
    final instant = DateTime.utc(2026, 10, 19, 15, 40, 12, 345);

    test('положительное смещение пояса', () {
      expect(
        formatLogTime(instant, utcOffset: const Duration(hours: 3)),
        '2026-10-19T18:40:12.345+03:00',
      );
    });

    test('отрицательное смещение с минутами', () {
      expect(
        formatLogTime(
          instant,
          utcOffset: const Duration(hours: -5, minutes: -30),
        ),
        '2026-10-19T10:10:12.345-05:30',
      );
    });

    test('нулевое смещение и миллисекунды с нулями', () {
      expect(
        formatLogTime(
          DateTime.utc(2026, 1, 2, 3, 4, 5, 7),
          utcOffset: Duration.zero,
        ),
        '2026-01-02T03:04:05.007+00:00',
      );
    });
  });

  group('formatContext', () {
    test('простые значения, null пропускается', () {
      expect(
        formatContext({'cursor': 1234, 'skip': null, 'ok': true}),
        'cursor=1234 ok=true',
      );
    });

    test('значения с пробелами, кавычками и переводом строки — в кавычках', () {
      expect(
        formatContext({'path': 'a b', 'q': 'say "hi"', 'e': '', 'nl': 'x\ny'}),
        r'path="a b" q="say \"hi\"" e="" nl="x\ny"',
      );
    });
  });

  group('formatLogRecord', () {
    const offset = Duration(hours: 3);

    test('строка по формату §13', () {
      final record = LogRecord(Level.INFO, 'pull done cursor=1234', 'sync');
      final line = formatLogRecord(record, utcOffset: offset);
      expect(
        line,
        matches(
          RegExp(
            r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}\+03:00 INFO  \[sync\] pull done cursor=1234$',
          ),
        ),
      );
    });

    test('уровни: DEBUG, WARN, ERROR выровнены по 5 символам', () {
      String levelOf(Level level) => formatLogRecord(
        LogRecord(level, 'm', 'x'),
        utcOffset: offset,
      ).substring(30, 36);
      expect(levelOf(Level.FINE), 'DEBUG ');
      expect(levelOf(Level.INFO), 'INFO  ');
      expect(levelOf(Level.WARNING), 'WARN  ');
      expect(levelOf(Level.SEVERE), 'ERROR ');
      expect(levelOf(Level.SHOUT), 'ERROR ');
    });

    test('пустое имя логгера → [root]', () {
      final line = formatLogRecord(
        LogRecord(Level.INFO, 'm', ''),
        utcOffset: offset,
      );
      expect(line, contains(' [root] m'));
    });

    test('rid из зоны записи дописывается в конец', () {
      late LogRecord record;
      runWithRequestId('abc123', () {
        record = LogRecord(
          Level.INFO,
          'GET /x',
          'http',
          null,
          null,
          Zone.current,
        );
      });
      expect(
        formatLogRecord(record, utcOffset: offset),
        endsWith('GET /x rid=abc123'),
      );
    });

    test('rid не дублируется, если уже есть в сообщении', () {
      late LogRecord record;
      runWithRequestId('abc123', () {
        record = LogRecord(
          Level.INFO,
          'x rid=abc123',
          'http',
          null,
          null,
          Zone.current,
        );
      });
      expect(
        'rid='.allMatches(formatLogRecord(record, utcOffset: offset)).length,
        1,
      );
    });

    test('ошибка и стек — отдельными строками с отступом', () {
      final stack = StackTrace.fromString(
        '#0 main (file:///a.dart:1:2)\n#1 run (file:///b.dart:3:4)\n',
      );
      final record = LogRecord(
        Level.SEVERE,
        'request failed',
        'http',
        StateError('boom'),
        stack,
      );
      final lines = formatLogRecord(record, utcOffset: offset).split('\n');
      expect(lines[0], endsWith('ERROR [http] request failed'));
      expect(lines[1], '  error: StateError: Bad state: boom');
      expect(lines[2], '  stack:');
      expect(lines[3], '    #0 main (file:///a.dart:1:2)');
      expect(lines[4], '    #1 run (file:///b.dart:3:4)');
      expect(lines, hasLength(5));
    });

    test('строка error: не повторяет описание, уже вписанное в сообщение', () {
      final error = StateError('boom');
      final record = LogRecord(
        Level.WARNING,
        'connect failed: ${describeError(error)}; retry in 1s',
        'db',
        error,
      );
      final text = formatLogRecord(record, utcOffset: offset);
      expect(text, endsWith('connect failed: StateError: Bad state: boom; retry in 1s'));
      expect(text, isNot(contains('\n  error:')));
    });

    test('стек берётся из Error, если в записи его нет', () {
      Object? caught;
      try {
        throw ArgumentError('bad');
      } catch (e) {
        caught = e;
      }
      final record = LogRecord(Level.SEVERE, 'x', 'm', caught);
      final text = formatLogRecord(record, utcOffset: offset);
      expect(
        text,
        contains('  error: ArgumentError: Invalid argument(s): bad'),
      );
      expect(text, contains('  stack:\n    #0'));
    });
  });

  group('describeError', () {
    test('тип не повторяется, если уже есть в toString()', () {
      expect(describeError(_CodedError('E1')), '_CodedError: failed');
    });

    test('подробности от извлекателя дописываются как key=value', () {
      registerErrorDetailsExtractor(
        (e) => e is _CodedError ? {'code': e.code} : null,
      );
      expect(describeError(_CodedError('E42')), '_CodedError: failed code=E42');
    });

    test('упавший извлекатель не теряет ошибку', () {
      registerErrorDetailsExtractor(
        (e) => e is FormatException ? throw StateError('oops') : null,
      );
      expect(
        describeError(const FormatException('bad input')),
        'FormatException: bad input detailsError="StateError: Bad state: oops"',
      );
    });

    test('null', () {
      expect(describeError(null), 'null');
    });
  });
}
