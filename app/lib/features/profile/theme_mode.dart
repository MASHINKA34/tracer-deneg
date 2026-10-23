import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../data/db/redact_db_error.dart';
import '../../data/providers.dart';
import '../../data/repositories/prefs_repository.dart';

final _log = Logger('profile');

final themeModeProvider = NotifierProvider<ThemeModeSetting, ThemeMode>(
  ThemeModeSetting.new,
  name: 'themeMode',
);

final class ThemeModeSetting extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;

  Future<bool> set(ThemeMode mode) async {
    final previous = state;
    if (mode == previous) {
      _log.fine('theme mode=${mode.name} chosen again: already applied');
      return true;
    }
    final sw = Stopwatch()..start();
    try {
      await ref
          .read(prefsRepositoryProvider)
          .setString(PrefKeys.themeMode, mode.name);
    } catch (e, st) {
      final error = redactDbError(e);
      _log.warning(
        'theme mode=${mode.name} not saved after ${sw.elapsedMilliseconds}ms, '
        'keeping mode=${previous.name}: ${describeError(error)}',
        error,
        st,
      );
      return false;
    }
    if (!ref.mounted) {
      _log.warning(
        'theme mode=${mode.name} saved, but the app scope is gone: applies '
        'after restart',
      );
      return true;
    }
    state = mode;
    _log.info(
      'theme changed mode=${mode.name} previous=${previous.name} '
      'in ${sw.elapsedMilliseconds}ms',
    );
    return true;
  }
}

ThemeMode? themeModeFromPref(String? value) {
  for (final mode in ThemeMode.values) {
    if (mode.name == value) return mode;
  }
  return null;
}

Future<ThemeMode> loadThemeMode(PrefsRepository prefs) async {
  final sw = Stopwatch()..start();
  final String? stored;
  try {
    stored = await prefs.getString(PrefKeys.themeMode);
  } catch (e, st) {
    final error = redactDbError(e);
    _log.warning(
      'theme mode read failed after ${sw.elapsedMilliseconds}ms, starting '
      'with mode=${ThemeMode.system.name}: ${describeError(error)}',
      error,
      st,
    );
    return ThemeMode.system;
  }
  if (stored == null) {
    _log.info(
      'theme mode=${ThemeMode.system.name}: not chosen yet '
      'in ${sw.elapsedMilliseconds}ms',
    );
    return ThemeMode.system;
  }
  final mode = themeModeFromPref(stored);
  if (mode == null) {
    _log.warning(
      'theme mode ignored: key=${PrefKeys.themeMode} has unknown value '
      'length=${stored.length}, starting with mode=${ThemeMode.system.name}',
    );
    return ThemeMode.system;
  }
  _log.info(
    'theme mode=${mode.name} from key=${PrefKeys.themeMode} '
    'in ${sw.elapsedMilliseconds}ms',
  );
  return mode;
}
