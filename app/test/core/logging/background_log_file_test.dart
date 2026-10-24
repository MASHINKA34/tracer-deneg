import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/background_entry.dart';
import 'package:milionchik/core/isolate_lock.dart';
import 'package:milionchik/core/logging/app_logging.dart';

const int _lines = 400;

final String _filler = 'x' * 60;

final RegExp _record = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\S+ (DEBUG|INFO|WARN|ERROR) +\[[a-z]+\] ',
);

typedef _Writer = (String dir, String lock, String who, SendPort done);

Future<void> _backgroundWriter(_Writer message) async {
  final (dir, lock, who, done) = message;
  final isolate = BackgroundIsolate.start(
    logsDir: () async => Directory(dir),
    logLock: IsolateLock(lock),
  );
  final log = await isolate.openLog('background writer $who');
  for (var i = 0; i < _lines; i++) {
    Logger('bg').info('$who line ${i.toString().padLeft(4, '0')} $_filler end');
    if (i % 7 == 0) await Future<void>.delayed(Duration.zero);
  }
  log.close('test writer $who done');
  done.send(who);
}

Future<String> _spawnWriter(String dir, String lock, String who) async {
  final done = ReceivePort();
  await Isolate.spawn(_backgroundWriter, (dir, lock, who, done.sendPort));
  final answer = await done.first as String;
  done.close();
  return answer;
}

List<int> _ids(List<String> lines, String logger, String who) {
  final pattern = RegExp(
    '^\\S+ INFO  \\[$logger\\] $who line (\\d{4}) $_filler end\$',
  );
  return [
    for (final line in lines)
      if (pattern.firstMatch(line) case final m?) int.parse(m.group(1)!),
  ];
}

var _locks = 0;

void main() {
  late Directory dir;
  late AppLogging app;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('milionchik_bg_log_');
    app = AppLogging.start(levelValue: 'info', openLogcat: false);
  });

  tearDown(() async {
    await app.dispose();
    dir.deleteSync(recursive: true);
  });

  test('приложение и фоновая задача пишут одновременно: каждая в свой файл, '
      'ни одна строка не потеряна и не обрезана', () async {
    final logsDir = Directory('${dir.path}/logs');
    final appFile = app.attachFile(logsDir);
    final background = _spawnWriter(
      logsDir.path,
      'test.bg-log.${_locks++}',
      'bgr',
    );
    for (var i = 0; i < _lines; i++) {
      Logger('app')
          .info('app line ${i.toString().padLeft(4, '0')} $_filler end');
      if (i % 5 == 0) await Future<void>.delayed(Duration.zero);
    }
    await background;
    app.detachFile();

    final appLines = appFile.readAsLinesSync();
    final bgLines = File('${logsDir.path}/$backgroundLogFileName')
        .readAsLinesSync();
    expect(appFile.path, endsWith(appLogFileName));
    expect(_ids(appLines, 'app', 'app'), List.generate(_lines, (i) => i));
    expect(_ids(bgLines, 'bg', 'bgr'), List.generate(_lines, (i) => i));
    expect(appLines.where((l) => l.contains('[bg]')), isEmpty);
    expect(bgLines.where((l) => l.contains('[app]')), isEmpty);
    for (final line in [...appLines, ...bgLines]) {
      expect(line, matches(_record));
    }
    expect(bgLines, contains(contains('background log file ready file=')));
  });

  test('две фоновые задачи сразу: вторая ждёт замок файла, строки обеих '
      'целы в bg.log', () async {
    final logsDir = Directory('${dir.path}/logs');
    final lock = 'test.bg-log.${_locks++}';
    final both = await Future.wait([
      _spawnWriter(logsDir.path, lock, 'one'),
      _spawnWriter(logsDir.path, lock, 'two'),
    ]);

    final bgLines = File('${logsDir.path}/$backgroundLogFileName')
        .readAsLinesSync();
    expect(both, ['one', 'two']);
    expect(_ids(bgLines, 'bg', 'one'), List.generate(_lines, (i) => i));
    expect(_ids(bgLines, 'bg', 'two'), List.generate(_lines, (i) => i));
    for (final line in bgLines) {
      expect(line, matches(_record));
    }
    expect(
      bgLines,
      contains(
        matches(
          RegExp(
            r'background log file ready file=\S+ \(app log stays app\.log, '
            r'one writer per file\) after waiting \d+ms for background '
            r'writer (one|two) in \d+ms$',
          ),
        ),
      ),
    );
  });
}
