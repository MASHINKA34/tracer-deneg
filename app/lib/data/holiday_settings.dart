import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import 'api/account_api.dart';
import 'api/api_exception.dart';
import 'db/redact_db_error.dart';
import 'providers.dart';
import 'repositories/prefs_repository.dart';
import 'session/session_providers.dart';
import 'session/session_state.dart';
import 'sync/pull_service.dart';

final _log = Logger('holidays');

final class CachedHolidaySettings {
  const CachedHolidaySettings({required this.userId, required this.settings});

  final String? userId;
  final HolidaySettings settings;

  @override
  bool operator ==(Object other) =>
      other is CachedHolidaySettings &&
      other.userId == userId &&
      other.settings == settings;

  @override
  int get hashCode => Object.hash(userId, settings);

  @override
  String toString() => 'userId=${userId ?? '-'} $settings';
}

String encodeHolidaySettings(CachedHolidaySettings cached) {
  final settings = cached.settings;
  return jsonEncode({
    'userId': cached.userId,
    'enabled': settings.enabled,
    'disabled': [for (final key in settings.disabled) key.key]..sort(),
    'birthdayMonth': settings.birthday?.month,
    'birthdayDay': settings.birthday?.day,
  });
}

CachedHolidaySettings decodeHolidaySettings(String text) {
  final reader = JsonReader.of(jsonDecode(text), 'HolidaySettingsCache');
  return CachedHolidaySettings(
    userId: reader.optString('userId'),
    settings: HolidaySettings(
      enabled: reader.boolean('enabled'),
      disabled: {
        for (final key in reader.strings('disabled')) ?HolidayKey.fromKey(key),
      },
      birthday: MonthDay.fromParts(
        reader.optInteger('birthdayMonth'),
        reader.optInteger('birthdayDay'),
      ),
    ),
  );
}

Future<CachedHolidaySettings?> loadHolidaySettings(
  PrefsRepository prefs, {
  required String? userId,
}) async {
  final sw = Stopwatch()..start();
  final String? stored;
  try {
    stored = await prefs.getString(PrefKeys.holidaySettings);
  } catch (e, st) {
    final error = redactDbError(e);
    _log.warning(
      'holiday settings read failed after ${sw.elapsedMilliseconds}ms → '
      'default settings until GET /me: ${describeError(error)}',
      error,
      st,
    );
    return null;
  }
  if (stored == null) {
    _log.info(
      'holiday settings: not cached yet in ${sw.elapsedMilliseconds}ms → '
      'default settings until GET /me',
    );
    return null;
  }
  final CachedHolidaySettings cached;
  try {
    cached = decodeHolidaySettings(stored);
  } on FormatException catch (e) {
    _log.warning(
      'holiday settings cache ignored: key=${PrefKeys.holidaySettings} is '
      'not valid (${withoutBirthdayValues(e.message)}) '
      'length=${stored.length} → default settings until GET /me',
    );
    return null;
  }
  if (cached.userId != userId) {
    _log.warning(
      'holiday settings cache ignored: saved for userId=${cached.userId ?? '-'}'
      ', session userId=${userId ?? '-'} → default settings until GET /me',
    );
    return null;
  }
  _log.info(
    'holiday settings from cache $cached in ${sw.elapsedMilliseconds}ms',
  );
  return cached;
}

final startupHolidaySettingsProvider = Provider<CachedHolidaySettings?>(
  (ref) => null,
  name: 'startupHolidaySettings',
);

final accountHolidaySettingsProvider =
    NotifierProvider<AccountHolidaySettings, CachedHolidaySettings?>(
      AccountHolidaySettings.new,
      name: 'accountHolidaySettings',
    );

final class AccountHolidaySettings extends Notifier<CachedHolidaySettings?> {
  @override
  CachedHolidaySettings? build() {
    ref.listen<String?>(
      sessionProvider.select((s) => s.userId),
      _sessionUserChanged,
    );
    return ref.read(startupHolidaySettingsProvider);
  }

  void _sessionUserChanged(String? previous, String? next) {
    if (previous == next) return;
    final dropped = state;
    if (dropped == null) return;
    state = null;
    _log.info(
      'holiday settings of userId=${dropped.userId ?? '-'} forgotten: '
      'session user ${previous ?? '-'} → ${next ?? '-'} → default settings '
      'until GET /me',
    );
  }

  Future<bool> refreshAfterPull(PullReason reason) =>
      refresh('after pull ${reason.name}');

  Future<bool> refresh(String why) async {
    final session = ref.read(sessionProvider);
    if (session is! SessionActive) {
      _log.fine(
        'holiday settings refresh ($why) skipped: session is ${session.name}',
      );
      return false;
    }
    final userId = session.user.userId;
    final sw = Stopwatch()..start();
    _log.fine('holiday settings refresh ($why) → GET $mePath userId=$userId');
    final MeReply reply;
    try {
      reply = await ref.read(accountApiProvider).me();
    } on ApiException catch (e) {
      _log.warning(
        'holiday settings refresh ($why) failed after '
        '${sw.elapsedMilliseconds}ms userId=$userId: ${e.runtimeType}: '
        '${e.details} rid=${e.requestId ?? '-'} → keeping '
        '${_keptText()}, next try after the next pull',
      );
      return false;
    } catch (e, st) {
      _log.warning(
        'holiday settings refresh ($why) crashed after '
        '${sw.elapsedMilliseconds}ms userId=$userId: ${describeError(e)} → '
        'keeping ${_keptText()}, next try after the next pull',
        e,
        st,
      );
      return false;
    }
    if (!ref.mounted) {
      _log.fine(
        'holiday settings refresh ($why) answered rid=${reply.requestId} '
        'after the app scope is gone: ignored',
      );
      return false;
    }
    return apply(
      reply.user,
      source:
          'GET $mePath rid=${reply.requestId} '
          'in ${sw.elapsedMilliseconds}ms ($why)',
    );
  }

  Future<bool> apply(User user, {required String source}) async {
    final sessionUserId = ref.read(sessionProvider).userId;
    if (user.id != sessionUserId) {
      _log.warning(
        'holiday settings from $source ignored: answer is for '
        'userId=${user.id}, session userId=${sessionUserId ?? '-'}',
      );
      return false;
    }
    final next = CachedHolidaySettings(
      userId: user.id,
      settings: user.holidaySettings,
    );
    final previous = state;
    if (previous == next) {
      _log.fine('holiday settings unchanged from $source: $next');
      return true;
    }
    final sw = Stopwatch()..start();
    var cachedOnPhone = true;
    try {
      await ref
          .read(prefsRepositoryProvider)
          .setString(PrefKeys.holidaySettings, encodeHolidaySettings(next));
    } catch (e, st) {
      cachedOnPhone = false;
      final error = redactDbError(e);
      _log.warning(
        'holiday settings from $source not cached after '
        '${sw.elapsedMilliseconds}ms → applied until restart only: '
        '${describeError(error)}',
        error,
        st,
      );
    }
    if (!ref.mounted) {
      _log.fine(
        'holiday settings from $source saved after the app scope is gone: '
        'applies after restart',
      );
      return cachedOnPhone;
    }
    final now = ref.read(sessionProvider).userId;
    if (now != user.id) {
      _log.warning(
        'holiday settings from $source dropped: session user changed to '
        '${now ?? '-'} while saving',
      );
      return false;
    }
    state = next;
    _log.info(
      'holiday settings changed from $source: ${next.settings} '
      '(was ${previous?.settings ?? 'defaults'})'
      '${cachedOnPhone ? ' cached in ${sw.elapsedMilliseconds}ms' : ''}',
    );
    return true;
  }

  String _keptText() {
    final current = state;
    return current == null ? 'default settings' : 'cached ${current.settings}';
  }
}

final holidaySettingsProvider = Provider<HolidaySettings>((ref) {
  final userId = ref.watch(sessionProvider.select((s) => s.userId));
  final cached = ref.watch(accountHolidaySettingsProvider);
  if (cached == null || cached.userId != userId) {
    return const HolidaySettings();
  }
  return cached.settings;
}, name: 'holidaySettings');
