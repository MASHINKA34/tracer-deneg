import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared/logging.dart';

import 'app.dart';
import 'core/logging/app_logging.dart';
import 'core/logging/crash_test.dart';
import 'core/logging/device_info.dart';
import 'core/logging/error_handlers.dart';
import 'core/logging/error_reports.dart';
import 'core/orientation_policy.dart';

final _log = Logger('app');

/// Запуск по шагам; каждый шаг — в лог с длительностью. Сбой
/// необязательного шага (файл лога, версия) не мешает запуску.
Future<void> main() async {
  final startup = Stopwatch()..start();

  // 1. Логи в logcat и перехват ошибок — до всего остального.
  final logging = AppLogging.start();
  final reports = ErrorReportQueue();
  installErrorHandlers(reports);
  final binding = WidgetsFlutterBinding.ensureInitialized();

  // 2. Версия и устройство.
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
    'start version=$version sdk=${device.sdkInt} model=${device.model} '
    'log=${logging.levelName} build=$buildMode '
    'android=${device.release} manufacturer=${device.manufacturer}',
  );
  reports.context = {
    'appVersion': version,
    'androidSdk': device.sdkInt,
    'deviceModel': device.model,
  };

  // 3. Файл лога и очередь отчётов в каталоге приложения.
  var sw = Stopwatch()..start();
  try {
    final supportDir = await getApplicationSupportDirectory();
    final logsDir = Directory('${supportDir.path}/logs');
    final file = logging.attachFile(logsDir);
    reports.attach(File('${logsDir.path}/pending_reports.jsonl'));
    _log.info('logging ready file=${file.path} in ${sw.elapsedMilliseconds}ms');
  } catch (e, st) {
    _log.severe(
      'log file unavailable, logging to logcat only: ${describeError(e)}',
      e,
      st,
    );
  }

  // 4. Системные панели и ориентация.
  sw = Stopwatch()..start();
  try {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _log.fine('edge-to-edge enabled in ${sw.elapsedMilliseconds}ms');
  } catch (e, st) {
    _log.warning('edge-to-edge mode failed: ${describeError(e)}', e, st);
  }
  OrientationPolicy().start();

  // 5. Первый кадр.
  binding.addPostFrameCallback((_) {
    _log.info('first frame in ${startup.elapsedMilliseconds}ms');
  });
  _log.fine('runApp after ${startup.elapsedMilliseconds}ms');
  runApp(const MilionchikApp());

  scheduleCrashTestIfRequested();
}
