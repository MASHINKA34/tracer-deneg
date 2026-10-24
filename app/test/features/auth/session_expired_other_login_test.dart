import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/repositories/account_data_cleaner.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:milionchik/data/session/session_providers.dart';
import 'package:milionchik/data/session/session_state.dart';
import 'package:milionchik/features/auth/login_screen.dart';
import 'package:milionchik/features/auth/recovery_code_screen.dart';
import 'package:milionchik/features/month/month_screen.dart';
import 'package:milionchik/ui/components/dialog.dart';

import '../profile/profile_fixture.dart';
import '../profile/profile_harness.dart';
import 'session_expired_fixture.dart';

const _title = 'Войти в другой аккаунт?';

const _warning =
    'Несохранённые траты прошлого аккаунта (3) будут удалены. Чтобы их '
    'сохранить, войди прежним логином.';

const _cleared = {'budgets': 1, 'categories': 0, 'expenses': 0, 'outbox': 0};

void _expectNoSecrets(ProfileHarness h) {
  final text = h.logs.text;
  for (final secret in [
    userPassword,
    wrongPassword,
    otherAccess,
    sameAccess,
    newRefresh,
    ProfileHarness.tokens.accessToken,
    ProfileHarness.tokens.refreshToken,
    otherLogin,
    profileUser.login,
  ]) {
    expect(text, isNot(contains(secret)), reason: secret);
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testUnmounting('другой логин: диалог с числом из очереди, «Отмена» → '
      'запроса входа нет, ничего не стёрто', (tester) async {
    final server = ExpiredSessionServer();
    final h = await startSignedIn(tester, server);
    final before = await tableCounts(tester, h.db);
    await expireOnMonth(h);

    await submitLogin(h, login: otherLogin);

    expect(find.byType(AppDialog), findsOneWidget);
    expect(find.text(_title), findsOneWidget);
    expect(find.text(_warning), findsOneWidget);
    expect(dialogButton('Удалить и войти'), findsOneWidget);

    await h.tap(dialogButton('Отмена'));

    expect(find.byType(AppDialog), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Сессия закончилась, войди снова'), findsOneWidget);
    expect(h.adapter.callsTo('/auth/login'), isEmpty);
    expect(h.container.read(sessionProvider), isA<SessionEnded>());
    expect(await tableCounts(tester, h.db), before);
    expect(
      h.linesOf('auth', Level.INFO),
      containsAll([
        matches(
          r'login after session end with another login=bo\*\*\* '
          r'previousUserId=user-server-77 previousLogin=an\*\*\* queue=3 → '
          r'warning dialog before clearing previous account data '
          r'\(counted in \d+ms\)$',
        ),
        endsWith(
          'login: previous account dialog choice=cancel queue=3 → not '
          'signing in, nothing cleared',
        ),
      ]),
    );
    _expectNoSecrets(h);
    expect(tester.takeException(), isNull);
  });

  testUnmounting('другой логин: «Удалить и войти» → вход, данные прошлого '
      'аккаунта стёрты как при выходе, первая загрузка с нуля', (tester) async {
    final server = ExpiredSessionServer();
    final h = await startSignedIn(tester, server);
    await tester.runAsync(() async {
      final prefs = DriftPrefsRepository(h.db);
      await prefs.setString(PrefKeys.themeMode, 'dark');
      await prefs.setString(PrefKeys.localUserId, 'u-1');
    });
    await expireOnMonth(h);

    await submitLogin(h, login: otherLogin);
    await h.tap(dialogButton('Удалить и войти'));
    await h.settle();

    expect(find.byType(AppDialog), findsNothing);
    expect(find.byType(MonthScreen), findsOneWidget);
    final prefs = (await tester.runAsync(
      () => h.db.select(h.db.localPrefs).get(),
    ))!;
    expect({for (final p in prefs) p.key: p.value}, {
      PrefKeys.themeMode: 'dark',
      PrefKeys.signedInBefore: 'true',
    });
    expect(server.order, [
      'POST /api/v1/sync/push',
      'POST /api/v1/auth/refresh',
      'POST /api/v1/auth/login',
      'GET /api/v1/sync/pull',
      'GET /api/v1/me',
    ]);
    expect(server.pulls[otherAccess], [0]);
    final state = h.container.read(sessionProvider);
    expect(state, isA<SessionActive>());
    expect(state.userId, otherUserId);
    expect(await tableCounts(tester, h.db), _cleared);
    expect(await syncCursor(tester, h.db), 7);

    expect(
      h.linesOf('auth', Level.INFO),
      containsAll([
        endsWith(
          'login: previous account dialog choice=delete queue=3 → signing '
          'in, previous account data cleared once the server accepts',
        ),
        endsWith(
          'login: another account userId=user-server-88, previous '
          'userId=user-server-77 → clearing previous account data like '
          'sign-out',
        ),
        matches(
          r'login: previous account userId=user-server-77 cleared queue=3 '
          r'rows=\d+ account prefs \[localUserId\] in \d+ms → signing in '
          r'userId=user-server-88, first load follows$',
        ),
      ]),
    );
    expect(
      h.linesOf('repo', Level.INFO),
      contains(contains('account data cleared reason=account-switch')),
    );
    _expectNoSecrets(h);
    expect(tester.takeException(), isNull);
  });

  testUnmounting('другой логин с неверным паролем после согласия: ошибка под '
      'полем, данные прошлого аккаунта не стёрты', (tester) async {
    final server = ExpiredSessionServer();
    final h = await startSignedIn(tester, server);
    final before = await tableCounts(tester, h.db);
    await expireOnMonth(h);

    await submitLogin(h, login: otherLogin, password: wrongPassword);
    await h.tap(dialogButton('Удалить и войти'));
    await h.settle();

    expect(h.adapter.callsTo('/auth/login'), hasLength(1));
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(h.errorUnder('Пароль'), 'Неверный логин или пароль');
    expect(h.container.read(sessionProvider), isA<SessionEnded>());
    expect(await tableCounts(tester, h.db), before);
    expect(
      h.linesOf('repo'),
      isNot(contains(contains('account data cleared'))),
    );
    _expectNoSecrets(h);
    expect(tester.takeException(), isNull);
  });

  testUnmounting('другой логин при пустой очереди: без диалога, данные '
      'прошлого аккаунта стёрты после входа', (tester) async {
    final server = ExpiredSessionServer();
    final h = await startSignedIn(tester, server, unsynced: 0);
    await expireOnMonth(h);

    await submitLogin(h, login: otherLogin);

    expect(find.byType(AppDialog), findsNothing);
    expect(find.byType(MonthScreen), findsOneWidget);
    expect(h.container.read(sessionProvider).userId, otherUserId);
    expect(await tableCounts(tester, h.db), _cleared);
    expect(
      h.linesOf('auth', Level.INFO),
      contains(
        matches(
          r'login after session end with another login=bo\*\*\* '
          r'previousUserId=user-server-77 previousLogin=an\*\*\* queue=0 → '
          r'nothing unsynced, no dialog, previous account data cleared once '
          r'the server accepts \(counted in \d+ms\)$',
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testUnmounting('регистрация нового аккаунта после истёкшей сессии — тоже '
      'другой аккаунт: диалог, согласие, данные стёрты, экран кода', (
    tester,
  ) async {
    final server = ExpiredSessionServer();
    final h = await startSignedIn(tester, server);
    await expireOnMonth(h);

    await h.tap(find.text('Зарегистрироваться'));
    await h.enter('Как тебя зовут', 'Борис');
    await h.enter('Логин', otherLogin);
    await h.enter('Пароль', userPassword);
    await h.enter('Повтори пароль', userPassword);
    await h.tap(authButton('Создать аккаунт'));

    expect(find.text(_title), findsOneWidget);
    expect(find.text(_warning), findsOneWidget);
    expect(h.adapter.callsTo('/auth/register'), isEmpty);

    await h.tap(dialogButton('Удалить и войти'));
    await h.settle();

    expect(h.adapter.callsTo('/auth/register'), hasLength(1));
    expect(find.byType(RecoveryCodeScreen), findsOneWidget);
    expect(h.container.read(sessionProvider).userId, otherUserId);
    final counts = await tableCounts(tester, h.db);
    expect(counts['expenses'], 0);
    expect(counts['outbox'], 0);
    expect(
      h.linesOf('auth', Level.INFO),
      contains(
        matches(
          r'register after session end with a new account login=bo\*\*\* '
          r'previousUserId=user-server-77 previousLogin=an\*\*\* queue=3 → '
          r'warning dialog before clearing previous account data '
          r'\(counted in \d+ms\)$',
        ),
      ),
    );
    _expectNoSecrets(h);
    expect(tester.takeException(), isNull);
  });

  testUnmounting('сбой очистки при входе другим логином: вход не выполнен, '
      'снекбар, данные и очередь прошлого аккаунта на месте', (tester) async {
    final server = ExpiredSessionServer();
    final h = await startSignedIn(
      tester,
      server,
      overrides: [
        accountDataCleanerProvider.overrideWithValue(const _BrokenCleaner()),
      ],
    );
    final before = await tableCounts(tester, h.db);
    await expireOnMonth(h);

    await submitLogin(h, login: otherLogin);
    await h.tap(dialogButton('Удалить и войти'));
    await h.settle();

    expect(h.adapter.callsTo('/auth/login'), hasLength(1));
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(
      find.text('Не получилось сохранить вход на телефоне. Попробуй ещё раз'),
      findsOneWidget,
    );
    final state = h.container.read(sessionProvider);
    expect(state, isA<SessionEnded>());
    expect(state.userId, profileUserId);
    expect(await tableCounts(tester, h.db), before);
    expect(
      h.linesOf('auth', Level.SEVERE),
      contains(
        matches(
          r'login accepted by server userId=user-server-88 login=bo\*\*\* '
          r'rid=\w+, but previous account data not cleared after \d+ms → not '
          r'signed in, staying on the login screen, previous account data '
          r'and queue kept: StateError: Bad state: disk-full-sierra\n',
        ),
      ),
    );
    _expectNoSecrets(h);
    expect(tester.takeException(), isNull);
  });
}

final class _BrokenCleaner implements AccountDataCleaner {
  const _BrokenCleaner();

  @override
  Future<AccountDataRemoval> clearAccountData(String reason) async =>
      throw StateError('disk-full-sierra');
}
