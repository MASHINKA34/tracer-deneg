import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../client_errors/client_error_store.dart';
import 'daily_jobs.dart';

final _log = Logger('client-errors');

const Duration clientErrorRetention = Duration(days: 30);

class ClientErrorsCleanup {
  ClientErrorsCleanup({
    required this.store,
    this.retention = clientErrorRetention,
    this._now = DateTime.now,
  });

  static const jobName = 'client-errors-cleanup';

  final ClientErrorStore store;
  final Duration retention;
  final DateTime Function() _now;

  DailyJob get job => DailyJob(jobName, () async => 'deleted=${await run()}');

  Future<int> run() async {
    final sw = Stopwatch()..start();
    final cutoff = normalizeInstant(_now()).subtract(retention);
    final int deleted;
    try {
      deleted = await store.deleteReceivedBefore(cutoff);
    } catch (e) {
      _log.warning(
        'client errors cleanup failed '
        'receivedBefore=${encodeInstant(cutoff)} '
        'retention=${retention.inDays}d in ${sw.elapsedMilliseconds}ms: '
        '${describeError(e)}',
      );
      rethrow;
    }
    _log.info(
      'client errors cleanup deleted=$deleted '
      'receivedBefore=${encodeInstant(cutoff)} '
      'retention=${retention.inDays}d in ${sw.elapsedMilliseconds}ms',
    );
    return deleted;
  }
}
