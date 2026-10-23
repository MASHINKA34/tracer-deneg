import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../api/token_store.dart';
import 'secure_values.dart';
import 'session.dart';

final _log = Logger('session');

final class SessionStore implements TokenStore {
  SessionStore(this._values);

  static const String tokensKey = 'milionchik.session.tokens';
  static const String userKey = 'milionchik.session.user';

  final SecureValues _values;

  Future<Session?> read() async {
    final sw = Stopwatch()..start();
    final String? rawTokens;
    final String? rawUser;
    try {
      rawTokens = await _values.read(tokensKey);
      rawUser = await _values.read(userKey);
    } catch (e, st) {
      _log.warning(
        'session storage read failed after ${sw.elapsedMilliseconds}ms '
        '→ treated as no session: ${describeError(e)}',
        e,
        st,
      );
      return null;
    }
    if (rawTokens == null && rawUser == null) {
      _log.info('no session stored (read in ${sw.elapsedMilliseconds}ms)');
      return null;
    }
    if (rawTokens == null || rawUser == null) {
      _log.warning(
        'session incomplete in storage tokens=${rawTokens != null} '
        'user=${rawUser != null} → treated as no session '
        '(read in ${sw.elapsedMilliseconds}ms)',
      );
      return null;
    }
    final Session session;
    try {
      session = Session(
        user: _decodeUser(rawUser),
        tokens: _decodeTokens(rawTokens),
      );
    } on FormatException catch (e, st) {
      _log.warning(
        'session storage unreadable after ${sw.elapsedMilliseconds}ms '
        '→ treated as no session: ${describeError(e)}',
        e,
        st,
      );
      return null;
    }
    _log.info('session restored in ${sw.elapsedMilliseconds}ms');
    return session;
  }

  Future<void> save(Session session) async {
    final sw = Stopwatch()..start();
    final userId = session.user.userId;
    try {
      await _values.write(userKey, _encodeUser(session.user));
      await _values.write(tokensKey, _encodeTokens(session.tokens));
    } catch (e, st) {
      _log.warning(
        'session save failed userId=$userId after ${sw.elapsedMilliseconds}ms '
        '→ removing partial session: ${describeError(e)}',
        e,
        st,
      );
      await _removePartial(userId);
      rethrow;
    }
    _log.info('session saved userId=$userId in ${sw.elapsedMilliseconds}ms');
  }

  Future<void> clear() async {
    final sw = Stopwatch()..start();
    try {
      await _values.delete(tokensKey);
      await _values.delete(userKey);
    } catch (e, st) {
      _log.warning(
        'session clear failed after ${sw.elapsedMilliseconds}ms: '
        '${describeError(e)}',
        e,
        st,
      );
      rethrow;
    }
    _log.info('session cleared in ${sw.elapsedMilliseconds}ms');
  }

  @override
  Future<AuthTokens?> readTokens() async {
    final sw = Stopwatch()..start();
    final String? raw;
    try {
      raw = await _values.read(tokensKey);
    } catch (e, st) {
      _log.warning(
        'session tokens read failed after ${sw.elapsedMilliseconds}ms '
        '→ treated as no session: ${describeError(e)}',
        e,
        st,
      );
      return null;
    }
    if (raw == null) {
      _log.fine(
        'no session tokens stored (read in ${sw.elapsedMilliseconds}ms)',
      );
      return null;
    }
    try {
      final tokens = _decodeTokens(raw);
      _log.fine('session tokens read in ${sw.elapsedMilliseconds}ms');
      return tokens;
    } on FormatException catch (e, st) {
      _log.warning(
        'session tokens unreadable after ${sw.elapsedMilliseconds}ms '
        '→ treated as no session: ${describeError(e)}',
        e,
        st,
      );
      return null;
    }
  }

  @override
  Future<void> saveTokens(AuthTokens tokens) async {
    final sw = Stopwatch()..start();
    try {
      await _values.write(tokensKey, _encodeTokens(tokens));
    } catch (e, st) {
      _log.warning(
        'session tokens save failed after ${sw.elapsedMilliseconds}ms: '
        '${describeError(e)}',
        e,
        st,
      );
      rethrow;
    }
    _log.info('session tokens updated in ${sw.elapsedMilliseconds}ms');
  }

  Future<void> _removePartial(String userId) async {
    try {
      await _values.delete(tokensKey);
      await _values.delete(userKey);
      _log.info('partial session removed userId=$userId');
    } catch (e, st) {
      _log.warning(
        'partial session not removed userId=$userId: ${describeError(e)}',
        e,
        st,
      );
    }
  }
}

String _encodeTokens(AuthTokens tokens) => jsonEncode({
  'accessToken': tokens.accessToken,
  'refreshToken': tokens.refreshToken,
});

String _encodeUser(SessionUser user) => jsonEncode({
  'userId': user.userId,
  'login': user.login,
  'displayName': user.displayName,
});

AuthTokens _decodeTokens(String raw) {
  final reader = JsonReader.of(_decodeJson(raw, 'tokens'), 'SessionTokens');
  return AuthTokens(
    accessToken: _nonEmpty(reader, 'accessToken'),
    refreshToken: _nonEmpty(reader, 'refreshToken'),
  );
}

SessionUser _decodeUser(String raw) {
  final reader = JsonReader.of(_decodeJson(raw, 'user'), 'SessionUser');
  return SessionUser(
    userId: _nonEmpty(reader, 'userId'),
    login: reader.string('login'),
    displayName: reader.string('displayName'),
  );
}

Object? _decodeJson(String raw, String what) {
  try {
    return jsonDecode(raw);
  } on FormatException catch (e) {
    throw FormatException(
      'stored session $what is not JSON (${e.message} at offset '
      '${e.offset}, ${raw.length} chars)',
    );
  }
}

String _nonEmpty(JsonReader reader, String key) {
  final value = reader.string(key);
  if (value.isEmpty) {
    throw FormatException('${reader.type}.$key: expected non-empty string');
  }
  return value;
}
