import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../core/logging/error_reporting.dart';
import '../db/redact_db_error.dart';
import '../recurring_service.dart';
import 'sync_engine.dart';

final _log = Logger('bg');

const String periodicSyncTask = 'sync-periodic';

const String pendingSyncTask = 'sync-pending';

const String periodicSyncUniqueName = 'ru.milionchik.sync.periodic';

const String pendingSyncUniqueName = 'ru.milionchik.sync.pending';

const Duration backgroundSyncFrequency = Duration(minutes: 30);

const String backgroundReasonKey = 'reason';

typedef BackgroundSyncRun = Future<SyncCycleResult> Function();

typedef BackgroundRecurringRun = Future<RecurringRunResult> Function();

typedef HomeWidgetUpdate = Future<void> Function(String reason);

typedef BackgroundErrorReport = void Function(Object error, StackTrace stack);

enum BackgroundJobOutcome { success, retry }

final class BackgroundJobResult {
  const BackgroundJobResult({
    required this.task,
    required this.outcome,
    required this.sync,
    required this.recurring,
    required this.widget,
    required this.errors,
    required this.elapsed,
  });

  final String task;
  final BackgroundJobOutcome outcome;
  final String sync;
  final String recurring;
  final String widget;
  final int errors;
  final Duration elapsed;

  String get summary =>
      'sync=$sync recurring=$recurring widget=$widget errors=$errors';

  @override
  String toString() =>
      'BackgroundJobResult($task ${outcome.name} $summary '
      'in ${elapsed.inMilliseconds}ms)';
}

Future<void> noHomeWidgetUpdate(String reason) async {
  _log.fine(
    'home widget update after $reason: the app has no home widget yet → '
    'nothing to update',
  );
}

final homeWidgetUpdateProvider = Provider<HomeWidgetUpdate>(
  (ref) => noHomeWidgetUpdate,
  name: 'homeWidgetUpdate',
);

final class BackgroundJob {
  BackgroundJob({
    required this._sync,
    required this._recurring,
    required this._updateWidget,
    required this._report,
  });

  factory BackgroundJob.from(
    T Function<T>(ProviderListenable<T> provider) read,
  ) => BackgroundJob(
    sync: () => read(syncEngineProvider).sync(SyncReason.background),
    recurring: () => read(recurringServiceProvider).forBackground(),
    updateWidget: read(homeWidgetUpdateProvider),
    report: (error, stack) =>
        read(errorReportingProvider)?.queue.add('error', error, stack),
  );

  final BackgroundSyncRun _sync;
  final BackgroundRecurringRun _recurring;
  final HomeWidgetUpdate _updateWidget;
  final BackgroundErrorReport _report;

  Future<BackgroundJobResult> run({
    required String task,
    required String reason,
    required String handledBy,
  }) async {
    final sw = Stopwatch()..start();
    _log.info('background job start task=$task reason=$reason in=$handledBy');
    var errors = 0;
    var outcome = BackgroundJobOutcome.success;

    String sync;
    try {
      final result = await _sync();
      sync = _describeSync(result);
      if (task == pendingSyncTask &&
          result is SyncCycleFailed &&
          result.retryIn != null) {
        outcome = BackgroundJobOutcome.retry;
        _log.info(
          'background job task=$task: sync failed with a network or server '
          'error → the system retries this task later with its backoff',
        );
      }
    } catch (e, st) {
      errors++;
      sync = 'crashed';
      _crashed('sync', task, e, st, sw);
    }

    String recurring;
    try {
      final result = await _recurring();
      recurring = result.ok
          ? 'created=${result.created}'
          : 'failed (error in [recurring] above)';
    } catch (e, st) {
      errors++;
      recurring = 'crashed';
      _crashed('recurring generator', task, e, st, sw);
    }

    String widget;
    try {
      await _updateWidget('background task $task');
      widget = 'ok';
    } catch (e, st) {
      errors++;
      widget = 'crashed';
      _crashed('home widget update', task, e, st, sw);
    }

    final result = BackgroundJobResult(
      task: task,
      outcome: outcome,
      sync: sync,
      recurring: recurring,
      widget: widget,
      errors: errors,
      elapsed: sw.elapsed,
    );
    _log.log(
      errors == 0 ? Level.INFO : Level.WARNING,
      'background job done task=$task result=${outcome.name} '
      '${result.summary} in ${sw.elapsedMilliseconds}ms',
    );
    return result;
  }

  void _crashed(
    String step,
    String task,
    Object error,
    StackTrace stack,
    Stopwatch sw,
  ) {
    final safe = redactDbError(error);
    _log.severe(
      'background job task=$task: $step crashed after '
      '${sw.elapsedMilliseconds}ms → error report queued, the next steps '
      'still run: ${describeError(safe)}',
      safe,
      stack,
    );
    try {
      _report(error, stack);
    } catch (e, st) {
      _log.warning(
        'background job task=$task: error report for $step not queued: '
        '${describeError(e)}',
        e,
        st,
      );
    }
  }
}

String _describeSync(SyncCycleResult result) => switch (result) {
  SyncCycleDone(:final push, :final pull) =>
    'done sent=${push.sent} applied=${push.applied} '
        'entities=${pull.counts.total}',
  SyncCycleFailed(:final stage, :final attempt) =>
    'failed stage=${stage.name} attempt=$attempt',
  SyncCycleSkipped(:final why) => 'skipped ($why)',
};
