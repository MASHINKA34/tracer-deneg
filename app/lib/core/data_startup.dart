import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
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
import '../data/holiday_settings.dart';
import '../data/providers.dart';
import '../data/repositories/prefs_repository.dart';
import '../data/session/secure_values.dart';
import '../data/session/session.dart';
import '../data/session/session_providers.dart';
import '../data/session/session_state.dart';
import '../data/session/session_store.dart';
import '../data/sync/background_sync.dart';
import '../features/holidays/holiday_banner_controller.dart';
import '../features/profile/theme_mode.dart';
import '../features/reminders/reminder_settings.dart';
import '../features/startup/database_error_app.dart';
import 'auth_gate.dart';
import 'clock.dart';
import 'isolate_lock.dart';
import 'logging/error_report_triggers.dart';
import 'logging/error_reporting.dart';
import 'logging/provider_logger.dart';
import 'recurring_triggers.dart';
import 'reminder_triggers_scope.dart';
import 'sync_triggers_scope.dart';

final _log = Logger('app');

final _sessionLog = Logger('session');

final _seedLog = Logger('seed');

final _authLog = Logger('auth');

typedef OpenDatabase = Future<AppDatabase> Function();

typedef RunDevSeed = Future<DevSeedResult> Function(AppDatabase db);

typedef ReadSession = Future<Session?> Function();

sealed class DataStartup {
  const DataStartup();
}

final class DataReady extends DataStartup {
  const DataReady(
    this.db,
    this.seed, {
    this.todayOverride,
    this.session,
    this.themeMode = ThemeMode.system,
    this.holidaySettings,
    this.hiddenHolidayBanners = const {},
    this.reminders = ReminderSettings.standard,
  });

  final AppDatabase db;
  final DevSeedResult seed;
  final LocalDate? todayOverride;
  final Session? session;
  final ThemeMode themeMode;
  final CachedHolidaySettings? holidaySettings;
  final Set<String> hiddenHolidayBanners;
  final ReminderSettings reminders;

  bool get devSeedDemo =>
      seed.status == DevSeedStatus.seeded ||
      seed.status == DevSeedStatus.skipped;
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
  String devSeedFlag = devSeedDefine,
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
    result = await _devSeedBlocked(db, session, devSeedFlag)
        ? DevSeedResult(DevSeedStatus.ignored, elapsed: sw.elapsed)
        : await seed(db);
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
  final themeMode = await loadThemeMode(DriftPrefsRepository(db));
  final holidaySettings = await loadHolidaySettings(
    DriftPrefsRepository(db),
    userId: session?.user.userId,
  );
  final hiddenHolidayBanners = await loadHiddenHolidayBanners(
    DriftPrefsRepository(db),
  );
  final reminders = await loadReminderSettings(DriftPrefsRepository(db));
  return DataReady(
    db,
    result,
    todayOverride: todayOverride,
    session: session,
    themeMode: themeMode,
    holidaySettings: holidaySettings,
    hiddenHolidayBanners: hiddenHolidayBanners,
    reminders: reminders,
  );
}

Future<bool> _devSeedBlocked(
  AppDatabase db,
  Session? session,
  String flag,
) async {
  if (flag.isEmpty || !kDebugMode) return false;
  if (session != null) {
    _seedLog.warning(
      'DEV_SEED=$flag ignored: signed in (session userId='
      '${session.user.userId}) → no demo data, account data and sign-in '
      'work as usual',
    );
    return true;
  }
  final sw = Stopwatch()..start();
  final bool? signedInBefore;
  try {
    signedInBefore = await DriftPrefsRepository(db)
        .getBool(PrefKeys.signedInBefore);
  } catch (e, st) {
    final error = redactDbError(e);
    _seedLog.warning(
      'DEV_SEED=$flag ignored: reading ${PrefKeys.signedInBefore} failed '
      'after ${sw.elapsedMilliseconds}ms → treated as signed in before, no '
      'demo data: ${describeError(error)}',
      error,
      st,
    );
    return true;
  }
  if (signedInBefore ?? false) {
    _seedLog.warning(
      'DEV_SEED=$flag ignored: this phone signed in before '
      '(${PrefKeys.signedInBefore}) → no demo data, sign-in screen as usual',
    );
    return true;
  }
  _seedLog.fine(
    'DEV_SEED=$flag allowed: no session and never signed in '
    '(checked in ${sw.elapsedMilliseconds}ms)',
  );
  return false;
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

Widget appRoot(
  DataStartup data, {
  ErrorReporting? reporting,
  bool background = false,
}) => switch (data) {
  DataReady(
    :final db,
    :final todayOverride,
    :final session,
    :final themeMode,
    :final holidaySettings,
    :final hiddenHolidayBanners,
    :final reminders,
  ) =>
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        themeModeProvider.overrideWithBuild((ref, _) => themeMode),
        reminderSettingsProvider.overrideWithBuild((ref, _) => reminders),
        signInRequiredProvider.overrideWithValue(_signInRequired(data)),
        if (session != null)
          sessionProvider.overrideWithBuild(
            (ref, _) => SessionActive(session.user),
          ),
        if (kDebugMode && todayOverride != null)
          todayOverrideProvider.overrideWithBuild((ref, _) => todayOverride),
        if (holidaySettings != null)
          startupHolidaySettingsProvider.overrideWithValue(holidaySettings),
        if (hiddenHolidayBanners.isNotEmpty)
          startupHiddenHolidayBannersProvider.overrideWithValue(
            hiddenHolidayBanners,
          ),
        if (reporting != null)
          errorReportingProvider.overrideWithValue(reporting),
        if (background) ...[
          isolateCoordinationProvider.overrideWithValue(
            IsolateCoordination.app(),
          ),
          backgroundSyncProvider.overrideWith(BackgroundSync.forApp),
        ],
      ],
      observers: const [ProviderLogger()],
      child: const RecurringTriggersScope(
        child: ErrorReportTriggersScope(
          child: SyncTriggersScope(
            child: ReminderTriggersScope(child: MilionchikApp()),
          ),
        ),
      ),
    ),
  DataUnavailable() => const DatabaseErrorApp(),
};

bool _signInRequired(DataReady data) {
  final demo = data.devSeedDemo;
  _authLog.info(
    'sign-in gate: session=${data.session == null ? 'absent' : 'present'} '
    'devSeed=${data.seed.status.name} → '
    '${demo ? 'DEV_SEED demo, app opens without sign-in' : 'sign-in screen when there is no session'}',
  );
  return !demo;
}
