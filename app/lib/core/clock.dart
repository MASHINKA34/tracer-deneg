import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../data/db/redact_db_error.dart';
import '../data/providers.dart';
import '../data/repositories/prefs_repository.dart';

final _log = Logger('clock');

final class Clock {
  const Clock({this._now = DateTime.now});

  final DateTime Function() _now;

  DateTime now() => _now();

  LocalDate today() => LocalDate.fromDateTime(now());
}

Clock clockFor(LocalDate? today, {bool debugBuild = kDebugMode}) {
  if (today == null || !debugBuild) return const Clock();
  return Clock(now: () => _sameTimeOn(today, DateTime.now()));
}

DateTime _sameTimeOn(LocalDate day, DateTime real) => DateTime(
  day.year,
  day.month,
  day.day,
  real.hour,
  real.minute,
  real.second,
  real.millisecond,
  real.microsecond,
);

LocalDate _realToday() => LocalDate.fromDateTime(DateTime.now());

final clockProvider = Provider<Clock>(
  (ref) =>
      kDebugMode ? clockFor(ref.watch(todayOverrideProvider)) : const Clock(),
  name: 'clock',
);

final todayOverrideProvider = NotifierProvider<TodayOverride, LocalDate?>(
  TodayOverride.new,
  name: 'todayOverride',
);

final class TodayOverride extends Notifier<LocalDate?> {
  @override
  LocalDate? build() => null;

  Future<bool> set(LocalDate date) async {
    final sw = Stopwatch()..start();
    final previous = state;
    try {
      await ref
          .read(prefsRepositoryProvider)
          .setString(PrefKeys.todayOverride, date.toString());
    } catch (e, st) {
      final error = redactDbError(e);
      _log.warning(
        'today override set date=$date not saved after '
        '${sw.elapsedMilliseconds}ms, keeping ${previous ?? 'real date'}: '
        '${describeError(error)}',
        error,
        st,
      );
      return false;
    }
    if (!ref.mounted) {
      _log.warning(
        'today override date=$date saved, but the app scope is gone: '
        'applies after restart',
      );
      return true;
    }
    state = date;
    _log.info(
      'today override set date=$date real=${_realToday()} '
      'previous=${previous ?? 'none'} in ${sw.elapsedMilliseconds}ms '
      '(debug build)',
    );
    return true;
  }

  Future<bool> reset() async {
    final sw = Stopwatch()..start();
    final previous = state;
    try {
      await ref.read(prefsRepositoryProvider).remove(PrefKeys.todayOverride);
    } catch (e, st) {
      final error = redactDbError(e);
      _log.warning(
        'today override reset not saved after ${sw.elapsedMilliseconds}ms, '
        'keeping ${previous ?? 'real date'}: ${describeError(error)}',
        error,
        st,
      );
      return false;
    }
    if (!ref.mounted) {
      _log.warning(
        'today override reset saved, but the app scope is gone: '
        'real date after restart',
      );
      return true;
    }
    state = null;
    _log.info(
      'today override reset date=${previous ?? 'none'} → real date '
      '${_realToday()} in ${sw.elapsedMilliseconds}ms (debug build)',
    );
    return true;
  }
}

Future<LocalDate?> loadTodayOverride(PrefsRepository prefs) async {
  final sw = Stopwatch()..start();
  final String? stored;
  try {
    stored = await prefs.getString(PrefKeys.todayOverride);
  } catch (e, st) {
    final error = redactDbError(e);
    _log.warning(
      'today override read failed after ${sw.elapsedMilliseconds}ms, '
      'starting with real date ${_realToday()}: ${describeError(error)}',
      error,
      st,
    );
    return null;
  }
  if (stored == null) {
    _log.fine(
      'today override: none, real date ${_realToday()} '
      'in ${sw.elapsedMilliseconds}ms',
    );
    return null;
  }
  final date = LocalDate.tryParse(stored);
  if (date == null) {
    _log.warning(
      'today override ignored: key=${PrefKeys.todayOverride} is not a '
      'YYYY-MM-DD date length=${stored.length}, starting with real date '
      '${_realToday()}',
    );
    return null;
  }
  _log.warning(
    'today overridden date=$date real=${_realToday()} '
    'key=${PrefKeys.todayOverride} in ${sw.elapsedMilliseconds}ms: '
    'debug build, reset it in the catalog',
  );
  return date;
}
