import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/core/logging/ring_file_sink.dart';

void main() {
  late Directory dir;
  final errors = <String>[];

  setUp(() {
    dir = Directory.systemTemp.createTempSync('milionchik_log_test');
    errors.clear();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  RingFileSink open({int maxBytes = 100}) => RingFileSink.open(
    Directory('${dir.path}/logs'),
    maxBytes: maxBytes,
    onError: (message, error, stack) => errors.add('$message: $error'),
  );

  test('пишет строки в logs/app.log', () {
    final sink = open();
    sink.writeLine('first');
    sink.writeLine('второй');
    sink.close();
    expect(sink.currentFile.path, endsWith('app.log'));
    expect(sink.currentFile.readAsStringSync(), 'first\nвторой\n');
    expect(sink.previousFile.existsSync(), isFalse);
  });

  test(
    'при переполнении app.log становится app.log.1, файлов не больше двух',
    () {
      final sink = open(maxBytes: 20);
      // 'line-N\n' — 7 байт: в файл до 20 байт помещаются 2 строки.
      for (var i = 0; i < 10; i++) {
        sink.writeLine('line-$i');
      }
      sink.close();
      final logs = Directory('${dir.path}/logs').listSync();
      expect(logs, hasLength(2));
      expect(sink.currentFile.readAsStringSync(), 'line-8\nline-9\n');
      expect(sink.previousFile.readAsStringSync(), 'line-6\nline-7\n');
      expect(errors, isEmpty);
    },
  );

  test(
    'после перезапуска дописывает в существующий файл и учитывает его размер',
    () {
      final first = open(maxBytes: 20);
      first.writeLine('aaaaaaaaaaaaaa'); // 15 байт
      first.close();
      final second = open(maxBytes: 20);
      second.writeLine('bbbbbbb'); // 8 байт: 15 + 8 > 20 → ротация
      second.close();
      expect(second.previousFile.readAsStringSync(), 'aaaaaaaaaaaaaa\n');
      expect(second.currentFile.readAsStringSync(), 'bbbbbbb\n');
    },
  );

  test('сбой записи сообщается один раз и не роняет приложение', () {
    final sink = open();
    sink.close(); // запись в закрытый файл упадёт
    sink.writeLine('x');
    sink.writeLine('y');
    expect(errors, hasLength(1));
    expect(errors.single, contains('file logging disabled'));
  });
}
