import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/logging/app_logging.dart';
import 'package:milionchik/core/logging/crash_test.dart';
import 'package:milionchik/core/logging/error_reports.dart';
import 'package:milionchik/core/logging/logcat.dart';

void main() {
  late Directory dir;
  late List<String> console;
  late AppLogging logging;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('milionchik_app_logging');
    console = [];
  });
  tearDown(() async {
    await logging.dispose();
    dir.deleteSync(recursive: true);
  });

  test('строки до открытия файла попадают в файл из буфера', () {
    logging = AppLogging.start(
      levelValue: 'info',
      openLogcat: false,
      extraSink: console.add,
    );
    Logger('app').info('start version=0.1.0+1');
    Logger('app').fine('debug line is below level');
    final file = logging.attachFile(Directory('${dir.path}/logs'));
    Logger('app').info('logging ready');

    final lines = file.readAsLinesSync();
    expect(lines, hasLength(2));
    expect(
      lines[0],
      matches(RegExp(r'^\S+ INFO  \[app\] start version=0\.1\.0\+1$')),
    );
    expect(lines[1], endsWith('INFO  [app] logging ready'));
    expect(console, hasLength(2));
  });

  test('LOG_LEVEL=debug включает debug-строки', () {
    logging = AppLogging.start(
      levelValue: 'debug',
      openLogcat: false,
      extraSink: console.add,
    );
    expect(logging.levelName, 'debug');
    Logger('app').fine('step done in 3ms');
    expect(console.single, contains('DEBUG [app] step done in 3ms'));
  });

  test('неизвестный LOG_LEVEL → info и предупреждение', () {
    logging = AppLogging.start(
      levelValue: 'loud',
      openLogcat: false,
      extraSink: console.add,
    );
    expect(logging.levelName, 'info');
    expect(
      console.single,
      contains('WARN  [logging] unknown LOG_LEVEL "loud" → info'),
    );
  });

  test(
    'очередь отчётов: JSON-строка с типом, сообщением, стеком и устройством',
    () {
      logging = AppLogging.start(
        levelValue: 'info',
        openLogcat: false,
        extraSink: console.add,
      );
      final queue = ErrorReportQueue()
        ..context = {
          'appVersion': '0.1.0+1',
          'androidSdk': 36,
          'deviceModel': 'Pixel',
        };
      queue.add(
        'crash',
        StateError('boom'),
        StackTrace.fromString('#0 main (a.dart:1)'),
      );
      final file = File('${dir.path}/pending_reports.jsonl');
      queue.attach(file);

      final report =
          jsonDecode(file.readAsLinesSync().single) as Map<String, Object?>;
      expect(report['kind'], 'crash');
      expect(report['message'], 'StateError: Bad state: boom');
      expect(report['stack'], '#0 main (a.dart:1)');
      expect(report['appVersion'], '0.1.0+1');
      expect(report['androidSdk'], 36);
      expect(report['deviceModel'], 'Pixel');
      expect(console.last, contains('error report queued kind=crash'));
    },
  );

  test('CRASH_TEST работает только в debug', () {
    logging = AppLogging.start(
      levelValue: 'info',
      openLogcat: false,
      extraSink: console.add,
    );
    scheduleCrashTestIfRequested(flag: '1', debugBuild: false);
    expect(
      console.single,
      contains('CRASH_TEST=1 ignored: works only in debug builds'),
    );
    scheduleCrashTestIfRequested(flag: '', debugBuild: true);
    expect(console, hasLength(1));
  });

  group('splitForLogcat', () {
    test('по строкам', () {
      expect(splitForLogcat('a\nb\n  c'), ['a', 'b', '  c']);
    });

    test('длинная строка режется по байтам UTF-8 по границе символа', () {
      final chunks = splitForLogcat('ёёёёё', maxBytes: 4);
      expect(chunks, ['ёё', 'ёё', 'ё']);
      for (final chunk in chunks) {
        expect(utf8.encode(chunk).length, lessThanOrEqualTo(4));
      }
    });
  });

  test('не Android — logcat не открывается', () {
    logging = AppLogging.start(levelValue: 'info', openLogcat: false);
    expect(Logcat.open(), isNull);
  });
}
