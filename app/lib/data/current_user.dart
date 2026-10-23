import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import 'db/redact_db_error.dart';
import 'repositories/prefs_repository.dart';

final _log = Logger('repo');

abstract interface class CurrentUser {
  Future<String> userId();
}

final class SessionCurrentUser implements CurrentUser {
  const SessionCurrentUser(this.id);

  final String id;

  @override
  Future<String> userId() async => id;

  @override
  String toString() => 'SessionCurrentUser(userId=$id)';
}

final class LocalPrefsCurrentUser implements CurrentUser {
  LocalPrefsCurrentUser(this._prefs, {String Function()? newId})
    : _newId = newId ?? _defaultNewId;

  static String _defaultNewId() => newId();

  final PrefsRepository _prefs;
  final String Function() _newId;
  Future<String>? _userId;

  @override
  Future<String> userId() => _userId ??= _load();

  Future<String> _load() async {
    final sw = Stopwatch()..start();
    try {
      var created = false;
      final id = await _prefs.putStringIfAbsent(PrefKeys.localUserId, () {
        created = true;
        return _newId();
      });
      if (created) {
        _log.info(
          'local user id created userId=$id key=${PrefKeys.localUserId} '
          'in ${sw.elapsedMilliseconds}ms',
        );
      } else {
        _log.fine(
          'local user id loaded userId=$id in ${sw.elapsedMilliseconds}ms',
        );
      }
      return id;
    } catch (e, st) {
      _userId = null;
      final error = redactDbError(e);
      _log.severe(
        'local user id load failed key=${PrefKeys.localUserId} '
        'after ${sw.elapsedMilliseconds}ms: ${describeError(error)}',
        error,
        st,
      );
      rethrow;
    }
  }
}
