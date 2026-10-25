import 'dart:async';
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
  const CachedHolidaySettings({
    required this.userId,
    required this.settings,
    this.otherDisabled = const {},
  });

  factory CachedHolidaySettings.fromUser(User user) => CachedHolidaySettings(
    userId: user.id,
    settings: user.holidaySettings,
    otherDisabled: {
      for (final key in user.holidaysDisabled)
        if (HolidayKey.fromKey(key) == null) key,
    },
  );

  final String? userId;
  final HolidaySettings settings;
  final Set<String> otherDisabled;

  List<String> get disabledKeys =>
      [for (final key in settings.disabled) key.key, ...otherDisabled]..sort();

  @override
  bool operator ==(Object other) =>
      other is CachedHolidaySettings &&
      other.userId == userId &&
      other.settings == settings &&
      other.otherDisabled.length == otherDisabled.length &&
      other.otherDisabled.containsAll(otherDisabled);

  @override
  int get hashCode =>
      Object.hash(userId, settings, Object.hashAllUnordered(otherDisabled));

  @override
  String toString() =>
      'userId=${userId ?? '-'} $settings'
      '${otherDisabled.isEmpty ? '' : ' otherDisabled=${otherDisabled.length}'}';
}

String encodeHolidaySettings(CachedHolidaySettings cached) {
  final settings = cached.settings;
  return jsonEncode({
    'userId': cached.userId,
    'enabled': settings.enabled,
    'disabled': cached.disabledKeys,
    'birthdayMonth': settings.birthday?.month,
    'birthdayDay': settings.birthday?.day,
  });
}

CachedHolidaySettings decodeHolidaySettings(String text) {
  final reader = JsonReader.of(jsonDecode(text), 'HolidaySettingsCache');
  final disabled = reader.strings('disabled');
  return CachedHolidaySettings(
    userId: reader.optString('userId'),
    settings: HolidaySettings(
      enabled: reader.boolean('enabled'),
      disabled: {for (final key in disabled) ?HolidayKey.fromKey(key)},
      birthday: MonthDay.fromParts(
        reader.optInteger('birthdayMonth'),
        reader.optInteger('birthdayDay'),
      ),
    ),
    otherDisabled: {
      for (final key in disabled)
        if (HolidayKey.fromKey(key) == null) key,
    },
  );
}

enum HolidaySettingsField {
  enabled('holidaysEnabled'),
  disabled('holidaysDisabled'),
  birthday('birthday');

  const HolidaySettingsField(this.key);

  final String key;
}

String encodeUnsentFields(Set<HolidaySettingsField> fields) => [
  for (final field in HolidaySettingsField.values)
    if (fields.contains(field)) field.key,
].join(',');

Set<HolidaySettingsField> decodeUnsentFields(String? text) {
  if (text == null || text.isEmpty) return const {};
  final parts = text.split(',');
  return {
    for (final field in HolidaySettingsField.values)
      if (parts.contains(field.key)) field,
  };
}

String _fieldsText(Set<HolidaySettingsField> fields) =>
    fields.isEmpty ? '-' : encodeUnsentFields(fields);

Map<String, Object?> holidaySettingsPatch(
  CachedHolidaySettings cached,
  Set<HolidaySettingsField> fields,
) {
  final settings = cached.settings;
  return {
    if (fields.contains(HolidaySettingsField.enabled))
      'holidaysEnabled': settings.enabled,
    if (fields.contains(HolidaySettingsField.disabled))
      'holidaysDisabled': cached.disabledKeys,
    if (fields.contains(HolidaySettingsField.birthday)) ...{
      'birthdayMonth': settings.birthday?.month,
      'birthdayDay': settings.birthday?.day,
    },
  };
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
  await _logUnsentAtStart(prefs);
  return cached;
}

Future<void> _logUnsentAtStart(PrefsRepository prefs) async {
  final sw = Stopwatch()..start();
  try {
    final unsent = decodeUnsentFields(
      await prefs.getString(PrefKeys.holidaySettingsUnsent),
    );
    if (unsent.isEmpty) return;
    _log.info(
      'holiday settings: changed on the phone and not sent yet '
      'fields=${_fieldsText(unsent)} (read in ${sw.elapsedMilliseconds}ms) '
      '→ PATCH /me after the startup sync',
    );
  } catch (e, st) {
    final error = redactDbError(e);
    _log.warning(
      'holiday settings unsent flag read failed after '
      '${sw.elapsedMilliseconds}ms → checked again before the next send: '
      '${describeError(error)}',
      error,
      st,
    );
  }
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

enum HolidaySendOutcome {
  sent,
  superseded,
  nothingUnsent,
  noSession,
  rejected,
  failed,
}

final class AccountHolidaySettings extends Notifier<CachedHolidaySettings?> {
  Future<HolidaySendOutcome>? _sending;
  bool _sendAgain = false;
  Future<void> _changes = Future<void>.value();

  Future<void> get sending => _sending ?? Future<void>.value();

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

  Future<bool> setEnabled(bool on) => _change(
    (_) => 'all holidays ${on ? 'on' : 'off'}',
    HolidaySettingsField.enabled,
    (s) => HolidaySettings(
      enabled: on,
      disabled: s.disabled,
      birthday: s.birthday,
    ),
  );

  Future<bool> setHoliday(HolidayKey key, bool on) => _change(
    (_) => '${key.name} ${on ? 'on' : 'off'}',
    HolidaySettingsField.disabled,
    (s) => HolidaySettings(
      enabled: s.enabled,
      disabled: on ? ({...s.disabled}..remove(key)) : {...s.disabled, key},
      birthday: s.birthday,
    ),
  );

  Future<bool> setBirthday(MonthDay? birthday) => _change(
    (s) => birthday == null
        ? 'birthday cleared'
        : s.birthday == null
        ? 'birthday set'
        : 'birthday changed',
    HolidaySettingsField.birthday,
    (s) => HolidaySettings(
      enabled: s.enabled,
      disabled: s.disabled,
      birthday: birthday,
    ),
  );

  Future<bool> _change(
    String Function(HolidaySettings current) describe,
    HolidaySettingsField field,
    HolidaySettings Function(HolidaySettings current) edit,
  ) {
    final run = _changes.then<bool>(
      (_) => ref.mounted
          ? _applyChange(describe, field, edit)
          : Future<bool>.value(false),
    );
    _changes = run.then<void>((_) {});
    return run;
  }

  Future<bool> _applyChange(
    String Function(HolidaySettings current) describe,
    HolidaySettingsField field,
    HolidaySettings Function(HolidaySettings current) edit,
  ) async {
    final userId = ref.read(sessionProvider).userId;
    final cachedNow = state;
    final current = cachedNow == null || cachedNow.userId != userId
        ? const HolidaySettings()
        : cachedNow.settings;
    final what = describe(current);
    final settings = edit(current);
    if (settings == current) {
      _log.fine('holiday settings change "$what": already so, nothing saved');
      return true;
    }
    final next = CachedHolidaySettings(
      userId: userId,
      settings: settings,
      otherDisabled: cachedNow != null && cachedNow.userId == userId
          ? cachedNow.otherDisabled
          : const {},
    );
    final sw = Stopwatch()..start();
    final Set<HolidaySettingsField> unsent;
    try {
      final prefs = ref.read(prefsRepositoryProvider);
      unsent = await ref.read(appDatabaseProvider).transaction(() async {
        await prefs.setString(
          PrefKeys.holidaySettings,
          encodeHolidaySettings(next),
        );
        if (userId == null) return const <HolidaySettingsField>{};
        final fields = {
          ...decodeUnsentFields(
            await prefs.getString(PrefKeys.holidaySettingsUnsent),
          ),
          field,
        };
        await prefs.setString(
          PrefKeys.holidaySettingsUnsent,
          encodeUnsentFields(fields),
        );
        return fields;
      });
    } catch (e, st) {
      final error = redactDbError(e);
      _log.warning(
        'holiday settings change "$what" not saved after '
        '${sw.elapsedMilliseconds}ms → keeping $current: '
        '${describeError(error)}',
        error,
        st,
      );
      return false;
    }
    if (!ref.mounted) {
      _log.warning(
        'holiday settings change "$what" saved, but the app scope is gone: '
        'applies and is sent after restart',
      );
      return true;
    }
    if (ref.read(sessionProvider).userId != userId) {
      _log.warning(
        'holiday settings change "$what" saved for userId=${userId ?? '-'}, '
        'but the session user changed while saving → not applied',
      );
      return false;
    }
    state = next;
    _log.info(
      'holiday settings changed on the phone: $what → $settings, saved in '
      '${sw.elapsedMilliseconds}ms'
      '${userId == null ? ', no session → stays on the phone' : ', unsent=${_fieldsText(unsent)} → PATCH $mePath'}',
    );
    if (userId != null) unawaited(_sendUnsent('changed on the phone'));
    return true;
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
    final unsent = await _readUnsent(why);
    if (unsent == null) return false;
    if (unsent.isNotEmpty) {
      _log.fine(
        'holiday settings refresh ($why): changed on the phone and not sent '
        'fields=${_fieldsText(unsent)} → PATCH $mePath instead of GET',
      );
      return await _sendUnsent(why) == HolidaySendOutcome.sent;
    }
    return _fetch(why, session.user.userId);
  }

  Future<bool> _fetch(String why, String userId) async {
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
    final next = CachedHolidaySettings.fromUser(user);
    final previous = state;
    if (previous == next) {
      _log.fine('holiday settings unchanged from $source: $next');
      return true;
    }
    final sw = Stopwatch()..start();
    var cachedOnPhone = true;
    var unsent = const <HolidaySettingsField>{};
    try {
      final prefs = ref.read(prefsRepositoryProvider);
      unsent = await ref.read(appDatabaseProvider).transaction(() async {
        final fields = decodeUnsentFields(
          await prefs.getString(PrefKeys.holidaySettingsUnsent),
        );
        if (fields.isEmpty) {
          await prefs.setString(
            PrefKeys.holidaySettings,
            encodeHolidaySettings(next),
          );
        }
        return fields;
      });
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
    if (unsent.isNotEmpty) {
      _log.info(
        'holiday settings from $source not applied: changed on the phone and '
        'not sent yet fields=${_fieldsText(unsent)} → PATCH $mePath goes first',
      );
      if (ref.mounted) unawaited(_sendUnsent('unsent change found after GET'));
      return false;
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
      'holiday settings ${previous == null ? 'received' : 'changed'} from '
      '$source: ${next.settings} (was '
      '${previous?.settings ?? 'not cached, defaults'})'
      '${cachedOnPhone ? ' cached in ${sw.elapsedMilliseconds}ms' : ''}',
    );
    return true;
  }

  Future<HolidaySendOutcome> _sendUnsent(String why) {
    final running = _sending;
    if (running != null) {
      _sendAgain = true;
      _log.fine(
        'holiday settings send ($why): PATCH $mePath already running → one '
        'more send with the latest settings after it',
      );
      return running;
    }
    final completer = Completer<HolidaySendOutcome>();
    _sending = completer.future;
    unawaited(_runSends(why, completer));
    return completer.future;
  }

  Future<void> _runSends(
    String why,
    Completer<HolidaySendOutcome> completer,
  ) async {
    var outcome = HolidaySendOutcome.failed;
    var round = 0;
    try {
      while (true) {
        _sendAgain = false;
        round++;
        outcome = await _sendOnce(round == 1 ? why : '$why, round $round');
        final again = _sendAgain || outcome == HolidaySendOutcome.superseded;
        if (!again || !ref.mounted) break;
      }
    } catch (e, st) {
      _log.severe(
        'holiday settings send ($why) crashed in round $round: '
        '${describeError(e)} → settings stay unsent, next try on start, '
        'network or after pull',
        e,
        st,
      );
      outcome = HolidaySendOutcome.failed;
    } finally {
      _sending = null;
      completer.complete(outcome);
    }
  }

  Future<Set<HolidaySettingsField>?> _readUnsent(String why) async {
    final sw = Stopwatch()..start();
    try {
      final text = await ref
          .read(prefsRepositoryProvider)
          .getString(PrefKeys.holidaySettingsUnsent);
      final fields = decodeUnsentFields(text);
      if (fields.isEmpty && text != null && text.isNotEmpty) {
        _log.warning(
          'holiday settings ($why): key=${PrefKeys.holidaySettingsUnsent} has '
          'unknown value length=${text.length} → treated as nothing unsent',
        );
      }
      return fields;
    } catch (e, st) {
      final error = redactDbError(e);
      _log.warning(
        'holiday settings ($why): unsent flag read failed after '
        '${sw.elapsedMilliseconds}ms → no GET or PATCH this time, next try '
        'after the next pull: ${describeError(error)}',
        error,
        st,
      );
      return null;
    }
  }

  Future<HolidaySendOutcome> _sendOnce(String why) async {
    final session = ref.read(sessionProvider);
    if (session is! SessionActive) {
      _log.info(
        'holiday settings send ($why) skipped: session is ${session.name} → '
        'settings stay unsent until sign-in',
      );
      return HolidaySendOutcome.noSession;
    }
    final userId = session.user.userId;
    final prefs = ref.read(prefsRepositoryProvider);
    final sw = Stopwatch()..start();
    final String? stored;
    final String? flag;
    try {
      stored = await prefs.getString(PrefKeys.holidaySettings);
      flag = await prefs.getString(PrefKeys.holidaySettingsUnsent);
    } catch (e, st) {
      final error = redactDbError(e);
      _log.warning(
        'holiday settings send ($why) not started: reading settings failed '
        'after ${sw.elapsedMilliseconds}ms → settings stay unsent: '
        '${describeError(error)}',
        error,
        st,
      );
      return HolidaySendOutcome.failed;
    }
    final fields = decodeUnsentFields(flag);
    if (fields.isEmpty) {
      _log.fine('holiday settings send ($why): nothing unsent');
      return HolidaySendOutcome.nothingUnsent;
    }
    final cached = _decodeForSend(stored, userId);
    if (cached == null) {
      await _dropUnsent(
        why,
        stored: stored,
        flag: flag,
        reason: 'no valid settings of userId=$userId on the phone',
      );
      return HolidaySendOutcome.nothingUnsent;
    }
    _log.fine(
      'holiday settings send ($why) → PATCH $mePath userId=$userId '
      'fields=${_fieldsText(fields)}',
    );
    final MeReply reply;
    try {
      reply = await ref
          .read(accountApiProvider)
          .updateMe(holidaySettingsPatch(cached, fields));
    } on ApiErrorResponse catch (e) {
      if (e.statusCode != 400) {
        _log.warning(
          'holiday settings send ($why) failed after '
          '${sw.elapsedMilliseconds}ms userId=$userId: ${e.runtimeType}: '
          '${e.details} rid=${e.requestId ?? '-'} → settings stay unsent, '
          'next try on start, network or after pull',
        );
        return HolidaySendOutcome.failed;
      }
      _log.warning(
        'holiday settings send ($why) rejected after '
        '${sw.elapsedMilliseconds}ms userId=$userId: ${e.details} '
        'rid=${e.requestId ?? '-'} → change on the phone dropped, server '
        'settings come with GET $mePath',
      );
      await _dropUnsent(
        why,
        stored: stored,
        flag: flag,
        reason: 'server rejected the change',
      );
      if (ref.mounted) await _fetch('after PATCH rejected', userId);
      return HolidaySendOutcome.rejected;
    } on ApiException catch (e) {
      _log.warning(
        'holiday settings send ($why) failed after '
        '${sw.elapsedMilliseconds}ms userId=$userId: ${e.runtimeType}: '
        '${e.details} rid=${e.requestId ?? '-'} → settings stay unsent, '
        'next try on start, network or after pull',
      );
      return HolidaySendOutcome.failed;
    } catch (e, st) {
      _log.warning(
        'holiday settings send ($why) crashed after '
        '${sw.elapsedMilliseconds}ms userId=$userId: ${describeError(e)} → '
        'settings stay unsent, next try on start, network or after pull',
        e,
        st,
      );
      return HolidaySendOutcome.failed;
    }
    if (reply.user.id != userId) {
      _log.warning(
        'holiday settings send ($why): PATCH $mePath rid=${reply.requestId} '
        'answered for userId=${reply.user.id}, sent for userId=$userId → '
        'answer ignored, settings stay unsent',
      );
      return HolidaySendOutcome.failed;
    }
    final next = CachedHolidaySettings.fromUser(reply.user);
    final bool committed;
    try {
      committed = await ref.read(appDatabaseProvider).transaction(() async {
        final storedNow = await prefs.getString(PrefKeys.holidaySettings);
        final flagNow = await prefs.getString(PrefKeys.holidaySettingsUnsent);
        if (storedNow != stored || flagNow != flag) return false;
        await prefs.setString(
          PrefKeys.holidaySettings,
          encodeHolidaySettings(next),
        );
        await prefs.remove(PrefKeys.holidaySettingsUnsent);
        return true;
      });
    } catch (e, st) {
      final error = redactDbError(e);
      _log.warning(
        'holiday settings sent ($why) rid=${reply.requestId}, but saving the '
        'answer failed after ${sw.elapsedMilliseconds}ms → settings stay '
        'unsent and go again: ${describeError(error)}',
        error,
        st,
      );
      return HolidaySendOutcome.failed;
    }
    if (!committed) {
      _log.fine(
        'holiday settings sent ($why) rid=${reply.requestId} in '
        '${sw.elapsedMilliseconds}ms, but they changed on the phone meanwhile '
        '→ answer not applied, sending the newer settings',
      );
      return HolidaySendOutcome.superseded;
    }
    final changedByServer = next.settings != cached.settings;
    if (ref.mounted && ref.read(sessionProvider).userId == userId) {
      state = next;
    }
    _log.info(
      'holiday settings sent ($why): PATCH $mePath rid=${reply.requestId} '
      'fields=${_fieldsText(fields)} in ${sw.elapsedMilliseconds}ms → '
      '${next.settings}'
      '${changedByServer ? ' (server answer differs from the phone, applied)' : ''}',
    );
    return HolidaySendOutcome.sent;
  }

  CachedHolidaySettings? _decodeForSend(String? stored, String userId) {
    if (stored == null) return null;
    try {
      final cached = decodeHolidaySettings(stored);
      return cached.userId == userId ? cached : null;
    } on FormatException catch (e) {
      _log.warning(
        'holiday settings cache not valid for sending '
        '(${withoutBirthdayValues(e.message)}) length=${stored.length}',
      );
      return null;
    }
  }

  Future<void> _dropUnsent(
    String why, {
    required String? stored,
    required String? flag,
    required String reason,
  }) async {
    final prefs = ref.read(prefsRepositoryProvider);
    try {
      final dropped = await ref.read(appDatabaseProvider).transaction(() async {
        final storedNow = await prefs.getString(PrefKeys.holidaySettings);
        final flagNow = await prefs.getString(PrefKeys.holidaySettingsUnsent);
        if (storedNow != stored || flagNow != flag) return false;
        await prefs.remove(PrefKeys.holidaySettingsUnsent);
        return true;
      });
      _log.warning(
        'holiday settings ($why): $reason → '
        '${dropped ? 'unsent flag dropped' : 'settings changed meanwhile, unsent flag kept'}',
      );
    } catch (e, st) {
      final error = redactDbError(e);
      _log.warning(
        'holiday settings ($why): $reason, but dropping the unsent flag '
        'failed: ${describeError(error)}',
        error,
        st,
      );
    }
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
