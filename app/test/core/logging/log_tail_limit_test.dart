import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/core/logging/log_tail.dart';
import 'package:shared/shared.dart';

String _info(int i) =>
    '2026-10-24T10:00:${(i % 60).toString().padLeft(2, '0')}.000+03:00 '
    'INFO  [sync] step number=$i done';

String _debug(String text) => '2026-10-24T10:00:00.000+03:00 DEBUG [db] $text';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('milionchik_tail'));
  tearDown(() => dir.deleteSync(recursive: true));

  File write(String name, String text) =>
      File('${dir.path}/$name')..writeAsStringSync(text);

  test('лимит по умолчанию - maxClientErrorLogsBytes, хвост не длиннее '
      'лимита и начинается с целой строки, последняя строка на месте', () {
    final lines = [for (var i = 0; i < 6000; i++) _info(i)];
    final current = write('app.log', '${lines.join('\n')}\n');
    expect(current.lengthSync(), greaterThan(maxClientErrorLogsBytes));

    final tail = readLogTail([current]);

    expect(tail.bytes, utf8.encode(tail.text).length);
    expect(tail.bytes, lessThanOrEqualTo(maxClientErrorLogsBytes));
    expect(tail.bytes, greaterThan(maxClientErrorLogsBytes - 100));
    expect(tail.truncated, isTrue);
    expect(tail.sourceBytes, current.lengthSync());
    final kept = const LineSplitter().convert(tail.text);
    expect(kept.last, lines.last);
    expect(lines, contains(kept.first));
    expect(kept, lines.sublist(lines.length - kept.length));
  });

  test('app.log.1 идёт раньше app.log, в лимит влезают свежие строки '
      'из обоих файлов', () {
    final previous = write('app.log.1', '${_info(1)}\n${_info(2)}\n');
    final current = write('app.log', '${_info(3)}\n${_info(4)}\n');
    final size = utf8.encode('${_info(2)}\n${_info(3)}\n${_info(4)}\n').length;

    final tail = readLogTail([previous, current], maxBytes: size);

    expect(tail.text, '${_info(2)}\n${_info(3)}\n${_info(4)}\n');
    expect(tail.files, 2);
    expect(tail.truncated, isTrue);
  });

  test('DEBUG-записи вместе с их стеком не уходят, ошибки со стеком '
      'остаются', () {
    final source = [
      _info(1),
      _debug('expense create amount=98765400 outbox=upsert#3'),
      '  stack:',
      '    #0 debug frame (package:milionchik/a.dart:1)',
      '2026-10-24T10:00:01.000+03:00 ERROR [errors] uncaught error: StateError',
      '  error: StateError: Bad state: boom',
      '  stack:',
      '    #0 main (package:milionchik/main.dart:1)',
      _info(2),
    ].join('\n');
    final current = write('app.log', '$source\n');

    final tail = readLogTail([current]);

    expect(tail.text, isNot(contains('98765400')));
    expect(tail.text, isNot(contains('debug frame')));
    expect(tail.debugLinesSkipped, 3);
    expect(const LineSplitter().convert(tail.text), [
      _info(1),
      '2026-10-24T10:00:01.000+03:00 ERROR [errors] uncaught error: StateError',
      '  error: StateError: Bad state: boom',
      '  stack:',
      '    #0 main (package:milionchik/main.dart:1)',
      _info(2),
    ]);
    expect(tail.truncated, isFalse);
  });

  test('UTF-8: лимит считается в байтах, одна огромная строка режется по '
      'границе символа с конца', () {
    final line = '2026-10-24T10:00:00.000+03:00 INFO  [app] ${'ё' * 300}';

    final tail = logTailOf('$line\n', maxBytes: 101);

    expect(utf8.encode(tail.text).length, lessThanOrEqualTo(101));
    expect(tail.text, 'ё' * 50);
    expect(tail.truncated, isTrue);
  });

  test('нет файлов - пустой хвост без ошибки', () {
    final tail = readLogTail([File('${dir.path}/app.log')]);

    expect(tail.text, isEmpty);
    expect(tail.files, 0);
  });
}
