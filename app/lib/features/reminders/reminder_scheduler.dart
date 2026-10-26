import 'dart:async';
import 'dart:ui' show Locale;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../core/auth_gate.dart';
import '../../core/clock.dart';
import '../../core/router.dart';
import '../../data/db/redact_db_error.dart';
import '../../data/providers.dart';
import '../../data/session/session_providers.dart';
import '../../data/session/session_state.dart';
import '../../l10n/app_localizations.dart';
import 'reminder_notifications.dart';
import 'reminder_plan.dart';
import 'reminder_settings.dart';

final _log = Logger('reminders');

typedef OwnExpenseCheck = Future<bool> Function(LocalDate day);

typedef TimeZoneDatabaseLoader = void Function();

final class ReminderTaps {
  void Function(Uri link)? _open;
  Uri? _waiting;

  void attach(void Function(Uri link) open) {
    _open = open;
    final waiting = _waiting;
    if (waiting == null) return;
    _waiting = null;
    _log.fine('reminder tap waited for the app → opening $waiting now');
    open(waiting);
  }

  void detach() {
    _open = null;
  }

  void deliver(Uri link) {
    final open = _open;
    if (open == null) {
      _log.fine('reminder tap before the app is shown → $link waits for it');
      _waiting = link;
      return;
    }
    open(link);
  }
}

final class ReminderScheduler {
  ReminderScheduler({
    required this._notifications,
    required this._clock,
    required this._settings,
    required this._accountActive,
    required this._ownExpenseOn,
    required this._texts,
    required this._taps,
    this._loadTimeZones = tzdata.initializeTimeZones,
  });

  final ReminderNotifications _notifications;
  final Clock Function() _clock;
  final ReminderSettings Function() _settings;
  final bool Function() _accountActive;
  final OwnExpenseCheck _ownExpenseOn;
  final ReminderTexts _texts;
  final ReminderTaps _taps;
  final TimeZoneDatabaseLoader _loadTimeZones;

  Future<void>? _ready;
  Future<void> _tail = Future<void>.value();
  bool _zonesLoaded = false;
  ({LocalDate day, String zone})? _planned;

  ({LocalDate day, String zone})? get planned => _planned;

  Future<void> start() => _serial('startup', () => _replan('startup'));

  Future<void> reschedule(String reason) =>
      _serial(reason, () => _replan(reason));

  Future<void> refreshIfStale(String event) =>
      _serial(event, () => _refresh(event));

  Future<void> cancelToday(String reason) =>
      _serial(reason, () => _cancelToday(reason));

  Future<void> cancelAll(String reason) =>
      _serial(reason, () => _cancelAllOnRequest(reason));

  Future<bool> notificationsAllowed(String event) async {
    final sw = Stopwatch()..start();
    try {
      final allowed = await _notifications.areEnabled();
      _log.fine(
        'notifications allowed=$allowed ($event) in ${sw.elapsedMilliseconds}ms',
      );
      return allowed;
    } catch (e, st) {
      _log.severe(
        'notification permission check failed ($event) after '
        '${sw.elapsedMilliseconds}ms → treated as allowed, nothing switched '
        'off: ${describeError(e)}',
        e,
        st,
      );
      return true;
    }
  }

  Future<bool> requestPermission() async {
    final sw = Stopwatch()..start();
    _log.info('notification permission requested: reminders switch turned on');
    try {
      final granted = await _notifications.requestPermission();
      _log.info(
        'notification permission answer=${granted ? 'granted' : 'denied'} '
        'in ${sw.elapsedMilliseconds}ms',
      );
      return granted;
    } catch (e, st) {
      _log.severe(
        'notification permission request failed after '
        '${sw.elapsedMilliseconds}ms → treated as denied: ${describeError(e)}',
        e,
        st,
      );
      return false;
    }
  }

  Future<bool> openSettings() async {
    final sw = Stopwatch()..start();
    try {
      final opened = await _notifications.openSettings();
      _log.log(
        opened ? Level.INFO : Level.WARNING,
        'system notification settings ${opened ? 'opened' : 'not opened: no '
                  'settings screen for the app'} in ${sw.elapsedMilliseconds}ms',
      );
      return opened;
    } catch (e, st) {
      _log.severe(
        'system notification settings not opened after '
        '${sw.elapsedMilliseconds}ms: ${describeError(e)}',
        e,
        st,
      );
      return false;
    }
  }

  Future<void> _serial(String what, Future<void> Function() body) {
    final run = _tail.then((_) => body());
    return _tail = run.catchError((Object e, StackTrace st) {
      _log.severe('reminders "$what" crashed: ${describeError(e)}', e, st);
    });
  }

  Future<bool> _ensureReady() async {
    final ready = _ready ??= _initialize();
    try {
      await ready;
      return true;
    } catch (_) {
      if (identical(_ready, ready)) _ready = null;
      _log.fine('notifications plugin not ready (error above) → skipped');
      return false;
    }
  }

  Future<void> _initialize() async {
    final sw = Stopwatch()..start();
    final ReminderTap? launch;
    try {
      launch = await _notifications.initialize(
        onTap: (tap) => _tapped(tap, app: 'running'),
      );
    } catch (e, st) {
      _log.severe(
        'notifications plugin init failed after ${sw.elapsedMilliseconds}ms '
        '→ reminders not planned now, retried on the next change: '
        '${describeError(e)}',
        e,
        st,
      );
      rethrow;
    }
    _log.info(
      'notifications plugin ready channel=$reminderChannelId '
      'launchedByReminder=${launch != null} in ${sw.elapsedMilliseconds}ms',
    );
    if (launch != null) _tapped(launch, app: 'launched by tap');
  }

  void _tapped(ReminderTap tap, {required String app}) {
    final day = reminderDayOf(tap.id);
    final payload = tap.payload;
    final link = payload == null ? null : Uri.tryParse(payload);
    if (link == null || !isAddExpenseLink(link)) {
      _log.warning(
        'notification tapped id=${tap.id ?? '-'} app=$app with unexpected '
        'payload length=${payload?.length ?? 0} → opening $reminderLink anyway',
      );
    }
    _log.info(
      'reminder tapped id=${tap.id ?? '-'} day=${day ?? '-'} app=$app → '
      '$reminderLink',
    );
    _taps.deliver(reminderLink);
  }

  Future<({tz.Location? location, String name})> _zone() async {
    final sw = Stopwatch()..start();
    String? name;
    try {
      if (!_zonesLoaded) {
        _loadTimeZones();
        _zonesLoaded = true;
        _log.fine('time zone database loaded in ${sw.elapsedMilliseconds}ms');
      }
      name = await _notifications.localTimeZone();
      return (location: tz.getLocation(name), name: name);
    } on tz.LocationNotFoundException catch (e) {
      _log.warning(
        'time zone $name is not in the time zone database → reminders '
        'planned by the phone clock offset in UTC: ${describeError(e)}',
      );
      return (location: null, name: 'UTC(phone offset, $name)');
    } catch (e, st) {
      _log.warning(
        'local time zone not read after ${sw.elapsedMilliseconds}ms → '
        'reminders planned by the phone clock offset in UTC: '
        '${describeError(e)}',
        e,
        st,
      );
      return (location: null, name: 'UTC(phone offset)');
    }
  }

  Future<void> _replan(String reason) async {
    final sw = Stopwatch()..start();
    final settings = _settings();
    if (!settings.enabled) {
      if (_ready == null) {
        _planned = null;
        _log.fine(
          'reminders off reason=$reason → nothing planned, notifications '
          'untouched',
        );
        return;
      }
      await _cancelAll('reminders switched off', reason, sw);
      return;
    }
    if (!_accountActive()) {
      await _cancelAll('no signed-in account', reason, sw);
      return;
    }
    if (!await _ensureReady()) return;
    final zone = await _zone();
    final now = _clock().now();
    final today = LocalDate.fromDateTime(now);
    var todayDone = false;
    try {
      todayDone = await _ownExpenseOn(today);
    } catch (e, st) {
      final error = redactDbError(e);
      _log.warning(
        'reminders: expense check for today $today failed → today\'s '
        'reminder kept: ${describeError(error)}',
        error,
        st,
      );
    }
    final plan = planReminders(
      now: now,
      time: settings.time,
      todayHasExpense: todayDone,
      zone: zone.location,
    );
    try {
      await _notifications.cancelPending();
    } catch (e, st) {
      _log.severe(
        'reminders: old reminders not cancelled before planning '
        'reason=$reason → new ones planned over them: ${describeError(e)}',
        e,
        st,
      );
    }
    final planned = <LocalDate>[];
    final past = <LocalDate>[];
    var failed = 0;
    for (final request in plan.reminders) {
      try {
        if (await _notifications.schedule(request, _texts)) {
          planned.add(request.day);
        } else {
          past.add(request.day);
        }
      } catch (e, st) {
        failed++;
        _log.severe(
          'reminder for ${request.day} not planned id=${request.id} '
          'at=${request.at} reason=$reason: ${describeError(e)}',
          e,
          st,
        );
      }
    }
    _planned = (day: today, zone: zone.name);
    final problems = [
      if (past.isNotEmpty)
        'pastByPhoneClock=${past.length} (${past.join(',')})',
      if (failed > 0) 'failed=$failed (errors above)',
    ];
    _log.log(
      failed > 0 ? Level.WARNING : Level.INFO,
      'reminders planned count=${planned.length} '
      'dates=${planned.isEmpty ? '-' : planned.join(',')} '
      'at=${settings.time} tz=${zone.name} '
      'today=$today ${plan.todayReminder.label}'
      '${problems.isEmpty ? '' : ' ${problems.join(' ')}'} '
      'reason=$reason in ${sw.elapsedMilliseconds}ms',
    );
  }

  Future<void> _refresh(String event) async {
    if (!_settings().enabled || !_accountActive()) {
      _log.fine('$event: reminders off or no account → nothing to refresh');
      return;
    }
    final planned = _planned;
    if (planned == null) {
      await _replan('$event, nothing planned in this run yet');
      return;
    }
    final today = _clock().today();
    if (planned.day != today) {
      await _replan('$event, day changed ${planned.day} → $today');
      return;
    }
    final zone = await _zone();
    if (zone.name != planned.zone) {
      await _replan('$event, time zone changed ${planned.zone} → ${zone.name}');
      return;
    }
    _log.fine(
      '$event: reminders planned today $today in tz=${zone.name} → '
      'nothing to refresh',
    );
  }

  Future<void> _cancelToday(String reason) async {
    final today = _clock().today();
    if (!_settings().enabled) {
      _log.fine('reminders off → nothing to cancel for today $today ($reason)');
      return;
    }
    if (!await _ensureReady()) return;
    final id = reminderIdFor(today);
    final sw = Stopwatch()..start();
    try {
      await _notifications.cancel(id);
    } catch (e, st) {
      _log.severe(
        'reminder for today $today not cancelled id=$id after '
        '${sw.elapsedMilliseconds}ms ($reason): ${describeError(e)}',
        e,
        st,
      );
      return;
    }
    _log.info(
      'reminder for today $today cancelled id=$id: $reason '
      'in ${sw.elapsedMilliseconds}ms',
    );
  }

  Future<void> _cancelAllOnRequest(String reason) async {
    final sw = Stopwatch()..start();
    if (_ready == null && !_settings().enabled) {
      _log.fine(
        'reminders off and never planned in this run → nothing to cancel '
        '($reason)',
      );
      return;
    }
    await _cancelAll(reason, reason, sw);
  }

  Future<void> _cancelAll(String why, String reason, Stopwatch sw) async {
    if (!await _ensureReady()) return;
    try {
      await _notifications.cancelAll();
    } catch (e, st) {
      _log.severe(
        'reminders not cancelled ($why) reason=$reason after '
        '${sw.elapsedMilliseconds}ms: ${describeError(e)}',
        e,
        st,
      );
      return;
    }
    _planned = null;
    _log.info(
      'all reminders cancelled: $why reason=$reason '
      'in ${sw.elapsedMilliseconds}ms',
    );
  }
}

final reminderTapsProvider = Provider<ReminderTaps>(
  (ref) => ReminderTaps(),
  name: 'reminderTaps',
);

ReminderTexts reminderTextsIn(AppLocalizations l10n) => ReminderTexts(
  title: l10n.reminderNotificationTitle,
  body: l10n.reminderNotificationBody,
  channelName: l10n.reminderChannelName,
  channelDescription: l10n.reminderChannelDescription,
);

final reminderSchedulerProvider = Provider<ReminderScheduler>(
  (ref) => ReminderScheduler(
    notifications: ref.watch(reminderNotificationsProvider),
    clock: () => ref.read(clockProvider),
    settings: () => ref.read(reminderSettingsProvider),
    accountActive: () =>
        ref.read(sessionProvider) is SessionActive ||
        !ref.read(signInRequiredProvider),
    ownExpenseOn: (day) async => ref
        .read(reminderQueriesProvider)
        .hasOwnExpenseOn(
          day,
          userId: await ref.read(currentUserProvider).userId(),
        ),
    texts: reminderTextsIn(lookupAppLocalizations(const Locale('ru'))),
    taps: ref.watch(reminderTapsProvider),
  ),
  name: 'reminderScheduler',
);
