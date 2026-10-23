import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/api/api_exception.dart';
import 'package:milionchik/data/api/token_store.dart';
import 'package:milionchik/data/current_user.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:milionchik/data/session/session.dart';
import 'package:milionchik/data/session/session_providers.dart';
import 'package:milionchik/data/session/session_state.dart';
import 'package:milionchik/data/session/session_store.dart';

import '../provider_harness.dart';
import 'fake_secure_values.dart';

const _user = SessionUser(
  userId: 'user-server-41',
  login: 'kotik_login',
  displayName: 'Котик Тестовый',
);

const _session = Session(
  user: _user,
  tokens: AuthTokens(
    accessToken: 'ACCESS-zulu-yankee-xray-whiskey',
    refreshToken: 'REFRESH-victor-uniform-tango-sierra',
  ),
);

void main() {
  late FakeSecureValues values;
  late ProviderHarness h;

  setUp(() {
    values = FakeSecureValues();
    h = ProviderHarness(
      overrides: [secureValuesProvider.overrideWithValue(values)],
    );
  });

  test(
    'без сессии: состояние «нет», CurrentUser - прежний локальный id',
    () async {
      expect(h.read(sessionProvider), isA<SessionAbsent>());
      expect(h.read(currentUserProvider), isA<LocalPrefsCurrentUser>());

      final userId = await h.read(currentUserProvider).userId();
      expect(
        await h.read(prefsRepositoryProvider).getString(PrefKeys.localUserId),
        userId,
      );
      expect(userId, isNot(_user.userId));
    },
  );

  test('сохранение сессии: состояние «есть», хранилище заполнено, траты и '
      'бюджеты пишутся с userId из сессии', () async {
    await h.read(sessionProvider.notifier).save(_session);

    expect(h.read(sessionProvider), isA<SessionActive>());
    expect(h.read(sessionProvider).user, _user);
    expect(values.data.keys, {SessionStore.userKey, SessionStore.tokensKey});
    expect(h.read(currentUserProvider), isA<SessionCurrentUser>());
    expect(await h.read(currentUserProvider).userId(), _user.userId);

    final budget = await h
        .read(budgetsRepositoryProvider)
        .createLocalPersonal();
    expect(budget.ownerId, _user.userId);

    expect(h.lines('session', Level.INFO), [
      matches(RegExp(r'session saved userId=user-server-41 in \d+ms$')),
      endsWith('session state absent → active userId=user-server-41'),
      endsWith('current user from session userId=user-server-41'),
    ]);
  });

  test('очистка: состояние «нет», хранилище пустое, CurrentUser снова '
      'локальный', () async {
    final localId = await h.read(currentUserProvider).userId();
    await h.read(sessionProvider.notifier).save(_session);
    expect(await h.read(currentUserProvider).userId(), _user.userId);

    await h.read(sessionProvider.notifier).clear();

    expect(h.read(sessionProvider), isA<SessionAbsent>());
    expect(values.data, isEmpty);
    expect(h.read(currentUserProvider), isA<LocalPrefsCurrentUser>());
    expect(await h.read(currentUserProvider).userId(), localId);
    expect(
      h.lines('session', Level.INFO),
      contains(endsWith('session state active → absent')),
    );
  });

  test('сессия закончилась: состояние «истекла» с причиной, userId из '
      'сессии сохраняется, хранилище не трогается', () async {
    await h.read(sessionProvider.notifier).save(_session);

    h.read(sessionProvider.notifier).ended(SessionEndReason.refreshRejected);

    final state = h.read(sessionProvider);
    expect(state, isA<SessionEnded>());
    expect((state as SessionEnded).reason, SessionEndReason.refreshRejected);
    expect(state.user, _user);
    expect(await h.read(currentUserProvider).userId(), _user.userId);
    expect(values.data.keys, {SessionStore.userKey, SessionStore.tokensKey});
    expect(
      h.lines('session', Level.INFO),
      contains(
        endsWith(
          'session state active → ended reason=refreshRejected '
          'userId=user-server-41',
        ),
      ),
    );
  });

  test('конец сессии без сессии - состояние «нет» остаётся', () {
    h.read(sessionProvider.notifier).ended(SessionEndReason.sessionRejected);

    expect(h.read(sessionProvider), isA<SessionAbsent>());
  });

  test(
    'хранилище не записало сессию - состояние «нет», ошибка наружу',
    () async {
      values.failWriteOf = SessionStore.tokensKey;

      await expectLater(
        h.read(sessionProvider.notifier).save(_session),
        throwsA(isA<StateError>()),
      );

      expect(h.read(sessionProvider), isA<SessionAbsent>());
      expect(h.read(currentUserProvider), isA<LocalPrefsCurrentUser>());
      expect(
        h.lines('session', Level.WARNING),
        contains(contains('session save failed userId=user-server-41')),
      );
    },
  );

  test('логи сессии без токенов, логина и имени', () async {
    await h.read(sessionProvider.notifier).save(_session);
    h.read(sessionProvider.notifier).ended(SessionEndReason.sessionRejected);
    await h.read(sessionProvider.notifier).clear();

    final text = h.lines('session').join('\n');
    for (final secret in [
      _session.tokens.accessToken,
      _session.tokens.refreshToken,
      _user.login,
      _user.displayName,
    ]) {
      expect(text, isNot(contains(secret)), reason: secret);
    }
  });
}
