import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

/// `--dart-define=CRASH_TEST=1` — тестовая ошибка через 2 секунды после
/// старта, чтобы проверить, что стек виден в logcat и в файле лога.
const String crashTestDefine = String.fromEnvironment('CRASH_TEST');

final _log = Logger('app');

/// Работает только в debug-сборке; в release флаг игнорируется с warn.
void scheduleCrashTestIfRequested({
  String flag = crashTestDefine,
  bool debugBuild = kDebugMode,
  Duration delay = const Duration(seconds: 2),
}) {
  if (flag != '1') return;
  if (!debugBuild) {
    _log.warning('CRASH_TEST=1 ignored: works only in debug builds');
    return;
  }
  _log.warning(
    'CRASH_TEST=1: test exception will be thrown in ${delay.inSeconds}s',
  );
  Timer(delay, _throwTestError);
}

Never _throwTestError() =>
    throw StateError('CRASH_TEST: test exception to check error logging');
