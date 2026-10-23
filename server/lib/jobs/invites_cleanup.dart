import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../db/database.dart';
import 'daily_jobs.dart';

final _log = Logger('jobs');

final class InvitesCleanupResult {
  const InvitesCleanupResult({required this.expired, required this.revoked});

  final int expired;
  final int revoked;

  int get deleted => expired + revoked;

  @override
  String toString() => 'deleted=$deleted expired=$expired revoked=$revoked';
}

class InvitesCleanup {
  InvitesCleanup({required this.db, this._now = DateTime.now});

  static const jobName = 'invites-cleanup';

  final Database db;
  final DateTime Function() _now;

  DailyJob get job => DailyJob(jobName, () async => '${await run()}');

  Future<InvitesCleanupResult> run() async {
    final sw = Stopwatch()..start();
    final now = normalizeInstant(_now());
    final context = 'expiresAtOrBefore=${encodeInstant(now)} or revoked';
    _log.fine('invites cleanup started $context');
    final InvitesCleanupResult result;
    try {
      final rows = await db.execute(
        'WITH gone AS (DELETE FROM invites '
        r'WHERE revoked_at IS NOT NULL OR expires_at <= $1::timestamptz '
        'RETURNING revoked_at IS NOT NULL AS revoked) '
        'SELECT (count(*) FILTER (WHERE NOT revoked))::int, '
        '(count(*) FILTER (WHERE revoked))::int FROM gone',
        parameters: [now],
        what: 'delete expired and revoked invites',
        logParams: {'expiresAtOrBefore': encodeInstant(now)},
      );
      final row = rows.single;
      result = InvitesCleanupResult(
        expired: row[0]! as int,
        revoked: row[1]! as int,
      );
    } catch (e) {
      _log.warning(
        'invites cleanup failed $context in ${sw.elapsedMilliseconds}ms: '
        '${describeError(e)}',
      );
      rethrow;
    }
    _log.info(
      'invites cleanup $result $context in ${sw.elapsedMilliseconds}ms',
    );
    return result;
  }
}
