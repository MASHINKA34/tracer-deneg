import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/api/token_store.dart';
import 'package:milionchik/data/session/session.dart';
import 'package:milionchik/data/session/session_store.dart';

import '../api/fake_api_adapter.dart';
import 'fake_secure_values.dart';

const _access = 'ACCESS-quebec-romeo-sierra-tango';
const _refresh = 'REFRESH-uniform-victor-whiskey-xray';

const _session = Session(
  user: SessionUser(
    userId: 'user-9f2e',
    login: 'gostya_login',
    displayName: 'Гостья Тестовая',
  ),
  tokens: AuthTokens(accessToken: _access, refreshToken: _refresh),
);

final _restoreError = PlatformException(
  code: 'Exception encountered',
  message: 'read',
  details: 'javax.crypto.AEADBadTagException: Failed to unwrap key',
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

  List<String> warnings() => logs.linesOf('session', Level.WARNING);

  void expectNoSecretsInLogs() {
    for (final secret in [_access, _refresh, 'gostya_login', 'Гостья']) {
      expect(logs.text, isNot(contains(secret)), reason: secret);
    }
  }

  test('ошибка чтения хранилища (после восстановления из бэкапа) - сессии '
      'нет, warn с типом ошибки, без падения', () async {
    await store.save(_session);
    values.readError = _restoreError;

    expect(await store.read(), isNull);
    expect(await store.readTokens(), isNull);

    expect(warnings(), hasLength(2));
    expect(
      warnings()[0],
      contains('WARN  [session] session storage read failed after '),
    );
    expect(
      warnings()[0],
      contains('→ treated as no session: PlatformException'),
    );
    expect(warnings()[0], contains('AEADBadTagException'));
    expect(warnings()[0], contains('stack:'));
    expect(warnings()[1], contains('session tokens read failed after '));
    expect(warnings()[1], contains('PlatformException'));
    expectNoSecretsInLogs();
  });

  test('испорченное значение в хранилище - сессии нет, warn без '
      'содержимого значения', () async {
    values.data[SessionStore.userKey] =
        '{"userId":"user-9f2e","login":"gostya_login","displayName":"x"}';
    values.data[SessionStore.tokensKey] =
        '{"accessToken":"$_access","refreshToken":"$_refresh';

    expect(await store.read(), isNull);
    expect(await store.readTokens(), isNull);

    expect(warnings(), hasLength(2));
    expect(warnings()[0], contains('session storage unreadable after '));
    expect(warnings()[0], contains('FormatException'));
    expect(warnings()[0], contains('stored session tokens is not JSON'));
    expect(warnings()[1], contains('session tokens unreadable after '));
    expectNoSecretsInLogs();
  });

  test(
    'неполная сессия (токены без пользователя) - сессии нет, warn',
    () async {
      await store.save(_session);
      values.data.remove(SessionStore.userKey);

      expect(await store.read(), isNull);

      expect(warnings(), [
        matches(
          RegExp(
            r'WARN  \[session\] session incomplete in storage tokens=true '
            r'user=false → treated as no session \(read in \d+ms\)$',
          ),
        ),
      ]);
    },
  );

  test('сохранение упало на токенах - половина сессии удалена, ошибка '
      'наружу, warn с типом', () async {
    values.failWriteOf = SessionStore.tokensKey;
    values.writeError = PlatformException(code: 'write', message: 'disk full');

    await expectLater(store.save(_session), throwsA(isA<PlatformException>()));

    expect(values.data, isEmpty);
    expect(await store.read(), isNull);
    expect(
      warnings().first,
      contains('session save failed userId=user-9f2e after '),
    );
    expect(warnings().first, contains('PlatformException'));
    expect(
      logs.linesOf('session', Level.INFO),
      isNot(contains(contains('session saved'))),
    );
    expect(logs.text, contains('partial session removed userId=user-9f2e'));
    expectNoSecretsInLogs();
  });

  test(
    'сохранение токенов после refresh упало - ошибка наружу, warn',
    () async {
      await store.save(_session);
      values.failWriteOf = SessionStore.tokensKey;

      await expectLater(
        store.saveTokens(
          const AuthTokens(accessToken: 'a-new-token', refreshToken: 'r-new-1'),
        ),
        throwsA(isA<StateError>()),
      );
      expect(warnings().single, contains('session tokens save failed after '));
      expect(warnings().single, contains('StateError'));
      values.failWriteOf = null;
      expect((await store.readTokens())!.refreshToken, _refresh);
    },
  );

  test('очистка упала - ошибка наружу, warn с типом', () async {
    values.deleteError = PlatformException(code: 'delete', message: 'busy');

    await expectLater(store.clear(), throwsA(isA<PlatformException>()));
    expect(warnings().single, contains('session clear failed after '));
    expect(warnings().single, contains('PlatformException'));
  });
}
