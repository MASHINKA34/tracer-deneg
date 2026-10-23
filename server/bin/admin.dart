import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:logging/logging.dart';
import 'package:server/admin/admin_cli.dart';
import 'package:server/logging/log_setup.dart';
import 'package:shared/logging.dart';

final _log = Logger('admin');

void main(List<String> args) {
  setupServerLogging(writeLine: stderr.writeln);

  final isolateErrors = RawReceivePort((Object? message) {
    final pair = message is List ? message : const <Object?>[];
    final error = pair.isNotEmpty ? pair[0] : message;
    final stack = pair.length > 1 && pair[1] is String
        ? StackTrace.fromString(pair[1] as String)
        : null;
    _log.severe('uncaught isolate error: $error', error, stack);
  });
  Isolate.current.addErrorListener(isolateErrors.sendPort);

  Future<void> finish(int code) async {
    isolateErrors.close();
    await stdout.flush();
    await stderr.flush();
    exit(code);
  }

  runZonedGuarded(
    () async {
      final code = await runAdmin(
        args,
        environment: Platform.environment,
        envFile: File('.env'),
        out: stdout.writeln,
        setLogLevel: (level) => Logger.root.level = level,
      );
      await finish(code);
    },
    (error, stack) {
      _log.severe(
        'uncaught async error: ${describeError(error)} → exit 1',
        error,
        stack,
      );
      unawaited(finish(adminExitFailure));
    },
  );
}
