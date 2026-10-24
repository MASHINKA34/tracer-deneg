import 'dart:async';

import 'package:drift/drift.dart' show TableUpdate, UpdateKind;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';
import 'package:workmanager/workmanager.dart';

import '../../core/isolate_lock.dart';
import '../db/app_database.dart';
import '../db/redact_db_error.dart';
import '../providers.dart';
import 'app_isolate_link.dart';
import 'background_job.dart';

final _log = Logger('bg');

final class BackgroundTaskRequest {
  const BackgroundTaskRequest({
    required this.uniqueName,
    required this.task,
    required this.reason,
    this.frequency,
    this.requiresNetwork = true,
  });

  final String uniqueName;
  final String task;
  final String reason;
  final Duration? frequency;
  final bool requiresNetwork;

  bool get periodic => frequency != null;

  @override
  String toString() =>
      'BackgroundTaskRequest($uniqueName task=$task '
      '${periodic ? 'every ${frequency!.inMinutes}min' : 'once'} '
      'network=${requiresNetwork ? 'connected' : 'any'})';
}

abstract interface class BackgroundTaskScheduler {
  Future<void> schedule(BackgroundTaskRequest request);

  Future<void> cancel(String uniqueName);
}

final class WorkmanagerTaskScheduler implements BackgroundTaskScheduler {
  const WorkmanagerTaskScheduler();

  @override
  Future<void> schedule(BackgroundTaskRequest request) {
    final constraints = Constraints(
      networkType: request.requiresNetwork
          ? NetworkType.connected
          : NetworkType.notRequired,
    );
    final input = {backgroundReasonKey: request.reason};
    final frequency = request.frequency;
    if (frequency != null) {
      return Workmanager().registerPeriodicTask(
        request.uniqueName,
        request.task,
        frequency: frequency,
        constraints: constraints,
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
        inputData: input,
      );
    }
    return Workmanager().registerOneOffTask(
      request.uniqueName,
      request.task,
      constraints: constraints,
      existingWorkPolicy: ExistingWorkPolicy.keep,
      inputData: input,
    );
  }

  @override
  Future<void> cancel(String uniqueName) =>
      Workmanager().cancelByUniqueName(uniqueName);
}

Future<void> Function(String what) backgroundJobGate(
  IsolateLock lock,
  AppDatabase Function() database,
) => (what) async {
  final lease = await lock.acquire('app sync engine ($what)');
  lease.release();
  final other = lease.waitedFor;
  if (other == null) return;
  final db = database();
  db.notifyUpdates({
    for (final table in db.allTables)
      TableUpdate(table.actualTableName, kind: UpdateKind.update),
  });
  _log.info(
    'sync $what waited ${lease.waited.inMilliseconds}ms for $other → '
    'its database changes announced to the open screens',
  );
};

class BackgroundSync {
  BackgroundSync({
    required this._scheduler,
    required this._queueSize,
    required this._job,
    this._host,
  });

  factory BackgroundSync.forApp(Ref ref) {
    final sync = BackgroundSync(
      scheduler: const WorkmanagerTaskScheduler(),
      queueSize: () => ref.read(outboxQueueProvider).count(),
      job: () => BackgroundJob.from(ref.read),
      host: AppIsolateHost(),
    );
    ref.onDispose(() => sync.stop('app scope disposed'));
    return sync;
  }

  final BackgroundTaskScheduler _scheduler;
  final Future<int> Function() _queueSize;
  final BackgroundJob Function() _job;
  final AppIsolateHost? _host;

  Future<void> _tail = Future<void>.value();
  bool _started = false;
  bool _signedIn = false;
  bool _foreground = true;

  bool get started => _started;

  Future<void> get idle => _tail;

  void start({required bool signedIn, required bool foreground}) {
    if (_started) return;
    _started = true;
    _signedIn = signedIn;
    _foreground = foreground;
    _host?.start(_runHandedOver);
    _log.info(
      'background sync on: periodic task every '
      '${backgroundSyncFrequency.inMinutes}min with network, one-off task '
      'with network when the app goes to background with unsent changes; '
      'session=${signedIn ? 'active' : 'none'} foreground=$foreground',
    );
    if (signedIn) {
      _schedulePeriodic('app started with a session');
    } else {
      _cancelAll('app started without a session');
    }
  }

  void stop(String why) {
    if (!_started) return;
    _started = false;
    _host?.stop(why);
    _log.fine(
      'background sync off: $why → scheduled tasks stay with the system',
    );
  }

  void sessionChanged({required bool active, required String change}) {
    if (!_started) return;
    final was = _signedIn;
    _signedIn = active;
    if (was == active) {
      _log.fine('background sync: session $change, still active=$active');
      return;
    }
    if (active) {
      _schedulePeriodic('signed in (session $change)');
    } else {
      _cancelAll(
        'session $change: signed out, account deleted or session ended',
      );
    }
  }

  void paused() {
    if (!_started) return;
    _foreground = false;
    _scheduleIfPending('app went to background');
  }

  void resumed() {
    if (!_started) return;
    _foreground = true;
  }

  void outboxWritten() {
    if (!_started || _foreground) return;
    _scheduleIfPending('change queued while the app is in background');
  }

  Future<BackgroundJobResult> _runHandedOver(String task, String reason) =>
      _job().run(task: task, reason: reason, handledBy: 'open app');

  void _schedulePeriodic(String why) {
    _enqueue('schedule $periodicSyncTask', () async {
      final request = BackgroundTaskRequest(
        uniqueName: periodicSyncUniqueName,
        task: periodicSyncTask,
        reason: 'periodic every ${backgroundSyncFrequency.inMinutes}min',
        frequency: backgroundSyncFrequency,
      );
      final sw = Stopwatch()..start();
      await _scheduler.schedule(request);
      _log.info(
        'background task scheduled $request ($why) in '
        '${sw.elapsedMilliseconds}ms',
      );
    });
  }

  void _scheduleIfPending(String why) {
    if (!_signedIn) {
      _log.fine('background sync: $why, no active session → no one-off task');
      return;
    }
    _enqueue('schedule $pendingSyncTask', () async {
      final queue = await _queueSize();
      if (queue == 0) {
        _log.fine('background sync: $why, queue empty → no one-off task');
        return;
      }
      final request = BackgroundTaskRequest(
        uniqueName: pendingSyncUniqueName,
        task: pendingSyncTask,
        reason: '$why with $queue unsent change(s)',
      );
      final sw = Stopwatch()..start();
      await _scheduler.schedule(request);
      _log.info(
        'background task scheduled $request: $why with queue=$queue → runs '
        'when network is available, in ${sw.elapsedMilliseconds}ms',
      );
    });
  }

  void _cancelAll(String why) {
    _enqueue('cancel background tasks', () async {
      final sw = Stopwatch()..start();
      await _scheduler.cancel(periodicSyncUniqueName);
      await _scheduler.cancel(pendingSyncUniqueName);
      _log.info(
        'background tasks cancelled $periodicSyncUniqueName, '
        '$pendingSyncUniqueName ($why) in ${sw.elapsedMilliseconds}ms',
      );
    });
  }

  void _enqueue(String what, Future<void> Function() body) {
    _tail = _tail.then((_) async {
      try {
        await body();
      } catch (e, st) {
        final error = redactDbError(e);
        _log.warning(
          'background sync: $what failed: ${describeError(error)} → the app '
          'keeps syncing while open, the next start or session change tries '
          'again',
          error,
          st,
        );
      }
    });
  }
}

final backgroundSyncProvider = Provider<BackgroundSync?>(
  (ref) => null,
  name: 'backgroundSync',
);
