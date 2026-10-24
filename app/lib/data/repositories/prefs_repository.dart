import 'package:drift/drift.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../db/app_database.dart';
import '../db/redact_db_error.dart';

final _log = Logger('repo');

abstract final class PrefKeys {
  static const String localUserId = 'localUserId';
  static const String todayOverride = 'debugTodayOverride';
  static const String signedInBefore = 'signedInBefore';
  static const String themeMode = 'themeMode';
  static const String selectedBudgetId = 'selectedBudgetId';
  static const String holidaySettings = 'holidaySettings';

  static const Set<String> phoneSettings = {
    themeMode,
    signedInBefore,
    todayOverride,
  };
}

abstract interface class PrefsRepository {
  Future<String?> getString(String key);

  Future<int?> getInt(String key);

  Future<bool?> getBool(String key);

  Stream<String?> watchString(String key);

  Stream<int?> watchInt(String key);

  Stream<bool?> watchBool(String key);

  Future<void> setString(String key, String value);

  Future<void> setInt(String key, int value);

  Future<void> setBool(String key, bool value);

  Future<void> remove(String key);

  Future<String> putStringIfAbsent(String key, String Function() create);
}

final class DriftPrefsRepository implements PrefsRepository {
  DriftPrefsRepository(this._db);

  final AppDatabase _db;

  SimpleSelectStatement<$LocalPrefsTable, LocalPrefEntry> _byKey(String key) =>
      _db.select(_db.localPrefs)..where((p) => p.key.equals(key));

  Future<String?> _read(String key, String type) async {
    final sw = Stopwatch()..start();
    try {
      final row = await _byKey(key).getSingleOrNull();
      _log.fine(
        'pref get key=$key type=$type found=${row != null} '
        'in ${sw.elapsedMilliseconds}ms',
      );
      return row?.value;
    } catch (e, st) {
      final error = redactDbError(e);
      _log.severe(
        'pref get failed key=$key type=$type '
        'after ${sw.elapsedMilliseconds}ms: ${describeError(error)}',
        error,
        st,
      );
      rethrow;
    }
  }

  Stream<String?> _watch(String key, String type) =>
      _byKey(key)
          .watchSingleOrNull()
          .map((row) => row?.value)
          .handleError((Object e, StackTrace st) {
            final error = redactDbError(e);
            _log.severe(
              'pref watch failed key=$key type=$type: ${describeError(error)}',
              error,
              st,
            );
            Error.throwWithStackTrace(e, st);
          });

  Future<void> _write(String key, String type, String value) async {
    final sw = Stopwatch()..start();
    try {
      await _db
          .into(_db.localPrefs)
          .insertOnConflictUpdate(LocalPrefEntry(key: key, value: value));
      _log.fine(
        'pref set key=$key type=$type length=${value.length} '
        'in ${sw.elapsedMilliseconds}ms',
      );
    } catch (e, st) {
      final error = redactDbError(e);
      _log.severe(
        'pref set failed key=$key type=$type '
        'after ${sw.elapsedMilliseconds}ms: ${describeError(error)}',
        error,
        st,
      );
      rethrow;
    }
  }

  int? _parseInt(String key, String? value) {
    if (value == null) return null;
    final parsed = int.tryParse(value);
    if (parsed == null) {
      _log.warning(
        'pref has unexpected value key=$key expected=int '
        'length=${value.length} → treated as absent',
      );
    }
    return parsed;
  }

  bool? _parseBool(String key, String? value) {
    if (value == null) return null;
    if (value == 'true') return true;
    if (value == 'false') return false;
    _log.warning(
      'pref has unexpected value key=$key expected=bool '
      'length=${value.length} → treated as absent',
    );
    return null;
  }

  @override
  Future<String?> getString(String key) => _read(key, 'string');

  @override
  Future<int?> getInt(String key) async =>
      _parseInt(key, await _read(key, 'int'));

  @override
  Future<bool?> getBool(String key) async =>
      _parseBool(key, await _read(key, 'bool'));

  @override
  Stream<String?> watchString(String key) => _watch(key, 'string');

  @override
  Stream<int?> watchInt(String key) =>
      _watch(key, 'int').map((v) => _parseInt(key, v));

  @override
  Stream<bool?> watchBool(String key) =>
      _watch(key, 'bool').map((v) => _parseBool(key, v));

  @override
  Future<void> setString(String key, String value) =>
      _write(key, 'string', value);

  @override
  Future<void> setInt(String key, int value) => _write(key, 'int', '$value');

  @override
  Future<void> setBool(String key, bool value) => _write(key, 'bool', '$value');

  @override
  Future<void> remove(String key) async {
    final sw = Stopwatch()..start();
    try {
      final removed = await (_db.delete(
        _db.localPrefs,
      )..where((p) => p.key.equals(key))).go();
      _log.fine(
        'pref remove key=$key removed=$removed in ${sw.elapsedMilliseconds}ms',
      );
    } catch (e, st) {
      final error = redactDbError(e);
      _log.severe(
        'pref remove failed key=$key after ${sw.elapsedMilliseconds}ms: '
        '${describeError(error)}',
        error,
        st,
      );
      rethrow;
    }
  }

  @override
  Future<String> putStringIfAbsent(String key, String Function() create) async {
    final sw = Stopwatch()..start();
    try {
      return await _db.transaction(() async {
        final existing = await _byKey(key).getSingleOrNull();
        if (existing != null) {
          _log.fine('pref exists key=$key in ${sw.elapsedMilliseconds}ms');
          return existing.value;
        }
        final value = create();
        await _db
            .into(_db.localPrefs)
            .insert(LocalPrefEntry(key: key, value: value));
        _log.fine(
          'pref created key=$key length=${value.length} '
          'in ${sw.elapsedMilliseconds}ms',
        );
        return value;
      });
    } catch (e, st) {
      final error = redactDbError(e);
      _log.severe(
        'pref create failed key=$key after ${sw.elapsedMilliseconds}ms: '
        '${describeError(error)}',
        error,
        st,
      );
      rethrow;
    }
  }
}
