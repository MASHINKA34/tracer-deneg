import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/auth_gate.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/repositories/account_data_cleaner.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:milionchik/data/session/session_providers.dart';
import 'package:milionchik/data/session/session_state.dart';
import 'package:milionchik/features/auth/login_screen.dart';
import 'package:milionchik/features/auth/sign_in_notice.dart';
import 'package:milionchik/features/profile/delete_account_screen.dart';
import 'package:milionchik/features/profile/profile_screen.dart';
import 'package:milionchik/ui/components/button.dart';
import 'package:milionchik/ui/components/snackbar.dart';

import '../../data/api/fake_api_adapter.dart';
import '../auth/session_expired_fixture.dart' show testUnmounting;
import 'profile_harness.dart';
import 'sign_out_fixture.dart';

const String _password = 'parol-kilo-lima-mike';

const String _label = 'Введи пароль, чтобы подтвердить';

const List<String> _tables = [
  'budgets',
  'budget_members',
  'member_profiles',
  'categories',
  'expenses',
  'recurring_rules',
  'outbox',
];

final class _Server {
  _Server(this.reply);

  final FakeReply Function(FakeCall call) reply;
  final List<String> order = [];

  FakeReply handle(FakeCall call) {
    order.add('${call.method} ${call.path}');
    if (call.method == 'DELETE' && call.path.endsWith('/account')) {
      return reply(call);
    }
    throw StateError('unexpected ${call.method} ${call.path}');
  }
}

FakeReply _deleted(FakeCall call) => const FakeReply(204);

Never _offline(FakeCall call) =>
    throw const SocketException('Network is unreachable');

final class _BrokenCleaner implements AccountDataCleaner {
  @override
  Future<AccountDataRemoval> clearAccountData(String reason) =>
      Future.error(StateError('disk I/O error while clearing'));
}

Finder _button(String label) => find.widgetWithText(AppButton, label);

Finder _snackbar(String text) =>
    find.descendant(of: find.byType(AppSnackbar), matching: find.text(text));

Future<ProfileHarness> _open(
  WidgetTester tester, {
  required _Server server,
  bool signInRequired = true,
  bool brokenCleaner = false,
}) async {
  final h = await ProfileHarness.start(
    tester,
    server: server.handle,
    sessionEvents: true,
    overrides: [
      if (signInRequired) signInRequiredProvider.overrideWithValue(true),
      if (brokenCleaner)
        accountDataCleanerProvider.overrideWithValue(_BrokenCleaner()),
    ],
  );
  await tester.runAsync(() async {
    await DriftPrefsRepository(h.db).setString(PrefKeys.themeMode, 'dark');
    await DriftPrefsRepository(h.db).setString(PrefKeys.localUserId, 'u-1');
    await addUnsyncedExpenses(h.db, 2);
  });
  await h.openProfile();
  await h.tap(h.row('Удалить аккаунт'));
  expect(find.byType(DeleteAccountScreen), findsOneWidget);
  return h;
}

Future<void> _submit(ProfileHarness h, [String password = _password]) async {
  await h.enter(_label, password);
  await h.tap(_button('Удалить навсегда'));
}

Future<Map<String, int>> _counts(ProfileHarness h) async =>
    (await h.tester.runAsync(
      () async => {
        for (final table in _tables) table: await rowsIn(h.db, table),
        'stored session': await h.container
            .read(sessionStoreProvider)
            .read()
            .then((s) => s == null ? 0 : 1),
      },
    ))!;

Future<void> _expectNothingDeleted(ProfileHarness h) async {
  final counts = await _counts(h);
  expect(counts['stored session'], 1);
  expect(counts['outbox'], 2);
  expect(counts['expenses'], 2);
  expect(counts['budgets'], 2);
  expect(h.container.read(sessionProvider), isA<SessionActive>());
  expect(h.container.read(signInNoticeProvider), isNull);
}

Future<void> _expectDeletedAndSignedOut(ProfileHarness h) async {
  expect(find.byType(LoginScreen), findsOneWidget);
  expect(find.byType(DeleteAccountScreen), findsNothing);
  expect(find.byType(ProfileScreen), findsNothing);
  expect(_snackbar('Аккаунт удалён'), findsOneWidget);
  expect(h.container.read(sessionProvider), isA<SessionAbsent>());
  expect(h.container.read(signInNoticeProvider), isNull);
  final counts = await _counts(h);
  expect(counts.values.toSet(), {0}, reason: '$counts');
  final prefs = (await h.tester.runAsync(
    () => h.db.select(h.db.localPrefs).get(),
  ))!;
  expect({for (final p in prefs) p.key: p.value}, {PrefKeys.themeMode: 'dark'});
}

Future<void> _waitSnackbarOut(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 6));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testUnmounting('«Удалить навсегда» с верным паролем: DELETE /account, '
      'данные и сессия стёрты, экран входа со снекбаром «Аккаунт удалён»', (
    tester,
  ) async {
    final server = _Server(_deleted);
    final h = await _open(tester, server: server);

    await _submit(h);

    expect(server.order, ['DELETE /api/v1/account']);
    final call = h.adapter.callsTo('/account').single;
    expect(call.json, {'password': _password});
    expect(
      call.header('Authorization'),
      'Bearer ${ProfileHarness.tokens.accessToken}',
    );
    await _expectDeletedAndSignedOut(h);
    expect(find.text('Войди — и траты подтянутся на этот телефон'), findsOne);

    final auth = h.linesOf('auth', Level.INFO);
    expect(
      auth,
      contains(
        endsWith(
          'account delete started userId=user-server-77 queue=2 → '
          'DELETE /account',
        ),
      ),
    );
    expect(
      auth,
      contains(
        matches(
          r'account deleted on server userId=user-server-77 '
          r'rid=ridprofile000001 in \d+ms → clearing phone data$',
        ),
      ),
    );
    expect(
      auth,
      contains(
        matches(
          r'account delete done userId=user-server-77 rid=ridprofile000001 '
          r'queue=2 cleared: \d+ rows, tokens, account prefs \[localUserId\] '
          r'in \d+ms → sign-in screen with "account deleted" snackbar$',
        ),
      ),
    );
    expect(
      auth,
      contains(
        endsWith(
          'login screen after account deletion → "account deleted" snackbar',
        ),
      ),
    );
    expect(h.logs.text, isNot(contains(_password)));
    await _waitSnackbarOut(tester);
  });

  testUnmounting('без обязательного входа экран сам ведёт на вход со '
      'снекбаром', (tester) async {
    final server = _Server(_deleted);
    final h = await _open(tester, server: server, signInRequired: false);

    await _submit(h);

    expect(server.order, ['DELETE /api/v1/account']);
    await _expectDeletedAndSignedOut(h);
    expect(
      h.linesOf('nav'),
      contains(
        endsWith(
          'delete account done, sign-in not forced by the gate → /auth/login',
        ),
      ),
    );
    await _waitSnackbarOut(tester);
  });

  testUnmounting('неверный пароль: «Неверный пароль» под полем, ничего не '
      'удалено, warn в логе; правка пароля убирает ошибку', (tester) async {
    final server = _Server(
      (call) => FakeReply.error(401, 'bad_credentials', 'Неверный пароль'),
    );
    final h = await _open(tester, server: server);

    await _submit(h, 'parol-wrong-november');

    expect(server.order, ['DELETE /api/v1/account']);
    expect(find.byType(DeleteAccountScreen), findsOneWidget);
    expect(h.errorUnder(_label), 'Неверный пароль');
    expect(find.byType(AppSnackbar), findsNothing);
    await _expectNothingDeleted(h);
    expect(
      h.linesOf('auth', Level.WARNING),
      contains(
        matches(
          r'account delete rejected: wrong password code=bad_credentials '
          r'status=401 userId=user-server-77 rid=ridprofile000001 in \d+ms → '
          r'error under the field, nothing deleted$',
        ),
      ),
    );
    expect(h.logs.text, isNot(contains('parol-wrong-november')));

    await h.enter(_label, _password);

    expect(h.errorUnder(_label), isNull);
    expect(
      tester.widget<AppButton>(_button('Удалить навсегда')).onPressed,
      isNotNull,
    );
  });

  testUnmounting('без сети: снекбар «Нет связи…», остаёмся на экране, '
      'ничего не удалено', (tester) async {
    final server = _Server(_offline);
    final h = await _open(tester, server: server);

    await _submit(h);

    expect(server.order, ['DELETE /api/v1/account']);
    expect(find.byType(DeleteAccountScreen), findsOneWidget);
    expect(
      _snackbar('Нет связи с сервером. Проверь интернет и попробуй ещё раз'),
      findsOneWidget,
    );
    expect(h.errorUnder(_label), isNull);
    await _expectNothingDeleted(h);
    expect(
      h.linesOf('auth', Level.WARNING),
      contains(
        matches(
          r'account delete failed ApiNetworkFailure: connection .* '
          r'userId=user-server-77 rid=ridprofile000001 in \d+ms → snackbar, '
          r'nothing deleted\n',
        ),
      ),
    );
    expect(h.logs.text, isNot(contains(_password)));
    expect(
      tester.widget<AppButton>(_button('Удалить навсегда')).onPressed,
      isNotNull,
    );
    await _waitSnackbarOut(tester);
  });

  testUnmounting('ошибка сервера 500: снекбар, ничего не удалено', (
    tester,
  ) async {
    final server = _Server((call) => FakeReply.error(500, 'internal'));
    final h = await _open(tester, server: server);

    await _submit(h);

    expect(find.byType(DeleteAccountScreen), findsOneWidget);
    expect(
      _snackbar('На сервере что-то сломалось. Попробуй позже'),
      findsOneWidget,
    );
    await _expectNothingDeleted(h);
    expect(
      h.linesOf('auth', Level.WARNING),
      contains(contains('account delete failed ApiServerFailure: 500')),
    );
    await _waitSnackbarOut(tester);
  });

  testUnmounting('сервер удалил, а телефон не смог стереть данные: сессия '
      'закончилась, вход с текстом и снекбаром, данные ждут следующего '
      'входа', (tester) async {
    final server = _Server(_deleted);
    final h = await _open(tester, server: server, brokenCleaner: true);

    await _submit(h);

    expect(server.order, ['DELETE /api/v1/account']);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Сессия закончилась, войди снова'), findsOneWidget);
    expect(_snackbar('Аккаунт удалён'), findsOneWidget);
    expect(h.container.read(sessionProvider), isA<SessionEnded>());
    final counts = await _counts(h);
    expect(counts['expenses'], 2);
    expect(counts['outbox'], 2);
    expect(
      h.linesOf('auth', Level.SEVERE),
      contains(
        matches(
          r'account delete: account deleted on server rid=ridprofile000001, '
          r'but phone data not cleared after \d+ms → session marked ended, '
          r'data stays until the next sign-in clears it: StateError: '
          r'Bad state: disk I/O error while clearing\n',
        ),
      ),
    );
    await _waitSnackbarOut(tester);
  });

  testUnmounting('пустой пароль: ошибка под полем, запроса нет', (
    tester,
  ) async {
    final server = _Server(_deleted);
    final h = await _open(tester, server: server);

    await h.tap(_button('Удалить навсегда'));

    expect(h.errorUnder(_label), 'Введи пароль');
    expect(server.order, isEmpty);
    await _expectNothingDeleted(h);
  });

  testUnmounting('«Готово» на клавиатуре только прячет её: без кнопки '
      'аккаунт не удаляется', (tester) async {
    final server = _Server(_deleted);
    final h = await _open(tester, server: server);

    await h.enter(_label, _password);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await h.settle();

    expect(server.order, isEmpty);
    expect(find.byType(DeleteAccountScreen), findsOneWidget);
    await _expectNothingDeleted(h);
  });

  testUnmounting('«Передумал» возвращает в профиль, ничего не удалено', (
    tester,
  ) async {
    final server = _Server(_deleted);
    final h = await _open(tester, server: server);

    await h.enter(_label, _password);
    await h.tap(_button('Передумал'));

    expect(find.byType(DeleteAccountScreen), findsNothing);
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(server.order, isEmpty);
    await _expectNothingDeleted(h);
    expect(
      h.linesOf('profile'),
      contains(
        endsWith('profile row delete account tap → /profile/delete-account'),
      ),
    );
    expect(
      h.linesOf('nav'),
      contains(
        endsWith('delete account closed by "changed my mind", nothing deleted'),
      ),
    );
  });
}
