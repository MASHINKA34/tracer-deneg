import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/isolate_lock.dart';
import 'package:milionchik/data/sync/app_isolate_link.dart';
import 'package:milionchik/data/sync/background_job.dart';
import 'package:milionchik/data/sync/background_task_runner.dart';

import '../api/fake_api_adapter.dart';

var _names = 0;

BackgroundJobResult _result(String task, BackgroundJobOutcome outcome) =>
    BackgroundJobResult(
      task: task,
      outcome: outcome,
      sync: 'done sent=1 applied=1 entities=0',
      recurring: 'created=0',
      widget: 'ok',
      errors: 0,
      elapsed: const Duration(milliseconds: 7),
    );

final class _Rig {
  _Rig() : id = _names++;

  final int id;
  late final IsolateLock jobLock = IsolateLock('test.bg-job.$id');
  late final String appName = 'test.app.$id';
  final List<String> standaloneRuns = [];
  final List<String?> holderDuringStandalone = [];
  final List<String> appRuns = [];
  final List<String?> holderDuringApp = [];

  BackgroundTaskRunner runner({Duration ack = isolateAckTimeout}) =>
      BackgroundTaskRunner(
        jobLock: jobLock,
        app: AppIsolateClient(name: appName, ackTimeout: ack),
        standalone: (task, reason) async {
          standaloneRuns.add('$task: $reason');
          holderDuringStandalone.add(await jobLock.holder());
          return _result(task, BackgroundJobOutcome.success);
        },
      );

  AppIsolateHost host(
    Future<BackgroundJobResult> Function(String task, String reason) job,
  ) => AppIsolateHost(name: appName)..start(job);
}

void main() {
  late LogCapture logs;

  setUp(() => logs = LogCapture());
  tearDown(() => logs.dispose());

  test('приложение открыто в процессе: задача передана ему, своей копии '
      'движка фон не запускает, замок задачи отпущен до работы', () async {
    final rig = _Rig();
    final host = rig.host((task, reason) async {
      rig.appRuns.add('$task: $reason');
      rig.holderDuringApp.add(await rig.jobLock.holder());
      return _result(task, BackgroundJobOutcome.success);
    });

    final outcome = await rig.runner().run(
      pendingSyncTask,
      'app went to background with 1 unsent change(s)',
    );

    expect(outcome.handledBy, 'open app');
    expect(outcome.succeeded, isTrue);
    expect(rig.appRuns, [
      'sync-pending: app went to background with 1 unsent change(s)',
    ]);
    expect(rig.holderDuringApp, [null]);
    expect(rig.standaloneRuns, isEmpty);
    expect(await rig.jobLock.holder(), isNull);
    expect(
      logs.linesOf('bg', Level.INFO),
      containsAllInOrder([
        endsWith(
          'background task sync-pending handed over to the open app '
          'reason=app went to background with 1 unsent change(s) → running '
          'it here',
        ),
        contains(
          'background task sync-pending done by the open app result=success '
          'sync=done sent=1 applied=1 entities=0',
        ),
      ]),
    );
    host.stop('test over');
  });

  test(
    'приложения нет: задача идёт в фоновом изоляте под замком задачи',
    () async {
      final rig = _Rig();

      final outcome = await rig.runner().run(
        periodicSyncTask,
        'periodic every 30min',
      );

      expect(outcome.handledBy, 'background isolate');
      expect(rig.standaloneRuns, ['sync-periodic: periodic every 30min']);
      expect(rig.holderDuringStandalone, ['background task sync-periodic']);
      expect(await rig.jobLock.holder(), isNull);
      expect(
        logs.linesOf('bg', Level.INFO),
        contains(
          endsWith(
            'background task sync-periodic runs in the background isolate: app '
            'is not running in this process; the app waits for it through the '
            'job lock if it opens meanwhile',
          ),
        ),
      );
    },
  );

  test('регистрация приложения осталась от умершего изолята: фон не ждёт '
      'вечно, снимает её и работает сам', () async {
    final rig = _Rig();
    final dead = ReceivePort();
    IsolateNameServer.registerPortWithName(dead.sendPort, rig.appName);
    dead.close();

    final outcome = await rig
        .runner(ack: const Duration(milliseconds: 50))
        .run(pendingSyncTask, 'app went to background with 2 unsent change(s)');

    expect(outcome.handledBy, 'background isolate');
    expect(rig.standaloneRuns, hasLength(1));
    expect(IsolateNameServer.lookupPortByName(rig.appName), isNull);
    expect(
      logs.linesOf('bg', Level.INFO),
      contains(
        contains(
          'runs in the background isolate: app isolate registration is '
          'stale: no answer in 50ms, registration removed',
        ),
      ),
    );
  });

  test(
    'задача упала в приложении: error в логе, разовая задача - retry',
    () async {
      final rig = _Rig();
      final host = rig.host(
        (task, reason) async => throw StateError('engine gone'),
      );

      final outcome = await rig.runner().run(
        pendingSyncTask,
        'app went to background with 1 unsent change(s)',
      );

      expect(outcome.outcome, BackgroundJobOutcome.retry);
      expect(rig.standaloneRuns, isEmpty);
      expect(
        logs.linesOf('bg', Level.SEVERE),
        contains(
          contains(
            'background task sync-pending crashed in the open app: '
            'StateError: Bad state: engine gone',
          ),
        ),
      );
      expect(
        logs.linesOf('bg', Level.WARNING),
        contains(
          contains(
            'background task sync-pending failed in the open app: StateError: '
            'Bad state: engine gone after',
          ),
        ),
      );
      host.stop('test over');
    },
  );
}
