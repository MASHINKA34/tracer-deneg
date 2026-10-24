import 'dart:async';
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../core/isolate_lock.dart';
import 'background_job.dart';

final _log = Logger('bg');

const String appIsolatePortName = 'ru.milionchik.app';

const Duration delegatedJobTimeout = Duration(minutes: 9);

const String _jobMessage = 'job';
const String _acceptedMessage = 'accepted';
const String _doneMessage = 'done';
const String _failedMessage = 'failed';

typedef DelegatedJob = Future<BackgroundJobResult> Function(
  String task,
  String reason,
);

final class AppIsolateHost {
  AppIsolateHost({this.name = appIsolatePortName});

  final String name;
  ReceivePort? _port;
  int _jobs = 0;

  bool get registered => _port != null;

  void start(DelegatedJob onJob) {
    if (_port != null) return;
    final port = ReceivePort('app isolate');
    var replaced = false;
    if (!IsolateNameServer.registerPortWithName(port.sendPort, name)) {
      IsolateNameServer.removePortNameMapping(name);
      replaced = true;
      if (!IsolateNameServer.registerPortWithName(port.sendPort, name)) {
        port.close();
        _log.warning(
          'app isolate not registered as $name (taken again right after '
          'removal) → background tasks run on their own and wait for the '
          'app through the job lock',
        );
        return;
      }
    }
    _port = port;
    port.listen((message) => _onMessage(message, onJob));
    _log.info(
      'app isolate registered as $name${replaced ? ' (replaced an earlier '
                'registration of a gone app isolate)' : ''} → background '
      'tasks hand their work to this app while it runs',
    );
  }

  void stop(String why) {
    final port = _port;
    if (port == null) return;
    _port = null;
    if (IsolateNameServer.lookupPortByName(name) == port.sendPort) {
      IsolateNameServer.removePortNameMapping(name);
    }
    port.close();
    _log.info(
      'app isolate unregistered ($why) after $_jobs background job(s) → '
      'background tasks run on their own',
    );
  }

  void _onMessage(Object? message, DelegatedJob onJob) {
    if (message is! List<Object?> ||
        message.length < 4 ||
        message[0] != _jobMessage) {
      _log.warning('app isolate got an unknown message → ignored');
      return;
    }
    final task = '${message[1]}';
    final reason = '${message[2]}';
    final reply = message[3];
    if (reply is! SendPort) {
      _log.warning('app isolate got job task=$task without reply port');
      return;
    }
    _jobs++;
    reply.send(const [_acceptedMessage]);
    _log.info(
      'background task $task handed over to the open app reason=$reason '
      '→ running it here',
    );
    unawaited(_run(task, reason, reply, onJob));
  }

  Future<void> _run(
    String task,
    String reason,
    SendPort reply,
    DelegatedJob onJob,
  ) async {
    try {
      final result = await onJob(task, reason);
      reply.send([_doneMessage, result.outcome.name, result.summary]);
    } catch (e, st) {
      _log.severe(
        'background task $task crashed in the open app: ${describeError(e)}',
        e,
        st,
      );
      reply.send([_failedMessage, describeError(e)]);
    }
  }
}

sealed class Delegation {
  const Delegation();
}

final class DelegationNoApp extends Delegation {
  const DelegationNoApp(this.why);

  final String why;
}

final class DelegationDone extends Delegation {
  const DelegationDone(this.outcome, this.summary);

  final BackgroundJobOutcome outcome;
  final String summary;
}

final class DelegationFailed extends Delegation {
  const DelegationFailed(this.why);

  final String why;
}

final class AppIsolateClient {
  AppIsolateClient({
    this.name = appIsolatePortName,
    this.ackTimeout = isolateAckTimeout,
    this.jobTimeout = delegatedJobTimeout,
  });

  final String name;
  final Duration ackTimeout;
  final Duration jobTimeout;

  Future<Delegation> delegate(
    String task,
    String reason, {
    void Function()? onAccepted,
  }) async {
    final app = IsolateNameServer.lookupPortByName(name);
    if (app == null) {
      return const DelegationNoApp('app is not running in this process');
    }
    final reply = ReceivePort('background task $task');
    final messages = StreamIterator<Object?>(reply);
    try {
      app.send([_jobMessage, task, reason, reply.sendPort]);
      final accepted = await messages.moveNext().timeout(
        ackTimeout,
        onTimeout: () => false,
      );
      if (!accepted) {
        if (IsolateNameServer.lookupPortByName(name) == app) {
          IsolateNameServer.removePortNameMapping(name);
        }
        return DelegationNoApp(
          'app isolate registration is stale: no answer in '
          '${ackTimeout.inMilliseconds}ms, registration removed',
        );
      }
      onAccepted?.call();
      final finished = await messages.moveNext().timeout(
        jobTimeout,
        onTimeout: () => false,
      );
      if (!finished) {
        return DelegationFailed(
          'the app accepted the job but did not finish it in '
          '${jobTimeout.inMinutes} min',
        );
      }
      final answer = messages.current;
      if (answer is List<Object?> &&
          answer.length >= 3 &&
          answer[0] == _doneMessage) {
        final outcome = BackgroundJobOutcome.values.firstWhere(
          (o) => o.name == answer[1],
          orElse: () => BackgroundJobOutcome.success,
        );
        return DelegationDone(outcome, '${answer[2]}');
      }
      if (answer is List<Object?> &&
          answer.length >= 2 &&
          answer[0] == _failedMessage) {
        return DelegationFailed('${answer[1]}');
      }
      return const DelegationFailed('unknown answer from the app');
    } finally {
      await messages.cancel();
      reply.close();
    }
  }
}
