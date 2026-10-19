import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:logging/logging.dart';
import 'package:server/logging/log_setup.dart';
import 'package:server/server_app.dart';
import 'package:shared/logging.dart';

final _log = Logger('server');

/// Точка входа: `dart run bin/server.dart` из папки `server/`
/// (настройки — переменные окружения и `server/.env`).
void main() {
  setupServerLogging();

  // Ошибки, которые не поймала ни одна зона, — с полным стеком.
  final isolateErrors = RawReceivePort((Object? message) {
    final pair = message is List ? message : const <Object?>[];
    final error = pair.isNotEmpty ? pair[0] : message;
    final stack = pair.length > 1 && pair[1] is String
        ? StackTrace.fromString(pair[1] as String)
        : null;
    _log.severe('uncaught isolate error: $error', error, stack);
  });
  Isolate.current.addErrorListener(isolateErrors.sendPort);

  runZonedGuarded(
    () async {
      final code = await runServerProcess(
        environment: Platform.environment,
        envFile: File('.env'),
        setLogLevel: (level) {
          Logger.root.level = level;
          _log.info('log level ${logLevelName(level)}');
        },
      );
      isolateErrors.close();
      await stdout.flush();
      exit(code);
    },
    (error, stack) {
      _log.severe(
        'uncaught async error: ${describeError(error)}',
        error,
        stack,
      );
    },
  );
}
