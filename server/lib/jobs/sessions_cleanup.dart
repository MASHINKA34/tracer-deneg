import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../db/database.dart';
import 'daily_jobs.dart';

final _log = Logger('jobs');

const Duration endedSessionRetention = Duration(days: 90);

final class SessionsCleanupResult {
  const SessionsCleanupResult({
    required this.revoked,
    required this.expired,
    required this.usedRefreshTokens,
  });

  final int revoked;
  final int expired;
  final int usedRefreshTokens;

  int get deleted => revoked + expired;

  @override
  String toString() =>
      'deleted=$deleted revoked=$revoked expired=$expired '
      'usedRefreshTokens=$usedRefreshTokens';
}

class SessionsCleanup {
  SessionsCleanup({
    required this.db,
    this.retention = endedSessionRetention,
    this._now = DateTime.now,
  });

  static const jobName = 'sessions-cleanup';

  final Database db;
  final Duration retention;
  final DateTime Function() _now;

  DailyJob get job => DailyJob(jobName, () async => '${await run()}');

  Future<SessionsCleanupResult> run() async {
    final sw = Stopwatch()..start();
    final cutoff = normalizeInstant(_now()).subtract(retention);
    final context =
        'revokedOrExpiredBefore=${encodeInstant(cutoff)} '
        'retention=${retention.inDays}d';
    _log.fine('sessions cleanup started $context');
    final SessionsCleanupResult result;
    try {
      final rows = await db.execute(
        'WITH gone AS (DELETE FROM sessions '
        r'WHERE revoked_at < $1::timestamptz OR expires_at < $1::timestamptz '
        r'RETURNING id, revoked_at < $1::timestamptz AS revoked) '
        'SELECT (count(*) FILTER (WHERE revoked))::int, '
        '(count(*) FILTER (WHERE revoked IS NOT TRUE))::int, '
        '(SELECT count(*) FROM used_refresh_tokens t '
        'WHERE t.session_id IN (SELECT id FROM gone))::int FROM gone',
        parameters: [cutoff],
        what: 'delete sessions ended before cutoff',
        logParams: {
          'revokedOrExpiredBefore': encodeInstant(cutoff),
          'retentionDays': retention.inDays,
        },
      );
      final row = rows.single;
      result = SessionsCleanupResult(
        revoked: row[0]! as int,
        expired: row[1]! as int,
        usedRefreshTokens: row[2]! as int,
      );
    } catch (e) {
      _log.warning(
        'sessions cleanup failed $context in ${sw.elapsedMilliseconds}ms: '
        '${describeError(e)}',
      );
      rethrow;
    }
    _log.info(
      'sessions cleanup $result $context in ${sw.elapsedMilliseconds}ms',
    );
    return result;
  }
}
