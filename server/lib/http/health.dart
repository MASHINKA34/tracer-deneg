import 'package:logging/logging.dart';
import 'package:shared/logging.dart';
import 'package:shelf/shelf.dart';

import '../db/database.dart';
import '../version.dart';
import 'json.dart';

final _log = Logger('health');

/// `GET /api/v1/health`: 200 `{status: ok, version, db: ok}`, если база
/// отвечает; иначе 503 `{status: degraded, version, db: error}`.
/// Причина недоступности базы — только в логе (наружу не отдаём).
Handler healthHandler(
  Database db, {
  Duration timeout = const Duration(seconds: 3),
}) => (Request request) async {
  final sw = Stopwatch()..start();
  try {
    await db.ping(timeout: timeout);
    _log.fine('database ok in ${sw.elapsedMilliseconds}ms');
    return jsonResponse(200, {
      'status': 'ok',
      'version': serverVersion,
      'db': 'ok',
    });
  } catch (e, st) {
    _log.warning(
      'database check failed in ${sw.elapsedMilliseconds}ms → 503: '
      '${describeError(e)}',
      e,
      st,
    );
    return jsonResponse(503, {
      'status': 'degraded',
      'version': serverVersion,
      'db': 'error',
    });
  }
};
