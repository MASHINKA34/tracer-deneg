import 'package:logging/logging.dart';

import '../../core/isolate_lock.dart';
import 'app_isolate_link.dart';
import 'background_job.dart';

final _log = Logger('bg');

typedef StandaloneJob = Future<BackgroundJobResult> Function(
  String task,
  String reason,
);

final class BackgroundTaskOutcome {
  const BackgroundTaskOutcome(this.outcome, {required this.handledBy});

  final BackgroundJobOutcome outcome;
  final String handledBy;

  bool get succeeded => outcome == BackgroundJobOutcome.success;
}

final class BackgroundTaskRunner {
  BackgroundTaskRunner({
    required this._jobLock,
    required this._app,
    required this._standalone,
  });

  final IsolateLock _jobLock;
  final AppIsolateClient _app;
  final StandaloneJob _standalone;

  Future<BackgroundTaskOutcome> run(String task, String reason) async {
    final sw = Stopwatch()..start();
    final lease = await _jobLock.acquire('background task $task');
    try {
      final delegation = await _app.delegate(
        task,
        reason,
        onAccepted: lease.release,
      );
      switch (delegation) {
        case DelegationDone(:final outcome, :final summary):
          _log.info(
            'background task $task done by the open app '
            'result=${outcome.name} $summary in ${sw.elapsedMilliseconds}ms',
          );
          return BackgroundTaskOutcome(outcome, handledBy: 'open app');
        case DelegationFailed(:final why):
          final outcome = task == pendingSyncTask
              ? BackgroundJobOutcome.retry
              : BackgroundJobOutcome.success;
          _log.warning(
            'background task $task failed in the open app: $why after '
            '${sw.elapsedMilliseconds}ms → result=${outcome.name}',
          );
          return BackgroundTaskOutcome(outcome, handledBy: 'open app');
        case DelegationNoApp(:final why):
          _log.info(
            'background task $task runs in the background isolate: $why; '
            'the app waits for it through the job lock if it opens meanwhile',
          );
          final result = await _standalone(task, reason);
          return BackgroundTaskOutcome(
            result.outcome,
            handledBy: 'background isolate',
          );
      }
    } finally {
      lease.release();
    }
  }
}
