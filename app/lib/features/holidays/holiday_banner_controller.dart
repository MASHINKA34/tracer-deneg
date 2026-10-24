import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../core/clock.dart';
import '../../data/db/redact_db_error.dart';
import '../../data/providers.dart';
import '../../data/repositories/prefs_repository.dart';
import 'mood_controller.dart';

final _log = Logger('holidays');

Duration? _noRetry(int retryCount, Object error) => null;

String encodeHiddenHolidayBanners(Set<String> ids) =>
    jsonEncode([...ids]..sort());

Set<String> decodeHiddenHolidayBanners(String text) {
  final decoded = jsonDecode(text);
  if (decoded is! List) {
    throw FormatException('expected a list of ids, got ${decoded.runtimeType}');
  }
  return {
    for (final id in decoded)
      if (id is String)
        id
      else
        throw FormatException('expected string ids, got ${id.runtimeType}'),
  };
}

String _idsText(Set<String> ids) => '[${([...ids]..sort()).join(',')}]';

int? _yearOf(String id) {
  final colon = id.lastIndexOf(':');
  return colon < 0 ? null : int.tryParse(id.substring(colon + 1));
}

Set<String> keepCurrentHiddenBanners(Set<String> ids, LocalDate today) => {
  for (final id in ids)
    if ((_yearOf(id) ?? 0) >= today.year) id,
};

Future<Set<String>> loadHiddenHolidayBanners(PrefsRepository prefs) async {
  final sw = Stopwatch()..start();
  const key = PrefKeys.hiddenHolidayBanners;
  final String? stored;
  try {
    stored = await prefs.getString(key);
  } catch (e, st) {
    final error = redactDbError(e);
    _log.warning(
      'hidden holiday banners read failed after ${sw.elapsedMilliseconds}ms '
      '→ every banner shown until the next close tap: ${describeError(error)}',
      error,
      st,
    );
    return const {};
  }
  if (stored == null) {
    _log.info(
      'hidden holiday banners: none closed yet (key=$key) '
      'in ${sw.elapsedMilliseconds}ms',
    );
    return const {};
  }
  final Set<String> ids;
  try {
    ids = decodeHiddenHolidayBanners(stored);
  } on FormatException catch (e) {
    _log.warning(
      'hidden holiday banners ignored: key=$key is not valid (${e.message}) '
      'length=${stored.length} → every banner shown until the next close tap',
    );
    return const {};
  }
  _log.info(
    'hidden holiday banners ${_idsText(ids)} from key=$key '
    'in ${sw.elapsedMilliseconds}ms',
  );
  return ids;
}

final startupHiddenHolidayBannersProvider = Provider<Set<String>>(
  (ref) => const {},
  name: 'startupHiddenHolidayBanners',
);

final _storedHiddenBannersProvider = StreamProvider<String?>(
  (ref) => ref
      .watch(prefsRepositoryProvider)
      .watchString(PrefKeys.hiddenHolidayBanners),
  name: 'storedHiddenHolidayBanners',
  retry: _noRetry,
);

final hiddenHolidayBannersProvider =
    NotifierProvider<HiddenHolidayBanners, Set<String>>(
      HiddenHolidayBanners.new,
      name: 'hiddenHolidayBanners',
    );

final class HiddenHolidayBanners extends Notifier<Set<String>> {
  int _saving = 0;

  @override
  Set<String> build() {
    ref.listen<AsyncValue<String?>>(_storedHiddenBannersProvider, _stored);
    return ref.read(startupHiddenHolidayBannersProvider);
  }

  void _stored(AsyncValue<String?>? previous, AsyncValue<String?> next) {
    switch (next) {
      case AsyncData(:final value) when _saving > 0:
        _log.fine(
          'hidden holiday banners on the phone read while saving '
          '(length=${value?.length ?? 0}): ignored, keeping ${_idsText(state)}',
        );
      case AsyncData(:final value):
        final Set<String> ids;
        try {
          ids = value == null ? const {} : decodeHiddenHolidayBanners(value);
        } on FormatException catch (e) {
          _log.warning(
            'hidden holiday banners on the phone are not valid '
            '(${e.message}) length=${value?.length ?? 0} → keeping '
            '${_idsText(state)}',
          );
          return;
        }
        if (_same(ids, state)) return;
        _log.info(
          'hidden holiday banners changed on the phone: ${_idsText(state)} → '
          '${_idsText(ids)}${value == null ? ' (key removed)' : ''}',
        );
        state = ids;
      case AsyncError(:final error):
        _log.warning(
          'hidden holiday banners watch failed: ${error.runtimeType} → '
          'keeping ${_idsText(state)}',
        );
      default:
    }
  }

  bool _same(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  Future<bool> hide(HolidayPhase phase) async {
    final id = phase.occurrence.id;
    final previous = state;
    if (previous.contains(id)) {
      _log.fine('holiday banner close tap id=$id: already hidden');
      return true;
    }
    final today = ref.read(clockProvider).today();
    final next = {...keepCurrentHiddenBanners(previous, today), id};
    state = next;
    final dropped = previous.difference(next);
    final sw = Stopwatch()..start();
    const key = PrefKeys.hiddenHolidayBanners;
    _saving++;
    try {
      await ref
          .read(prefsRepositoryProvider)
          .setString(key, encodeHiddenHolidayBanners(next));
    } catch (e, st) {
      final error = redactDbError(e);
      _log.warning(
        'holiday banner hidden id=$id for this run only: saving key=$key '
        'failed after ${sw.elapsedMilliseconds}ms → shown again after '
        'restart: ${describeError(error)}',
        error,
        st,
      );
      return false;
    } finally {
      _saving--;
    }
    _log.info(
      'holiday banner hidden id=$id holiday=${phase.key.name} '
      'stage=${phase.stage.name} → until the next holiday; saved key=$key '
      'ids=${_idsText(next)}'
      '${dropped.isEmpty ? '' : ' dropped past=${_idsText(dropped)}'} '
      'in ${sw.elapsedMilliseconds}ms',
    );
    return true;
  }
}

final holidayBannerProvider = Provider<HolidayPhase?>((ref) {
  final phase = ref.watch(moodControllerProvider.select((m) => m.holiday));
  if (phase == null) return null;
  final id = phase.occurrence.id;
  if (ref.watch(hiddenHolidayBannersProvider).contains(id)) {
    _log.fine(
      'holiday banner id=$id holiday=${phase.key.name} not shown: closed '
      'earlier on this phone',
    );
    return null;
  }
  return phase;
}, name: 'holidayBanner');
