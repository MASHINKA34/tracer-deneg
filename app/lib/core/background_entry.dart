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

final class BackgroundIsolate {
  BackgroundIsolate._(this._logging, this._reports);

  factory BackgroundIsolate.start() {
    final logging = AppLogging.start();
    final reports = ErrorReportQueue();
    installErrorHandlers(reports);
    DartPluginRegistrant.ensureInitialized();
    _log.fine('background isolate: logging and error handlers installed');
    return BackgroundIsolate._(logging, reports);
  }

  final AppLogging _logging;
  final ErrorReportQueue _reports;
  Future<ErrorReporting>? _prepared;

  Future<bool> run(String task, Map<String, dynamic>? input) async {
    final sw = Stopwatch()..start();
    final reason = '${input?[backgroundReasonKey] ?? '-'}';
    _log.info('background task start name=$task reason=$reason');
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
    }
  }

  Future<void> stopped(String task, StopReason reason) async {
    _log.warning(
      'background task stopped by the system name=$task reason=${reason.name} '
      '→ unfinished work stays in the queue for the next run',
    );
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
    final sw = Stopwatch()..start();
    try {
      final supportDir = await getApplicationSupportDirectory();
      final logsDir = Directory('${supportDir.path}/logs');
      final file = _logging.attachFile(logsDir);
      _reports.attach(File('${logsDir.path}/pending_reports.jsonl'));
      _log.info(
        'background logging ready file=${file.path} '
        'in ${sw.elapsedMilliseconds}ms',
      );
    } catch (e, st) {
      _log.severe(
        'background log file unavailable, logging to logcat only: '
        '${describeError(e)}',
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
      logFiles: () => [?_logging.previousLogFile, ?_logging.logFile],
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
