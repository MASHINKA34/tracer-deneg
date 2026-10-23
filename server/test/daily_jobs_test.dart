import 'dart:async';

import 'package:server/jobs/daily_jobs.dart';
import 'package:test/test.dart';

import 'support/test_support.dart';

void main() {
  late LogCapture logs;

  setUp(() => logs = LogCapture());

  test('start: первый запуск сразу, дальше по интервалу; в логе номер '
      'запуска, задачи и результат', () async {
    var runs = 0;
    final jobs = DailyJobs([
      DailyJob('count', () async => 'runs=${++runs}'),
    ], interval: const Duration(milliseconds: 150));
    addTearDown(() => jobs.stop('test'));

    jobs.start();
    await waitUntil(() => runs >= 3);
    await jobs.stop('test');
    final stoppedAt = runs;
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(runs, stoppedAt, reason: 'no runs after stop');
    expect(
      logs.text,
      contains(
        'INFO  [jobs] daily jobs scheduled jobs=count interval=150ms '
        'firstRun=now',
      ),
    );
    expect(logs.text, contains('daily jobs run #1 started reason=startup'));
    expect(logs.text, contains('daily jobs run #2 started reason=timer'));
    expect(logs.text, contains('job count done runs=1 in'));
    expect(logs.text, contains('job count done runs=3 in'));
    expect(
      logs.text,
      contains(RegExp(r'daily jobs run #3 finished ok=1 failed=0 in \d+ms')),
    );
    expect(logs.text, contains('stopping daily jobs (test)'));
  });

  test('упавшая задача не мешает следующей: error со стеком, итог warn '
      'с именем упавшей', () async {
    final order = <String>[];
    final jobs = DailyJobs([
      DailyJob('broken', () async {
        order.add('broken');
        throw StateError('cleanup exploded');
      }),
      DailyJob('healthy', () async {
        order.add('healthy');
        return 'deleted=4';
      }),
    ]);

    final run = await jobs.runNow('test');

    expect(order, ['broken', 'healthy']);
    expect(run.number, 1);
    expect(run.failed, ['broken']);
    expect(run.ok, ['healthy']);
    expect(logs.text, contains('ERROR [jobs] job broken failed in '));
    expect(
      logs.text,
      contains('Bad state: cleanup exploded → continuing with the next job'),
    );
    expect(logs.text, contains('  stack:'));
    expect(logs.text, contains('INFO  [jobs] job healthy done deleted=4 in'));
    expect(
      logs.text,
      contains(
        RegExp(
          r'WARN  \[jobs\] daily jobs run #1 finished ok=1 failed=1 '
          r'\(broken\) in \d+ms nextRun=none',
        ),
      ),
    );
  });

  test('запуск во время идущего: таймер пропускает с warn, runNow ждёт тот '
      'же запуск; stop дожидается задачи', () async {
    final release = Completer<void>();
    var started = 0;
    var finished = 0;
    final jobs = DailyJobs([
      DailyJob('slow', () async {
        started++;
        await release.future;
        finished++;
        return 'done';
      }),
    ], interval: const Duration(milliseconds: 100));

    jobs.start();
    await waitUntil(
      () => logs.text.contains('daily jobs run skipped reason=timer'),
    );
    expect(jobs.isRunning, isTrue);
    final joined = jobs.runNow('manual');
    expect(
      logs.text,
      contains(
        'daily jobs run requested reason=manual while run is in progress',
      ),
    );

    final stopping = jobs.stop('test');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(finished, 0);
    release.complete();
    await stopping;
    final run = await joined;

    expect(started, 1);
    expect(finished, 1);
    expect(run.number, 1);
    expect(jobs.isRunning, isFalse);
    expect(logs.text, contains('stopping daily jobs (test) running=true'));
    expect(logs.text, contains(RegExp(r'daily jobs stopped in \d+ms')));
  });
}
