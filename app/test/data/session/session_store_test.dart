import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/api/token_store.dart';
import 'package:milionchik/data/session/secure_values.dart';
import 'package:milionchik/data/session/session.dart';
import 'package:milionchik/data/session/session_store.dart';

import '../api/fake_api_adapter.dart';
import 'fake_secure_values.dart';

const _access = 'ACCESS-alpha-bravo-charlie-delta';
const _refresh = 'REFRESH-echo-foxtrot-golf-hotel';
const _login = 'marusya_login';
const _name = 'Маруся Гостевая';

const _user = SessionUser(
  userId: 'user-7a1c',
  login: _login,
  displayName: _name,
);

const _session = Session(
  user: _user,
  tokens: AuthTokens(accessToken: _access, refreshToken: _refresh),
);

void main() {
  late LogCapture logs;
  late FakeSecureValues values;
  late SessionStore store;

  setUp(() {
    logs = LogCapture();
    values = FakeSecureValues();
    store = SessionStore(values);
  });

  tearDown(() => logs.dispose());

  void expectNoSecretsInLogs() {
    for (final secret in [_access, _refresh, _login, _name]) {
      expect(logs.text, isNot(contains(secret)), reason: secret);
    }
  }

  test('сохранить → прочитать: та же сессия, info «session saved» и '
      '«session restored» без значений', () async {
    await store.save(_session);
    final restored = await SessionStore(values).read();

    expect(restored, isNotNull);
    expect(restored!.user, _user);
    expect(restored.tokens.accessToken, _access);
    expect(restored.tokens.refreshToken, _refresh);
    expect(values.data.keys, {SessionStore.userKey, SessionStore.tokensKey});
    expect(logs.linesOf('session', Level.INFO), [
      matches(
        RegExp(r'INFO  \[session\] session saved userId=user-7a1c in \d+ms$'),
      ),
      matches(RegExp(r'INFO  \[session\] session restored in \d+ms$')),
    ]);
    expectNoSecretsInLogs();
  });

  test('пустое хранилище - сессии нет, info «no session stored»', () async {
    expect(await store.read(), isNull);
    expect(await store.readTokens(), isNull);
    expect(logs.linesOf('session', Level.INFO), [
      matches(
        RegExp(r'INFO  \[session\] no session stored \(read in \d+ms\)$'),
      ),
    ]);
  });

  test(
    'очистить - ключи удалены, сессии нет, info «session cleared»',
    () async {
      await store.save(_session);
      await store.clear();

      expect(values.data, isEmpty);
      expect(await store.read(), isNull);
      expect(await store.readTokens(), isNull);
      expect(
        logs.linesOf('session', Level.INFO),
        contains(
          matches(RegExp(r'INFO  \[session\] session cleared in \d+ms$')),
        ),
      );
      expectNoSecretsInLogs();
    },
  );

  test('TokenStore: новая пара после refresh сохраняется, пользователь '
      'остаётся прежним', () async {
    await store.save(_session);
    expect((await store.readTokens())!.accessToken, _access);

    const fresh = AuthTokens(
      accessToken: 'ACCESS-india-juliett-kilo-lima',
      refreshToken: 'REFRESH-mike-november-oscar-papa',
    );
    await store.saveTokens(fresh);

    final tokens = await store.readTokens();
    expect(tokens!.accessToken, fresh.accessToken);
    expect(tokens.refreshToken, fresh.refreshToken);
    final restored = await store.read();
    expect(restored!.user, _user);
    expect(restored.tokens.refreshToken, fresh.refreshToken);
    expect(
      logs.linesOf('session', Level.INFO),
      contains(
        matches(RegExp(r'INFO  \[session\] session tokens updated in \d+ms$')),
      ),
    );
    for (final secret in [fresh.accessToken, fresh.refreshToken]) {
      expect(logs.text, isNot(contains(secret)));
    }
    expectNoSecretsInLogs();
  });

  test(
    'через flutter_secure_storage: сохранить, прочитать, очистить',
    () async {
      final backing = <String, String>{};
      FlutterSecureStorage.setMockInitialValues(backing);
      final real = SessionStore(const FlutterSecureValues());

      await real.save(_session);
      expect(backing.keys, {SessionStore.userKey, SessionStore.tokensKey});
      final restored = await SessionStore(const FlutterSecureValues()).read();
      expect(restored!.user, _user);
      expect(restored.tokens.refreshToken, _refresh);

      await real.clear();
      expect(backing, isEmpty);
      expect(await real.read(), isNull);
    },
  );
}
