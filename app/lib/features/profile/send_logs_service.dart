import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../core/logging/error_reporting.dart';
import '../../core/logging/log_secrets.dart';
import '../../core/logging/log_tail.dart';
import '../../data/api/api_exception.dart';
import '../../data/api/client_errors_api.dart';
import '../../data/session/session_providers.dart';
import '../../data/session/session_state.dart';

final _log = Logger('errors');

sealed class SendLogsOutcome {
  const SendLogsOutcome();
}

final class LogsSent extends SendLogsOutcome {
  const LogsSent({
    required this.id,
    required this.requestId,
    required this.logsBytes,
  });

  final String id;
  final String requestId;
  final int logsBytes;
}

final class SendLogsFailed extends SendLogsOutcome {
  const SendLogsFailed(this.error);

  final Object error;
}

class SendLogsService {
  SendLogsService(this._ref, {this.maxLogsBytes = maxClientErrorLogsBytes});

  final Ref _ref;
  final int maxLogsBytes;

  Future<SendLogsOutcome> send() async {
    final sw = Stopwatch()..start();
    final reporting = _ref.read(errorReportingProvider);
    final device = reporting?.device ?? ReportDevice.unknown;
    final tail = _readTail(reporting);
    final check = maskLeakedSecrets(tail.text);
    if (check.clean) {
      _log.fine('user report logs checked for secrets: none found');
    } else {
      _log.warning(
        'user report logs: secret-like text found (${check.summary}) → '
        'masked in the report only, log file unchanged',
      );
    }
    final logs = check.text.isEmpty ? null : check.text;
    final report = ClientErrorReport(
      appVersion: device.appVersion,
      androidSdk: device.device.sdkInt,
      deviceModel: device.device.model,
      kind: ClientErrorKind.userReport,
      message:
          'user report from profile: ${device.describe()} '
          'logsBytes=${tail.bytes} files=${tail.files}',
      logs: logs,
    );
    final withSession = _ref.read(sessionProvider) is SessionActive;
    _log.info(
      'user report sending logsBytes=${tail.bytes} of ${tail.sourceBytes} '
      'limit=$maxLogsBytes files=${tail.files} '
      'debugSkipped=${tail.debugLinesSkipped} truncated=${tail.truncated} '
      'masked=${check.total} session=${withSession ? 'yes' : 'no'}',
    );
    try {
      final sent = await _ref
          .read(clientErrorsApiProvider)
          .send(report, withSession: withSession);
      _log.info(
        'user report sent id=${sent.id} logsBytes=${tail.bytes} '
        'rid=${sent.requestId} in ${sw.elapsedMilliseconds}ms',
      );
      return LogsSent(
        id: sent.id,
        requestId: sent.requestId,
        logsBytes: tail.bytes,
      );
    } on ApiException catch (e, st) {
      _log.warning(
        'user report not sent kind=${ClientErrorKind.userReport.code} '
        'logsBytes=${tail.bytes} rid=${e.requestId}: ${e.runtimeType} '
        '${e.details} after ${sw.elapsedMilliseconds}ms → error snackbar',
        e,
        st,
      );
      return SendLogsFailed(e);
    } catch (e, st) {
      _log.severe(
        'user report send crashed after ${sw.elapsedMilliseconds}ms '
        'logsBytes=${tail.bytes} → error snackbar: ${describeError(e)}',
        e,
        st,
      );
      return SendLogsFailed(e);
    }
  }

  LogTail _readTail(ErrorReporting? reporting) {
    if (reporting == null) {
      _log.info(
        'user report: log files not available here → sent without logs',
      );
      return LogTail.empty;
    }
    final files = reporting.logFiles();
    final background = reporting.backgroundLogFiles();
    if (files.isEmpty && background.isEmpty) {
      _log.warning(
        'user report: log file was not opened at start (logcat only) → '
        'sent without logs',
      );
      return LogTail.empty;
    }
    _log.fine(
      'user report: app log files=${files.length}, background task log '
      'files=${background.length} → merged by time, newest kept',
    );
    try {
      return readMergedLogTail([files, background], maxBytes: maxLogsBytes);
    } catch (e, st) {
      _log.warning(
        'user report: log tail read failed '
        'files=${[...files, ...background].map((f) => f.path).join(',')}: '
        '${describeError(e)} → sent without logs',
        e,
        st,
      );
      return LogTail.empty;
    }
  }
}

final sendLogsServiceProvider = Provider<SendLogsService>(
  SendLogsService.new,
  name: 'sendLogsService',
);
