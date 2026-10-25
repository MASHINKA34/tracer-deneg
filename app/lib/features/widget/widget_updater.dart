import 'dart:async';
import 'dart:ui' show Locale;

import 'package:drift/drift.dart' show TableUpdate, TableUpdateQuery;
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../core/auth_gate.dart';
import '../../core/clock.dart';
import '../../core/isolate_lock.dart';
import '../../core/recurring_triggers.dart' show TriggerTimer;
import '../../data/db/redact_db_error.dart';
import '../../data/holiday_settings.dart';
import '../../data/providers.dart';
import '../../data/session/session_providers.dart';
import '../../data/session/session_state.dart';
import '../../data/sync/background_job.dart';
import '../../data/sync/sync_engine.dart';
import '../../l10n/app_localizations.dart';
import '../holidays/mood_controller.dart';
import '../month/month_picker_sheet.dart' show seasonEmoji;
import '../profile/theme_mode.dart';
import 'home_widget_data.dart';
import 'home_widget_store.dart';

final _log = Logger('widget');

enum WidgetUpdateSource {
  startup('startup', redraw: true),
  expenses('expenses changed'),
  sync('sync done'),
  mood('mood changed'),
  day('day changed'),
  theme('theme changed'),
  systemTheme('system theme changed', redraw: true),
  budget('budget changed'),
  session('session changed'),
  accountCleared('account data cleared', redraw: true);

  const WidgetUpdateSource(this.label, {this.redraw = false});

  final String label;
  final bool redraw;
}

typedef WidgetDayTotals =
    Future<Map<int, Money>> Function(String budgetId, YearMonth month);

typedef WidgetSignedOutReason = String? Function();

typedef _Failure = ({Object error, StackTrace stack});

final class _WidgetSnapshot {
  const _WidgetSnapshot(
    this.data, {
    required this.today,
    this.budgetId,
    this.signedOutBecause,
  });

  final HomeWidgetData data;
  final LocalDate today;
  final String? budgetId;
  final String? signedOutBecause;

  String describe() {
    final because = signedOutBecause;
    if (because != null) return '${data.describe()} because=$because';
    return '${data.describe()} budget=${budgetId ?? 'none'} '
        'month=${YearMonth.of(today)}';
  }
}

final class WidgetUpdater {
  WidgetUpdater({
    required this._store,
    required this._clock,
    required this._signedOutBecause,
    required this._selectedBudget,
    required this._dayTotals,
    required this._mood,
    required this._holidaySettings,
    required this._theme,
    this._lock,
    this._timer = Timer.new,
    AppLocalizations? l10n,
  }) : _l10n = l10n ?? lookupAppLocalizations(const Locale('ru'));

  static const Duration coalesceDelay = Duration(seconds: 1);

  static const Duration maxDelay = Duration(seconds: 3);

  final HomeWidgetStore _store;
  final Clock Function() _clock;
  final WidgetSignedOutReason _signedOutBecause;
  final Future<String?> Function() _selectedBudget;
  final WidgetDayTotals _dayTotals;
  final MoodToday Function() _mood;
  final HolidaySettings Function() _holidaySettings;
  final ThemeMode Function() _theme;
  final IsolateLock? _lock;
  final TriggerTimer _timer;
  final AppLocalizations _l10n;

  final Set<WidgetUpdateSource> _pending = {};
  Timer? _quiet;
  Timer? _deadline;
  Future<Object?> _tail = Future<Object?>.value();
  String? _lastJson;
  bool _datesReady = false;
  bool _unavailable = false;
  bool _disposed = false;

  bool get hasPending => _pending.isNotEmpty;

  Future<void> get idle => _tail.then((_) {});

  void request(WidgetUpdateSource source) {
    if (_disposed) {
      _log.fine(
        'widget update source=${source.label} after the updater was '
        'disposed → ignored',
      );
      return;
    }
    final first = _pending.isEmpty;
    _pending.add(source);
    _quiet?.cancel();
    _quiet = _timer(
      coalesceDelay,
      () => _flush('${coalesceDelay.inMilliseconds}ms without new changes'),
    );
    if (first) {
      _deadline = _timer(
        maxDelay,
        () => _flush('${maxDelay.inMilliseconds}ms limit of joined changes'),
      );
      _log.fine(
        'widget update requested source=${source.label} → in '
        '${coalesceDelay.inMilliseconds}ms if nothing else changes, at most '
        'in ${maxDelay.inMilliseconds}ms',
      );
      return;
    }
    _log.fine(
      'widget update requested source=${source.label} → joins the pending '
      'update [${_describe(_pending)}], waiting '
      '${coalesceDelay.inMilliseconds}ms again',
    );
  }

  Future<void> updateNow(String reason) async {
    final joined = _takePending();
    final full = joined.isEmpty ? reason : '$reason+${_describe(joined)}';
    final failure = await _enqueue(full, redraw: true);
    if (failure != null) {
      Error.throwWithStackTrace(failure.error, failure.stack);
    }
  }

  Future<void> updateImmediately(WidgetUpdateSource source) async {
    final sources = {source, ..._takePending()};
    final reason = _describe(sources);
    _log.fine(
      'widget update reason=$reason starts without the '
      '${coalesceDelay.inMilliseconds}ms delay: ${source.label} must reach '
      'the widget before the process can be killed',
    );
    await _enqueue(reason, redraw: true);
  }

  void dispose(String why) {
    if (_disposed) return;
    _disposed = true;
    final dropped = _takePending();
    _log.fine(
      'widget updater disposed ($why)'
      '${dropped.isEmpty ? '' : ' → pending update [${_describe(dropped)}] '
                'dropped, the next start writes the widget again'}',
    );
  }

  void _flush(String after) {
    final sources = _takePending();
    if (sources.isEmpty) return;
    final reason = _describe(sources);
    _log.fine('widget update starts reason=$reason after $after');
    unawaited(_enqueue(reason, redraw: sources.any((s) => s.redraw)));
  }

  Set<WidgetUpdateSource> _takePending() {
    _quiet?.cancel();
    _quiet = null;
    _deadline?.cancel();
    _deadline = null;
    final taken = {..._pending};
    _pending.clear();
    return taken;
  }

  Future<_Failure?> _enqueue(String reason, {required bool redraw}) {
    final run = _tail.then((_) => _update(reason, redraw: redraw));
    _tail = run;
    return run;
  }

  Future<_Failure?> _update(String reason, {required bool redraw}) async {
    if (_unavailable) {
      _log.fine(
        'widget update reason=$reason skipped: the home widget plugin is not '
        'available in this run (warning above)',
      );
      return null;
    }
    final sw = Stopwatch()..start();
    var step = 'waiting for the lock';
    IsolateLease? lease;
    try {
      lease = await _lock?.acquire('home widget update ($reason)');
      final other = lease?.waitedFor;
      final waitText = other == null
          ? ''
          : ' after waiting ${lease!.waited.inMilliseconds}ms for $other';
      step = 'reading its data';
      final snapshot = await _snapshot();
      final json = snapshot.data.encode();
      if (!redraw && json == _lastJson) {
        _log.fine(
          'widget update reason=$reason: ${snapshot.describe()} unchanged '
          'since the last write → not written, checked in '
          '${sw.elapsedMilliseconds}ms',
        );
        return null;
      }
      step = 'saving';
      await _store.show(snapshot.data, reason: reason);
      _lastJson = json;
      _log.info(
        'widget updated reason=$reason ${snapshot.describe()}$waitText '
        'in ${sw.elapsedMilliseconds}ms',
      );
      return null;
    } catch (e, st) {
      _lastJson = null;
      _failed(reason, step, e, st, sw);
      return (error: e, stack: st);
    } finally {
      lease?.release();
    }
  }

  void _failed(
    String reason,
    String step,
    Object error,
    StackTrace stack,
    Stopwatch sw,
  ) {
    if (error is MissingPluginException) {
      _unavailable = true;
      _log.warning(
        'home widget plugin is not available on this platform '
        '(${describeError(error)}) → widget updates are off until restart',
      );
      return;
    }
    if (step == 'saving') {
      _log.warning(
        'widget update reason=$reason not shown after '
        '${sw.elapsedMilliseconds}ms: the widget storage failed (error '
        'above) → the widget keeps its previous data, the next update '
        'writes and redraws it again',
      );
      return;
    }
    final safe = redactDbError(error);
    _log.severe(
      'widget update reason=$reason failed while $step after '
      '${sw.elapsedMilliseconds}ms → the widget keeps its previous data, the '
      'next update writes and redraws it again: ${describeError(safe)}',
      safe,
      stack,
    );
  }

  Future<_WidgetSnapshot> _snapshot() async {
    final today = _clock().today();
    var mood = _mood();
    if (mood.date != today) {
      _log.fine(
        'mood state is for ${mood.date}, today is $today → mood for today '
        'from the holiday settings',
      );
      mood = moodTodayFor(today, _holidaySettings());
    }
    final theme = _theme();
    final signedOut = _signedOutBecause();
    if (signedOut != null) {
      return _WidgetSnapshot(
        HomeWidgetData.signedOut(mood: mood.mood, theme: theme),
        today: today,
        signedOutBecause: signedOut,
      );
    }
    await _ensureDateFormats();
    final month = YearMonth.of(today);
    final budgetId = await _selectedBudget();
    var total = Money.zero;
    var todayTotal = Money.zero;
    var days = 0;
    if (budgetId == null) {
      _log.fine(
        'widget data: no budget to show yet (no personal budget in the '
        'database) → zero totals for $month',
      );
    } else {
      final totals = await _dayTotals(budgetId, month);
      days = totals.length;
      for (final amount in totals.values) {
        total += amount;
      }
      todayTotal = totals[today.day] ?? Money.zero;
    }
    final emoji = mood.holiday?.key.emoji ?? seasonEmoji(month);
    _log.fine(
      'widget data budget=${budgetId ?? 'none'} date=$today days=$days '
      'total=${total.format()} today=${todayTotal.format()} '
      'mood=${mood.mood.name} emoji=$emoji theme=${theme.name}',
    );
    return _WidgetSnapshot(
      HomeWidgetData.month(
        l10n: _l10n,
        mood: mood.mood,
        theme: theme,
        emoji: emoji,
        month: month,
        total: total,
        today: todayTotal,
      ),
      today: today,
      budgetId: budgetId,
    );
  }

  Future<void> _ensureDateFormats() async {
    if (_datesReady) return;
    final sw = Stopwatch()..start();
    await initializeDateFormatting('ru');
    _datesReady = true;
    _log.fine('ru date formats ready in ${sw.elapsedMilliseconds}ms');
  }
}

String _describe(Iterable<WidgetUpdateSource> sources) =>
    sources.map((s) => s.label).join('+');

String? widgetSignedOutBecause(Ref ref) {
  final session = ref.read(sessionProvider);
  if (session is! SessionActive && ref.read(signInRequiredProvider)) {
    return 'session ${session.name}';
  }
  final held = ref.read(syncEngineProvider).heldBy;
  if (held != null) return 'account data cleared by $held';
  return null;
}

Future<String?> widgetSelectedBudget(Ref ref) async {
  final selected = ref.container.listen(
    selectedBudgetIdProvider.future,
    (_, _) {},
  );
  try {
    return await selected.read();
  } finally {
    selected.close();
  }
}

final widgetUpdateTimerProvider = Provider<TriggerTimer>(
  (ref) => Timer.new,
  name: 'widgetUpdateTimer',
);

final widgetExpenseChangesProvider = Provider<Stream<Set<TableUpdate>>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.tableUpdates(TableUpdateQuery.onTable(db.expenses));
}, name: 'widgetExpenseChanges');

final widgetUpdaterProvider = Provider<WidgetUpdater>((ref) {
  final updater = WidgetUpdater(
    store: ref.watch(homeWidgetStoreProvider),
    clock: () => ref.read(clockProvider),
    signedOutBecause: () => widgetSignedOutBecause(ref),
    selectedBudget: () => widgetSelectedBudget(ref),
    dayTotals: (budgetId, month) =>
        ref.read(monthQueriesProvider).watchDayTotals(budgetId, month).first,
    mood: () => ref.read(moodControllerProvider),
    holidaySettings: () => ref.read(holidaySettingsProvider),
    theme: () => ref.read(themeModeProvider),
    lock: ref.read(isolateCoordinationProvider)?.homeWidget,
    timer: ref.watch(widgetUpdateTimerProvider),
  );
  ref.onDispose(() => updater.dispose('provider scope disposed'));
  return updater;
}, name: 'widgetUpdater');

Override homeWidgetUpdateOverride() => homeWidgetUpdateProvider.overrideWith(
  (ref) => ref.watch(widgetUpdaterProvider).updateNow,
);

List<Override> backgroundWidgetOverrides({
  required ThemeMode themeMode,
  CachedHolidaySettings? holidaySettings,
}) => [
  signInRequiredProvider.overrideWithValue(true),
  themeModeProvider.overrideWithBuild((ref, _) => themeMode),
  if (holidaySettings != null)
    startupHolidaySettingsProvider.overrideWithValue(holidaySettings),
  homeWidgetUpdateOverride(),
];
