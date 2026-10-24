import 'dart:io';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared/logging.dart';
import 'package:shared/shared.dart' show LocalDate;
import 'package:workmanager/workmanager.dart';

import '../data/db/app_database.dart';
import '../data/providers.dart';
import '../data/repositories/prefs_repository.dart';
import '../data/session/secure_values.dart';
import '../data/session/session_providers.dart';
import '../data/session/session_state.dart';
import '../data/session/session_store.dart';
import '../data/sync/app_isolate_link.dart';
import '../data/sync/background_job.dart';
import '../data/sync/background_task_runner.dart';
import 'clock.dart';
import 'isolate_lock.dart';
import 'logging/app_logging.dart';
import 'logging/device_info.dart';
import 'logging/error_handlers.dart';
import 'logging/error_reporting.dart';
import 'logging/error_reports.dart';
import 'logging/provider_logger.dart';

final _log = Logger('bg');

@pragma('vm:entry-point')
void backgroundDispatcher() {
  final isolate = BackgroundIsolate.start();
  Workmanager().executeTask(isolate.run, onTaskStopped: isolate.stopped);
}

Future<Directory> _logsDirectory() async =>
    Directory('${(await getApplicationSupportDirectory()).path}/logs');

final class BackgroundLog {
  BackgroundLog._(this._isolate, this._lease, this.file);

  final BackgroundIsolate _isolate;
  final IsolateLease? _lease;
  final File? file;
  bool _closed = false;

  void close(String why) {
    if (_closed) return;
    _closed = true;
    if (file != null) {
      _log.fine(
        'background log file ${file!.path} closed ($why) → the next '
        'background task writes it',
      );
      _isolate._logging.detachFile();
    }
    _lease?.release();
  }
}

final class BackgroundIsolate {
  BackgroundIsolate._(
    this._logging,
    this._reports,
    this._logsDir,
    this._logLock,
  );

  factory BackgroundIsolate.start({
    Future<Directory> Function() logsDir = _logsDirectory,
    IsolateLock? logLock,
  }) {
    final logging = AppLogging.start();
    final reports = ErrorReportQueue();
    installErrorHandlers(reports);
    DartPluginRegistrant.ensureInitialized();
    _log.fine('background isolate: logging and error handlers installed');
    return BackgroundIsolate._(
      logging,
      reports,
      logsDir,
      logLock ?? IsolateLock(backgroundLogLockName),
    );
  }

  final AppLogging _logging;
  final ErrorReportQueue _reports;
  final Future<Directory> Function() _logsDir;
  final IsolateLock _logLock;
  Future<ErrorReporting>? _prepared;

  Future<bool> run(String task, Map<String, dynamic>? input) async {
    final sw = Stopwatch()..start();
    final reason = '${input?[backgroundReasonKey] ?? '-'}';
    _log.info('background task start name=$task reason=$reason');
    final log = await openLog('background task $task');
    try {
      final reporting = await (_prepared ??= _prepare());
      if (task != periodicSyncTask && task != pendingSyncTask) {
        _log.warning(
          'background task end name=$task result=unknown → not a task of '
          'this app version, nothing done in ${sw.elapsedMilliseconds}ms',
        );
        return true;
      }
      final outcome = await BackgroundTaskRunner(
        jobLock: IsolateLock(backgroundJobLockName),
        app: AppIsolateClient(),
        standalone: (task, reason) => _standalone(task, reason, reporting),
      ).run(task, reason);
      _log.info(
        'background task end name=$task result=${outcome.outcome.name} '
        'handledBy=${outcome.handledBy} in ${sw.elapsedMilliseconds}ms',
      );
      return outcome.succeeded;
    } catch (e, st) {
      final safe = reportSafeError(e, st);
      _log.severe(
        'background task end name=$task result=crashed after '
        '${sw.elapsedMilliseconds}ms → error report queued: '
        '${describeError(safe.error)}${safe.origin}',
        safe.error,
        safe.stack,
      );
      _reports.add('crash', e, st);
      return true;
    } finally {
      log.close('task $task finished');
    }
  }

  Future<void> stopped(String task, StopReason reason) async {
    _log.warning(
      'background task stopped by the system name=$task reason=${reason.name} '
      '→ unfinished work stays in the queue for the next run',
    );
  }

  Future<BackgroundLog> openLog(String owner) async {
    final sw = Stopwatch()..start();
    final IsolateLease lease;
    try {
      lease = await _logLock.acquire(owner);
    } catch (e, st) {
      _log.warning(
        'background log lock not taken by $owner: ${describeError(e)} → '
        'logging to logcat only',
        e,
        st,
      );
      return BackgroundLog._(this, null, null);
    }
    final waited = lease.waitedFor == null
        ? ''
        : ' after waiting ${lease.waited.inMilliseconds}ms for '
              '${lease.waitedFor}';
    try {
      final dir = await _logsDir();
      final file = _logging.attachFile(dir, fileName: backgroundLogFileName);
      _log.info(
        'background log file ready file=${file.path} '
        '(app log stays app.log, one writer per file)$waited '
        'in ${sw.elapsedMilliseconds}ms',
      );
      return BackgroundLog._(this, lease, file);
    } catch (e, st) {
      _log.severe(
        'background log file unavailable, logging to logcat only: '
        '${describeError(e)}',
        e,
        st,
      );
      return BackgroundLog._(this, lease, null);
    }
  }

  Future<ErrorReporting> _prepare() async {
    final device = DeviceInfo.read();
    var version = '?';
    try {
      final info = await PackageInfo.fromPlatform();
      version = '${info.version}+${info.buildNumber}';
    } catch (e, st) {
      _log.warning('package info unavailable: ${describeError(e)}', e, st);
    }
    final buildMode = kReleaseMode
        ? 'release'
        : kProfileMode
        ? 'profile'
        : 'debug';
    _log.info(
      'background isolate start version=$version sdk=${device.sdkInt} '
      'model=${device.model} log=${_logging.levelName} build=$buildMode',
    );
    _reports.context = {
      'appVersion': version,
      'androidSdk': device.sdkInt,
      'deviceModel': device.model,
    };
    try {
      final dir = await _logsDir();
      _reports.attach(File('${dir.path}/pending_reports.jsonl'));
    } catch (e, st) {
      _log.severe(
        'background error report queue file unavailable, reports stay in '
        'memory of this task: ${describeError(e)}',
        e,
        st,
      );
    }
    return ErrorReporting(
      queue: _reports,
      device: ReportDevice(
        appVersion: version,
        device: device,
        buildMode: buildMode,
        logLevel: _logging.levelName,
      ),
      logFiles: () => const [],
      backgroundLogFiles: () => [?_logging.previousLogFile, ?_logging.logFile],
    );
  }

  Future<BackgroundJobResult> _standalone(
    String task,
    String reason,
    ErrorReporting reporting,
  ) async {
    final db = await openAppDatabase();
    try {
      final session = await SessionStore(const FlutterSecureValues()).read();
      LocalDate? todayOverride;
      if (kDebugMode) {
        todayOverride = await loadTodayOverride(DriftPrefsRepository(db));
      }
      if (session == null) {
        _log.info(
          'background task $task: no session on the phone → sync skipped, '
          'recurring generator still runs',
        );
      }
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          isolateCoordinationProvider.overrideWithValue(
            IsolateCoordination.background(),
          ),
          errorReportingProvider.overrideWithValue(reporting),
          if (session != null)
            sessionProvider.overrideWithBuild(
              (ref, _) => SessionActive(session.user),
            ),
          if (kDebugMode && todayOverride != null)
            todayOverrideProvider.overrideWithBuild((ref, _) => todayOverride),
        ],
        observers: const [ProviderLogger()],
      );
      try {
        return await BackgroundJob.from(container.read)
            .run(task: task, reason: reason, handledBy: 'background isolate');
      } finally {
        container.dispose();
      }
    } finally {
      await _close(db);
    }
  }

  Future<void> _close(AppDatabase db) async {
    final sw = Stopwatch()..start();
    try {
      await db.close();
      _log.fine('background database closed in ${sw.elapsedMilliseconds}ms');
    } catch (e, st) {
      _log.warning(
        'background database close failed after ${sw.elapsedMilliseconds}ms: '
        '${describeError(e)}',
        e,
        st,
      );
    }
  }
}
