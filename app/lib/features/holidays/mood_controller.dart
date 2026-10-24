import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../core/clock.dart';
import '../../core/recurring_triggers.dart'
    show TriggerTimer, untilNextMidnight;
import '../../data/holiday_settings.dart';

final _log = Logger('mood');

enum MoodReason { season, holiday, birthday, off }

enum MoodTrigger {
  startup('startup'),
  midnight('midnight'),
  resumed('app resumed'),
  settings('holiday settings changed'),
  clock('today override changed');

  const MoodTrigger(this.label);

  final String label;
}

final class MoodToday {
  const MoodToday({
    required this.date,
    required this.settings,
    required this.mood,
    required this.reason,
    this.holiday,
    this.skipped = const [],
  });

  final LocalDate date;
  final HolidaySettings settings;
  final Mood mood;
  final MoodReason reason;
  final HolidayPhase? holiday;
  final List<HolidayKey> skipped;

  @override
  bool operator ==(Object other) =>
      other is MoodToday &&
      other.date == date &&
      other.settings == settings &&
      other.mood == mood &&
      other.reason == reason &&
      other.holiday == holiday;

  @override
  int get hashCode => Object.hash(date, settings, mood, reason, holiday);

  @override
  String toString() => 'MoodToday($date ${mood.name} ${reason.name})';
}

MoodToday moodTodayFor(LocalDate date, HolidaySettings settings) {
  final mood = moodOn(date, settings);
  final holiday = activeHoliday(date, settings);
  final reason = !settings.enabled
      ? MoodReason.off
      : holiday == null
      ? MoodReason.season
      : holiday.key == HolidayKey.birthday
      ? MoodReason.birthday
      : MoodReason.holiday;
  final skipped = [
    for (final occurrence in holidaysOn(date, birthday: settings.birthday))
      if (!settings.enabled || settings.disabled.contains(occurrence.key))
        occurrence.key,
  ];
  return MoodToday(
    date: date,
    settings: settings,
    mood: mood,
    reason: reason,
    holiday: holiday,
    skipped: skipped,
  );
}

Mood monthCardMood(YearMonth month, MoodToday today) =>
    month == YearMonth.of(today.date)
    ? today.mood
    : Mood.ofSeason(seasonOf(month.month));

final moodTimerProvider = Provider<TriggerTimer>(
  (ref) => Timer.new,
  name: 'moodTimer',
);

final moodControllerProvider = NotifierProvider<MoodController, MoodToday>(
  MoodController.new,
  name: 'mood',
);

final class MoodController extends Notifier<MoodToday> {
  static const Duration minMidnightDelay = Duration(seconds: 1);

  MoodToday? _current;
  Timer? _midnight;

  bool get midnightScheduled => _midnight?.isActive ?? false;

  @override
  MoodToday build() {
    final clock = ref.watch(clockProvider);
    final settings = ref.watch(holidaySettingsProvider);
    ref.onDispose(_cancelMidnight);
    final previous = _current;
    final trigger = previous == null
        ? MoodTrigger.startup
        : previous.settings != settings
        ? MoodTrigger.settings
        : MoodTrigger.clock;
    final next = _recalculate(clock, settings, trigger, previous);
    _scheduleMidnight(clock);
    return next;
  }

  void resumed() {
    if (!ref.mounted) return;
    final clock = ref.read(clockProvider);
    final today = clock.today();
    final current = _current;
    if (current != null && current.date == today) {
      _log.fine(
        'app resumed, still $today: mood=${current.mood.name} kept, '
        'midnight timer reset',
      );
    } else {
      state = _recalculate(
        clock,
        ref.read(holidaySettingsProvider),
        MoodTrigger.resumed,
        current,
      );
    }
    _scheduleMidnight(clock);
  }

  MoodToday _recalculate(
    Clock clock,
    HolidaySettings settings,
    MoodTrigger trigger,
    MoodToday? previous,
  ) {
    final next = moodTodayFor(clock.today(), settings);
    _current = next;
    final change = previous == null
        ? ''
        : previous.mood == next.mood
        ? ' (unchanged)'
        : ' (was ${previous.mood.name} on ${previous.date})';
    _log.info(
      'mood recalculated trigger=${trigger.label} date=${next.date} '
      'mood=${next.mood.name} reason=${_reasonText(next)} '
      'settings=${next.settings}$change',
    );
    return next;
  }

  void _scheduleMidnight(Clock clock) {
    _cancelMidnight();
    final now = clock.now();
    var delay = untilNextMidnight(now);
    if (delay < minMidnightDelay) delay = minMidnightDelay;
    _midnight = ref.read(moodTimerProvider)(delay, _onMidnight);
    _log.fine(
      'mood midnight timer set in ${delay.inHours}h${delay.inMinutes % 60}m'
      '${delay.inSeconds % 60}s now=$now',
    );
  }

  void _cancelMidnight() {
    _midnight?.cancel();
    _midnight = null;
  }

  void _onMidnight() {
    _midnight = null;
    if (!ref.mounted) return;
    final clock = ref.read(clockProvider);
    final today = clock.today();
    final current = _current;
    if (current != null && current.date == today) {
      _log.fine('mood midnight timer fired, still $today: rescheduling');
    } else {
      state = _recalculate(
        clock,
        ref.read(holidaySettingsProvider),
        MoodTrigger.midnight,
        current,
      );
    }
    _scheduleMidnight(clock);
  }
}

String _reasonText(MoodToday today) {
  final skipped = today.skipped.isEmpty
      ? ''
      : ' skipped=[${today.skipped.map((k) => k.name).join(',')}]';
  final holiday = today.holiday;
  return switch (today.reason) {
    MoodReason.off => 'off (holidays turned off)$skipped',
    MoodReason.season => 'season$skipped',
    MoodReason.birthday => 'birthday$skipped',
    MoodReason.holiday =>
      'holiday holiday=${holiday!.key.name} stage=${holiday.stage.name} '
          'daysUntilDay=${holiday.daysUntilDay}$skipped',
  };
}
