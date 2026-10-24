import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/core/logging/app_logging.dart';
import 'package:milionchik/core/logging/device_info.dart';
import 'package:milionchik/core/logging/error_reporting.dart';
import 'package:milionchik/core/logging/error_reports.dart';
import 'package:milionchik/core/logging/log_tail.dart';
import 'package:milionchik/data/api/api_client.dart';
import 'package:milionchik/data/api/api_config.dart';
import 'package:milionchik/data/api/api_providers.dart';
import 'package:milionchik/data/api/token_store.dart';
import 'package:milionchik/features/profile/send_logs_service.dart';

import '../../data/api/fake_api_adapter.dart';

const ReportDevice _device = ReportDevice(
  appVersion: '0.1.0+1',
  device: DeviceInfo(
    sdkInt: 30,
    release: '11',
    model: 'sdk_gphone_x86_64',
    manufacturer: 'Google',
  ),
  buildMode: 'debug',
  logLevel: 'info',
);

const String _appOld =
    '2026-10-24T09:00:00.100+00:00 INFO  [app] start version=0.1.0+1 sdk=30';
const String _appMiddle =
    '2026-10-24T09:00:02.300+00:00 INFO  [sync] sync cycle start '
    'reason=startup attempt=1 queue=0';
const String _appNew =
    '2026-10-24T09:00:04.500+00:00 INFO  [nav] push month (from login)';
const String _bgStart =
    '2026-10-24T09:00:01.200+00:00 INFO  [bg] background task start '
    'name=sync-periodic reason=periodic every 30min';
const String _bgError =
    '2026-10-24T09:00:03.400+00:00 ERROR [bg] background job '
    'task=sync-periodic: sync crashed after 12ms';
const String _bgStack = '  #0      SyncEngine.sync (sync_engine.dart:310:7)';
const String _bgDebug =
    '2026-10-24T09:00:03.450+00:00 DEBUG [lock] lock released';
const String _bgEnd =
    '2026-10-24T09:00:05.600+00:00 INFO  [bg] background task end '
    'name=sync-periodic result=success handledBy=background isolate in 4400ms';

void main() {
  late Directory dir;
  late LogCapture logs;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('milionchik_send_bg_logs');
    logs = LogCapture();
    final logsDir = Directory('${dir.path}/logs')..createSync();
    File('${logsDir.path}/$appLogFileName.1').writeAsStringSync('$_appOld\n');
    File('${logsDir.path}/$appLogFileName')
        .writeAsStringSync('$_appMiddle\n$_appNew\n');
    File('${logsDir.path}/$backgroundLogFileName').writeAsStringSync(
      '$_bgStart\n$_bgError\n$_bgStack\n$_bgDebug\n$_bgEnd\n',
    );
  });

  tearDown(() async {
    await logs.dispose();
    dir.deleteSync(recursive: true);
  });

  Directory logsDir() => Directory('${dir.path}/logs');

  List<File> appFiles() => [
    File('${logsDir().path}/$appLogFileName.1'),
    File('${logsDir().path}/$appLogFileName'),
  ];

  test('«Отправить логи»: в отчёт попадают и строки фоновой задачи из '
      'bg.log, вперемешку с приложением по времени, стек остаётся при своей '
      'строке', () async {
    final adapter = FakeApiAdapter((call) {
      if (call.path.endsWith('/client-errors')) {
        return FakeReply.json(202, {'id': 'srv-user-report-bg'});
      }
      throw StateError('unexpected ${call.method} ${call.path}');
    });
    final container = ProviderContainer(
      overrides: [
        errorReportingProvider.overrideWithValue(
          ErrorReporting(
            queue: ErrorReportQueue(),
            device: _device,
            logFiles: appFiles,
            backgroundLogFiles: () => backgroundLogFilesIn(logsDir()),
          ),
        ),
        apiClientProvider.overrideWith(
          (ref) => ApiClient(
            config: ApiConfig.resolve(define: '', debugBuild: true),
            tokens: MemoryTokenStore(),
            adapter: adapter,
            newRequestId: () => 'ridsendbglogs001',
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final outcome = await container.read(sendLogsServiceProvider).send();

    expect(outcome, isA<LogsSent>());
    final sent = adapter.callsTo('/client-errors').single.json;
    expect(
      sent['logs'],
      [
        _appOld,
        _bgStart,
        _appMiddle,
        _bgError,
        _bgStack,
        _appNew,
        _bgEnd,
        '',
      ].join('\n'),
    );
    expect(sent['message'], contains('files=3'));
  });

  test('лимит хвоста считается по объединённым строкам: остаются самые '
      'новые из обоих файлов', () {
    final tail = readMergedLogTail([
      appFiles(),
      backgroundLogFilesIn(logsDir()),
    ], maxBytes: _appNew.length + _bgEnd.length + 2);

    expect(tail.text, '$_appNew\n$_bgEnd\n');
    expect(tail.truncated, isTrue);
    expect(tail.files, 3);
    expect(tail.debugLinesSkipped, 1);
  });
}
