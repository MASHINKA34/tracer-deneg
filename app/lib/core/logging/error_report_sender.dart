import 'dart:async';
import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../data/api/api_exception.dart';
import '../../data/api/client_errors_api.dart';
import 'error_reports.dart';

final _log = Logger('errors');

final class ErrorReportsSendResult {
  const ErrorReportsSendResult({
    required this.queued,
    required this.sent,
    required this.dropped,
    required this.left,
    required this.elapsed,
    this.failure,
  });

  final int queued;
  final int sent;
  final int dropped;
  final int left;
  final Duration elapsed;
  final Object? failure;
}

ClientErrorReport queuedReportFrom(String raw, {required String appVersion}) {
  final Object? json;
  try {
    json = jsonDecode(raw);
  } on FormatException catch (e) {
    throw FormatException('not JSON: ${e.message}');
  }
  if (json is! Map<String, Object?>) {
    throw FormatException('expected JSON object, got ${json.runtimeType}');
  }
  final version = json['appVersion'];
  return ClientErrorReport.fromJson({
    ...json,
    if (version is! String || version.isEmpty) 'appVersion': appVersion,
  });
}

bool isPermanentRejection(ApiException error) =>
    error is ApiErrorResponse &&
    switch (error.code) {
      ApiErrorCode.badRequest ||
      ApiErrorCode.validationFailed ||
      ApiErrorCode.payloadTooLarge => true,
      _ => false,
    };

class ErrorReportSender {
  ErrorReportSender({
    required this._queue,
    required this._api,
    required this._withSession,
    required this._appVersion,
  });

  final ErrorReportQueue _queue;
  final ClientErrorsApi _api;
  final bool Function() _withSession;
  final String _appVersion;

  Future<ErrorReportsSendResult>? _running;
  String? _runningReason;

  bool get sending => _running != null;

  Future<ErrorReportsSendResult> send(String reason) {
    final running = _running;
    if (running != null) {
      _log.fine(
        'error reports send reason=$reason joins the running one '
        'reason=$_runningReason',
      );
      return running;
    }
    _runningReason = reason;
    final future = _send(reason);
    _running = future;
    unawaited(
      future.whenComplete(() {
        if (!identical(_running, future)) return;
        _running = null;
        _runningReason = null;
      }),
    );
    return future;
  }

  Future<ErrorReportsSendResult> _send(String reason) async {
    final sw = Stopwatch()..start();
    final queued = _queue.readQueued();
    if (queued.isEmpty) {
      _log.fine('error reports: queue empty, nothing to send reason=$reason');
      return ErrorReportsSendResult(
        queued: 0,
        sent: 0,
        dropped: 0,
        left: 0,
        elapsed: sw.elapsed,
      );
    }
    final withSession = _withSession();
    _log.info(
      'error reports sending count=${queued.length} reason=$reason '
      'session=${withSession ? 'yes' : 'no'}',
    );
    var sent = 0;
    var dropped = 0;
    Object? failure;
    for (var i = 0; i < queued.length; i++) {
      final entry = queued[i];
      final ClientErrorReport report;
      try {
        report = queuedReportFrom(entry.raw, appVersion: _appVersion);
      } on FormatException catch (e) {
        _log.warning(
          'queued error report line ${entry.line} is malformed: ${e.message} '
          '→ dropped, it can never be sent',
        );
        if (!_queue.remove(entry)) {
          failure = StateError('queue line ${entry.line} not removed');
          break;
        }
        dropped++;
        continue;
      }
      final item = Stopwatch()..start();
      try {
        final result = await _api.send(report, withSession: withSession);
        if (!_queue.remove(entry)) {
          failure = StateError('queue line ${entry.line} not removed');
          break;
        }
        sent++;
        _log.fine(
          'error report sent kind=${report.kind.code} id=${result.id} '
          'rid=${result.requestId} in ${item.elapsedMilliseconds}ms '
          '(${i + 1}/${queued.length})',
        );
      } on ApiException catch (e, st) {
        if (isPermanentRejection(e)) {
          _log.warning(
            'error report rejected kind=${report.kind.code} '
            'rid=${e.requestId}: ${e.runtimeType} ${e.details} → dropped, '
            'the server will not accept it',
            e,
            st,
          );
          if (!_queue.remove(entry)) {
            failure = e;
            break;
          }
          dropped++;
          continue;
        }
        failure = e;
        _log.warning(
          'error report not sent kind=${report.kind.code} '
          'rid=${e.requestId}: ${e.runtimeType} ${e.details} after '
          '${item.elapsedMilliseconds}ms → kept, retry on next start or '
          'when network appears',
          e,
          st,
        );
        break;
      } catch (e, st) {
        failure = e;
        _log.severe(
          'error report send crashed kind=${report.kind.code} after '
          '${item.elapsedMilliseconds}ms → kept: ${describeError(e)}',
          e,
          st,
        );
        break;
      }
    }
    final left = _queue.readQueued().length;
    final summary =
        'sent=$sent dropped=$dropped left=$left of ${queued.length} '
        'reason=$reason in ${sw.elapsedMilliseconds}ms';
    if (failure == null) {
      _log.info('error reports done $summary');
    } else {
      _log.info(
        'error reports stopped $summary: ${failure.runtimeType}, see warning '
        'above',
      );
    }
    return ErrorReportsSendResult(
      queued: queued.length,
      sent: sent,
      dropped: dropped,
      left: left,
      elapsed: sw.elapsed,
      failure: failure,
    );
  }
}
