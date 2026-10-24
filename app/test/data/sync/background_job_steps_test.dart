import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/api/api_exception.dart';
import 'package:milionchik/data/recurring_service.dart';
import 'package:milionchik/data/sync/background_job.dart';
import 'package:milionchik/data/sync/pull_service.dart';
import 'package:milionchik/data/sync/push_service.dart';
import 'package:milionchik/data/sync/sync_engine.dart';
import 'package:shared/shared.dart';

import '../api/fake_api_adapter.dart';

final _done = SyncCycleDone(
  reason: SyncReason.background,
  elapsed: const Duration(milliseconds: 40),
  push: const PushOutcome(
    sent: 2,
    applied: 2,
    rejected: [],
    batches: 1,
    remaining: 0,
    elapsed: Duration(milliseconds: 15),
  ),
  pull: PullResult(
    reason: PullReason.background,
    pages: 1,
    counts: const PullCounts(expenses: 3),
    cursorBefore: 10,
    cursorAfter: 13,
    syncedAt: DateTime.utc(2026, 10, 24, 9),
    elapsed: const Duration(milliseconds: 20),
  ),
);

const _offline = SyncCycleFailed(
  reason: SyncReason.background,
  elapsed: Duration(milliseconds: 5),
  stage: SyncStage.push,
  error: ApiNetworkFailure(
    method: 'POST',
    path: '/api/v1/sync/push',
    requestId: 'ridbgjob0000001',
    problem: ApiNetworkProblem.connection,
  ),
  attempt: 1,
  retryIn: Duration(seconds: 2),
);

RecurringRunResult _recurring({int created = 1}) => RecurringRunResult(
  reason: RecurringRunReason.background,
  today: LocalDate(2026, 10, 24),
  rules: 2,
  created: created,
  skippedExisting: 1,
  skippedDeleted: 0,
  failedRules: 0,
  elapsed: const Duration(milliseconds: 3),
);

final class _Fakes {
  final List<String> calls = [];
  final List<(Object, StackTrace)> reports = [];
  Object? syncError;
  Object? recurringError;
  Object? widgetError;
  SyncCycleResult syncResult = _done;

  BackgroundJob job() => BackgroundJob(
    sync: () async {
      calls.add('sync');
      final error = syncError;
      if (error != null) throw error;
      return syncResult;
    },
    recurring: () async {
      calls.add('recurring');
      final error = recurringError;
      if (error != null) throw error;
      return _recurring();
    },
    updateWidget: (reason) async {
      calls.add('widget $reason');
      final error = widgetError;
      if (error != null) throw error;
    },
    report: (error, stack) => reports.add((error, stack)),
  );
}

void main() {
  late LogCapture logs;

  setUp(() => logs = LogCapture());
  tearDown(() => logs.dispose());

  test('задача: синхронизация, затем генератор регулярных, затем хук '
      'виджета; в логе [bg] старт и конец с мс', () async {
    final fakes = _Fakes();

    final result = await fakes.job().run(
      task: periodicSyncTask,
      reason: 'periodic every 30min',
      handledBy: 'background isolate',
    );

    expect(fakes.calls, [
      'sync',
      'recurring',
      'widget background task $periodicSyncTask',
    ]);
    expect(result.outcome, BackgroundJobOutcome.success);
    expect(result.errors, 0);
    expect(result.sync, 'done sent=2 applied=2 entities=3');
    expect(result.recurring, 'created=1');
    expect(fakes.reports, isEmpty);
    final info = logs.linesOf('bg', Level.INFO);
    expect(info, hasLength(2));
    expect(
      info.first,
      endsWith(
        'background job start task=sync-periodic reason=periodic every 30min '
        'in=background isolate',
      ),
    );
    expect(
      info.last,
      matches(
        RegExp(
          r'INFO  \[bg\] background job done task=sync-periodic '
          r'result=success sync=done sent=2 applied=2 entities=3 '
          r'recurring=created=1 widget=ok errors=0 in \d+ms$',
        ),
      ),
    );
  });

  test('синхронизация упала исключением: error со стеком, отчёт в очередь, '
      'генератор и виджет всё равно выполнены, задача не падает', () async {
    final fakes = _Fakes()..syncError = StateError('engine exploded');

    final result = await fakes.job().run(
      task: periodicSyncTask,
      reason: 'periodic every 30min',
      handledBy: 'open app',
    );

    expect(fakes.calls, [
      'sync',
      'recurring',
      'widget background task $periodicSyncTask',
    ]);
    expect(result.outcome, BackgroundJobOutcome.success);
    expect(result.errors, 1);
    expect(result.sync, 'crashed');
    expect(fakes.reports, hasLength(1));
    expect(fakes.reports.single.$1, isA<StateError>());
    final severe = logs.records.where(
      (r) => r.loggerName == 'bg' && r.level == Level.SEVERE,
    );
    expect(severe, hasLength(1));
    expect(
      severe.single.message,
      startsWith('background job task=sync-periodic: sync crashed after'),
    );
    expect(severe.single.message, contains('engine exploded'));
    expect(severe.single.stackTrace, isNotNull);
    expect(
      logs.linesOf('bg', Level.WARNING).last,
      contains(
        'background job done task=sync-periodic result=success sync=crashed '
        'recurring=created=1 widget=ok errors=1 in',
      ),
    );
  });

  test(
    'генератор и виджет упали: оба в логе и в отчётах, итог с errors=2',
    () async {
      final fakes = _Fakes()
        ..recurringError = StateError('rules broken')
        ..widgetError = UnsupportedError('no widget host');

      final result = await fakes.job().run(
        task: periodicSyncTask,
        reason: 'periodic every 30min',
        handledBy: 'background isolate',
      );

      expect(result.errors, 2);
      expect(result.recurring, 'crashed');
      expect(result.widget, 'crashed');
      expect(fakes.reports.map((r) => r.$1.runtimeType), [
        StateError,
        UnsupportedError,
      ]);
      expect(logs.linesOf('bg', Level.SEVERE), [
        contains('recurring generator crashed after'),
        contains('home widget update crashed after'),
      ]);
    },
  );

  test('разовая задача без сети: результат retry (система повторит); '
      'периодическая без сети - success до следующего периода', () async {
    final pending = _Fakes()..syncResult = _offline;
    final periodic = _Fakes()..syncResult = _offline;

    final once = await pending.job().run(
      task: pendingSyncTask,
      reason: 'app went to background with 1 unsent change(s)',
      handledBy: 'background isolate',
    );
    final every = await periodic.job().run(
      task: periodicSyncTask,
      reason: 'periodic every 30min',
      handledBy: 'background isolate',
    );

    expect(once.outcome, BackgroundJobOutcome.retry);
    expect(once.sync, 'failed stage=push attempt=1');
    expect(every.outcome, BackgroundJobOutcome.success);
    expect(pending.calls, contains('recurring'));
    expect(
      logs.linesOf('bg', Level.INFO),
      contains(
        endsWith(
          'background job task=sync-pending: sync failed with a network or '
          'server error → the system retries this task later with its '
          'backoff',
        ),
      ),
    );
  });
}
