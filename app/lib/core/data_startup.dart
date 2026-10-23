import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared/logging.dart';
import 'package:shared/shared.dart' show LocalDate;

import '../app.dart';
import '../data/current_user.dart';
import '../data/db/app_database.dart';
import '../data/db/redact_db_error.dart';
import '../data/dev_seed.dart';
import '../data/providers.dart';
import '../data/repositories/prefs_repository.dart';
import '../data/session/secure_values.dart';
import '../data/session/session.dart';
import '../data/session/session_providers.dart';
import '../data/session/session_state.dart';
import '../data/session/session_store.dart';
import '../features/startup/database_error_app.dart';
import 'clock.dart';
import 'logging/provider_logger.dart';
import 'recurring_triggers.dart';

final _log = Logger('app');

final _sessionLog = Logger('session');

typedef OpenDatabase = Future<AppDatabase> Function();

typedef RunDevSeed = Future<DevSeedResult> Function(AppDatabase db);

typedef ReadSession = Future<Session?> Function();

sealed class DataStartup {
  const DataStartup();
}

final class DataReady extends DataStartup {
  const DataReady(this.db, this.seed, {this.todayOverride, this.session});

  final AppDatabase db;
  final DevSeedResult seed;
  final LocalDate? todayOverride;
  final Session? session;
}

final class DataUnavailable extends DataStartup {
  const DataUnavailable(this.error);

  final Object error;
}

Future<DevSeedResult> runDevSeed(AppDatabase db) => DevSeed(
  db,
  currentUser: LocalPrefsCurrentUser(DriftPrefsRepository(db)),
).runIfRequested();

Future<Session?> readStoredSession() =>
    SessionStore(const FlutterSecureValues()).read();

Future<DataStartup> startData({
  OpenDatabase open = openAppDatabase,
  RunDevSeed seed = runDevSeed,
  ReadSession readSession = readStoredSession,
}) async {
  var sw = Stopwatch()..start();
  final AppDatabase db;
  try {
    db = await open();
  } catch (e, st) {
    final error = redactDbError(e);
    _log.severe(
      'database open failed after ${sw.elapsedMilliseconds}ms, '
      'showing database error screen instead of the app: '
      '${describeError(error)}',
      error,
      st,
    );
    return DataUnavailable(error);
  }
  _log.info('database opened in ${sw.elapsedMilliseconds}ms');

  final session = await _restoreSession(readSession);

  sw = Stopwatch()..start();
  DevSeedResult result;
  try {
    result = await seed(db);
  } catch (e, st) {
    final error = redactDbError(e);
    _log.severe(
      'dev seed crashed after ${sw.elapsedMilliseconds}ms, '
      'starting without demo data: ${describeError(error)}',
      error,
      st,
    );
    result = DevSeedResult(DevSeedStatus.failed, elapsed: sw.elapsed);
  }
  _logSeed(result, sw.elapsedMilliseconds);

  LocalDate? todayOverride;
  if (kDebugMode) {
    todayOverride = await loadTodayOverride(DriftPrefsRepository(db));
  }
  return DataReady(db, result, todayOverride: todayOverride, session: session);
}

Future<Session?> _restoreSession(ReadSession read) async {
  final sw = Stopwatch()..start();
  try {
    return await read();
  } catch (e, st) {
    _sessionLog.warning(
      'session restore failed after ${sw.elapsedMilliseconds}ms '
      '→ starting without session: ${describeError(e)}',
      e,
      st,
    );
    return null;
  }
}

void _logSeed(DevSeedResult result, int ms) {
  switch (result.status) {
    case DevSeedStatus.off:
      _log.info('dev seed off in ${ms}ms: DEV_SEED not set');
    case DevSeedStatus.ignored:
      _log.info('dev seed ignored in ${ms}ms: reason in [seed] warning above');
    case DevSeedStatus.skipped:
      _log.info('dev seed skipped in ${ms}ms: database not empty');
    case DevSeedStatus.seeded:
      _log.info(
        'dev seed done in ${ms}ms budgets=${result.budgets} '
        'categories=${result.categories} expenses=${result.expenses}',
      );
    case DevSeedStatus.failed:
      _log.warning(
        'dev seed failed in ${ms}ms, starting without demo data: '
        'error in [seed] above',
      );
  }
}

Widget appRoot(DataStartup data) => switch (data) {
  DataReady(:final db, :final todayOverride, :final session) => ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      if (session != null)
        sessionProvider.overrideWithBuild(
          (ref, _) => SessionActive(session.user),
        ),
      if (kDebugMode && todayOverride != null)
        todayOverrideProvider.overrideWithBuild((ref, _) => todayOverride),
    ],
    observers: const [ProviderLogger()],
    child: const RecurringTriggersScope(child: MilionchikApp()),
  ),
  DataUnavailable() => const DatabaseErrorApp(),
};
