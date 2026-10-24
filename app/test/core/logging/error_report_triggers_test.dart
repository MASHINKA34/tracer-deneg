import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/logging/error_report_triggers.dart';
import 'package:milionchik/core/logging/error_reporting.dart';
import 'package:milionchik/core/logging/error_reports.dart';
import 'package:milionchik/core/network_status.dart';
import 'package:milionchik/data/api/api_client.dart';
import 'package:milionchik/data/api/api_config.dart';
import 'package:milionchik/data/api/api_providers.dart';
import 'package:milionchik/data/api/token_store.dart';

import '../../data/api/fake_api_adapter.dart';

final class _Scope {
  _Scope(this.tester, this.dir, {required this.online});

  final WidgetTester tester;
  final Directory dir;
  bool online;
  final StreamController<List<ConnectivityResult>> network =
      StreamController<List<ConnectivityResult>>.broadcast();
  late final FakeApiAdapter adapter = FakeApiAdapter((call) {
    if (!online) throw const SocketException('Network is unreachable');
    return FakeReply.json(202, {'id': 'srv-1'});
  });
  late final ErrorReportQueue queue = ErrorReportQueue()
    ..context = const {'appVersion': '0.1.0+1'}
    ..attach(file);
  int networkReads = 0;

  File get file => File('${dir.path}/pending_reports.jsonl');

  int get queued => file.existsSync() ? file.readAsLinesSync().length : 0;

  Future<void> mount({bool reporting = true}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          if (reporting)
            errorReportingProvider.overrideWithValue(
              ErrorReporting(
                queue: queue,
                device: ReportDevice.unknown,
                logFiles: () => const [],
              ),
            ),
          networkChangesProvider.overrideWith((ref) {
            networkReads++;
            return network.stream;
          }),
          apiClientProvider.overrideWith(
            (ref) => ApiClient(
              config: ApiConfig.resolve(define: '', debugBuild: true),
              tokens: MemoryTokenStore(),
              adapter: adapter,
              newRequestId: () => 'ridtriggers000001',
            ),
          ),
        ],
        child: const ErrorReportTriggersScope(child: SizedBox()),
      ),
    );
    await settle();
  }

  Future<void> emit(List<ConnectivityResult> results) async {
    network.add(results);
    await settle();
  }

  Future<void> settle() async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
    }
  }

  Future<void> dispose() async {
    await tester.pumpWidget(const SizedBox());
    await network.close();
  }
}

void main() {
  late Directory dir;
  late LogCapture logs;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('milionchik_report_triggers');
    logs = LogCapture();
  });
  tearDown(() async {
    await logs.dispose();
    dir.deleteSync(recursive: true);
  });

  testWidgets('при старте без сети отчёт остаётся; сеть появилась - ушёл и '
      'удалён из файла', (tester) async {
    final s = _Scope(tester, dir, online: false);
    s.queue.add('crash', StateError('offline'), null);

    await s.mount();

    expect(s.adapter.callsTo('/client-errors'), hasLength(1));
    expect(s.queued, 1);

    await s.emit(const [ConnectivityResult.none]);
    expect(s.adapter.callsTo('/client-errors'), hasLength(1));

    s.online = true;
    await s.emit(const [ConnectivityResult.wifi]);

    expect(s.adapter.callsTo('/client-errors'), hasLength(2));
    expect(s.queued, 0);
    expect(
      logs.linesOf('errors', Level.INFO),
      containsAllInOrder([
        endsWith('error reports sending count=1 reason=start session=no'),
        endsWith('network appeared types=wifi → sending queued error reports'),
        endsWith('error reports sending count=1 reason=network session=no'),
        matches(
          r'error reports done sent=1 dropped=0 left=0 of 1 reason=network '
          r'in \d+ms$',
        ),
      ]),
    );
    await s.dispose();
  });

  testWidgets('первое событие сети - только точка отсчёта, повторной '
      'отправки нет; потеря сети - в логе', (tester) async {
    final s = _Scope(tester, dir, online: true);
    s.queue.add('crash', StateError('online'), null);

    await s.mount();
    await s.emit(const [ConnectivityResult.mobile]);
    await s.emit(const [ConnectivityResult.none]);

    expect(s.adapter.callsTo('/client-errors'), hasLength(1));
    expect(s.queued, 0);
    expect(
      logs.linesOf('errors', Level.INFO),
      contains(endsWith('network lost types=none → reports wait for network')),
    );
    await s.dispose();
  });

  testWidgets('без очереди отчётов в scope - ни запросов, ни подписки на '
      'сеть', (tester) async {
    final s = _Scope(tester, dir, online: true);

    await s.mount(reporting: false);

    expect(s.adapter.calls, isEmpty);
    expect(s.networkReads, 0);
    expect(
      logs.linesOf('errors'),
      contains(
        endsWith('error report sending off: no report queue in this scope'),
      ),
    );
    await s.dispose();
  });
}
