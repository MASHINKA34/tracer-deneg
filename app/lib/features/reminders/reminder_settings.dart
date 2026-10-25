import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../data/db/redact_db_error.dart';
import '../../data/providers.dart';
import '../../data/repositories/prefs_repository.dart';

final _log = Logger('reminders');

final class ReminderTime {
  const ReminderTime(this.hour, this.minute);

  static const ReminderTime standard = ReminderTime(21, 0);

  static const int minutesPerDay = 24 * 60;

  static ReminderTime? fromMinutes(int minutes) {
    if (minutes < 0 || minutes >= minutesPerDay) return null;
    return ReminderTime(minutes ~/ 60, minutes % 60);
  }

  final int hour;
  final int minute;

  int get minutes => hour * 60 + minute;

  @override
  bool operator ==(Object other) =>
      other is ReminderTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

final class ReminderSettings {
  const ReminderSettings({
    this.enabled = false,
    this.time = ReminderTime.standard,
  });

  static const ReminderSettings standard = ReminderSettings();

  final bool enabled;
  final ReminderTime time;

  ReminderSettings copyWith({bool? enabled, ReminderTime? time}) =>
      ReminderSettings(
        enabled: enabled ?? this.enabled,
        time: time ?? this.time,
      );

  @override
  bool operator ==(Object other) =>
      other is ReminderSettings &&
      other.enabled == enabled &&
      other.time == time;

  @override
  int get hashCode => Object.hash(enabled, time);

  @override
  String toString() => '${enabled ? 'on' : 'off'} time=$time';
}

final reminderSettingsProvider =
    NotifierProvider<ReminderSettingsController, ReminderSettings>(
      ReminderSettingsController.new,
      name: 'reminderSettings',
    );

final class ReminderSettingsController extends Notifier<ReminderSettings> {
  @override
  ReminderSettings build() => ReminderSettings.standard;

  Future<bool> setEnabled(bool enabled, {required String why}) => _save(
    state.copyWith(enabled: enabled),
    why,
    (prefs) => prefs.setBool(PrefKeys.remindersEnabled, enabled),
  );

  Future<bool> setTime(ReminderTime time) => _save(
    state.copyWith(time: time),
    'time picked',
    (prefs) => prefs.setInt(PrefKeys.reminderMinutes, time.minutes),
  );

  Future<bool> _save(
    ReminderSettings next,
    String why,
    Future<void> Function(PrefsRepository prefs) write,
  ) async {
    final previous = state;
    if (next == previous) {
      _log.fine('reminders $next chosen again ($why): already applied');
      return true;
    }
    final sw = Stopwatch()..start();
    try {
      await write(ref.read(prefsRepositoryProvider));
    } catch (e, st) {
      final error = redactDbError(e);
      _log.warning(
        'reminders $next not saved after ${sw.elapsedMilliseconds}ms '
        '($why), keeping $previous: ${describeError(error)}',
        error,
        st,
      );
      return false;
    }
    if (!ref.mounted) {
      _log.warning(
        'reminders $next saved ($why), but the app scope is gone: applies '
        'after restart',
      );
      return true;
    }
    state = next;
    _log.info(
      'reminders settings changed to $next previous=$previous ($why) '
      'in ${sw.elapsedMilliseconds}ms',
    );
    return true;
  }
}

Future<ReminderSettings> loadReminderSettings(PrefsRepository prefs) async {
  final sw = Stopwatch()..start();
  final bool? enabled;
  final int? minutes;
  try {
    enabled = await prefs.getBool(PrefKeys.remindersEnabled);
    minutes = await prefs.getInt(PrefKeys.reminderMinutes);
  } catch (e, st) {
    final error = redactDbError(e);
    _log.warning(
      'reminder settings read failed after ${sw.elapsedMilliseconds}ms, '
      'starting with ${ReminderSettings.standard}: ${describeError(error)}',
      error,
      st,
    );
    return ReminderSettings.standard;
  }
  var time = ReminderTime.standard;
  if (minutes != null) {
    final stored = ReminderTime.fromMinutes(minutes);
    if (stored == null) {
      _log.warning(
        'reminder time ignored: key=${PrefKeys.reminderMinutes} is out of '
        'range minutes=$minutes, using ${ReminderTime.standard}',
      );
    } else {
      time = stored;
    }
  }
  final settings = ReminderSettings(enabled: enabled ?? false, time: time);
  _log.info(
    'reminder settings $settings '
    '(${enabled == null ? 'never switched' : 'from key=${PrefKeys.remindersEnabled}'}, '
    '${minutes == null ? 'default time' : 'time from key=${PrefKeys.reminderMinutes}'}) '
    'in ${sw.elapsedMilliseconds}ms',
  );
  return settings;
}
