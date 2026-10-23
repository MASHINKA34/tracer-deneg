import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:milionchik/data/session/session_state.dart';
import 'package:milionchik/data/session/session_store.dart';
import 'package:milionchik/features/auth/forgot_password_screen.dart';
import 'package:milionchik/features/auth/login_screen.dart';
import 'package:milionchik/features/month/month_screen.dart';
import 'package:milionchik/ui/components/button.dart';
import 'package:milionchik/ui/components/snackbar.dart';

import '../../data/api/fake_api_adapter.dart';
import 'auth_harness.dart';

const _password = 'Pass-Word-Login-Screen-Forty-Two';
const _access = 'ACCESS-login-screen-papa-quebec';
const _refresh = 'REFRESH-login-screen-romeo-sierra';

FakeReply _noServer(FakeCall call) =>
    throw StateError('no request expected, got ${call.method} ${call.path}');

void main() {
  Future<void> fill(AuthHarness h, String login, String password) async {
    await h.enter('Логин', login);
    await h.enter('Пароль', password);
  }

  Future<void> signIn(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(AppButton, 'Войти'));
    await tester.pumpAndSettle();
  }

  testWidgets('пустые поля: ошибки из shared под полями, запроса нет', (
    tester,
  ) async {
    final h = await AuthHarness.start(tester, server: _noServer);

    await signIn(tester);

    expect(h.errorUnder('Логин'), 'Введи логин');
    expect(h.errorUnder('Пароль'), 'Введи пароль');
    expect(h.adapter.calls, isEmpty);
    expect(
      h.linesOf('auth', Level.FINE),
      contains(
        endsWith(
          'login blocked by validation login=login_empty '
          'password=password_empty',
        ),
      ),
    );

    await h.enter('Логин', 'Аня');
    expect(
      h.errorUnder('Логин'),
      'В логине можно только латинские буквы, цифры, точку и подчёркивание',
    );
    await h.enter('Логин', 'an');
    expect(
      h.errorUnder('Логин'),
      'Логин слишком короткий: нужно от 3 символов',
    );
    await h.enter('Пароль', '12345');
    expect(
      h.errorUnder('Пароль'),
      'Пароль слишком короткий: нужно от 6 символов',
    );
    await h.enter('Логин', 'anya_m');
    await h.enter('Пароль', '123456');
    expect(h.errorUnder('Логин'), isNull);
    expect(h.errorUnder('Пароль'), isNull);
  });

  testWidgets('«глазик» показывает и снова скрывает пароль', (tester) async {
    final h = await AuthHarness.start(tester, server: _noServer);
    await h.enter('Пароль', _password);

    expect(h.obscured('Пароль'), isTrue);
    await h.tapLabel('Показать пароль');
    expect(h.obscured('Пароль'), isFalse);
    await h.tapLabel('Скрыть пароль');
    expect(h.obscured('Пароль'), isTrue);
  });

  testWidgets('неверный пароль: ошибка «Неверный логин или пароль» под '
      'паролем как 42:4149, логин без ошибки; правка пароля убирает её', (
    tester,
  ) async {
    final h = await AuthHarness.start(
      tester,
      server: (call) =>
          FakeReply.error(401, 'bad_credentials', 'Неверный логин или пароль'),
    );
    await fill(h, 'Anya_M ', _password);

    await signIn(tester);

    expect(h.adapter.calls.single.json['login'], 'anya_m');
    expect(h.adapter.calls.single.json['deviceName'], testDeviceName);
    expect(h.errorUnder('Пароль'), 'Неверный логин или пароль');
    expect(h.errorUnder('Логин'), isNull);
    expect(find.byType(AppSnackbar), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(h.session, isA<SessionAbsent>());
    expect(
      h.linesOf('auth', Level.INFO),
      contains(
        matches(
          RegExp(
            r'login rejected code=bad_credentials status=401 login=an\*\*\* '
            r'rid=ridauthscreen001 in \d+ms$',
          ),
        ),
      ),
    );

    await h.enter('Пароль', 'Other-Password-1');
    expect(h.errorUnder('Пароль'), isNull);
    expect(h.logs.text, isNot(contains(_password)));
    expect(h.logs.text, isNot(contains('anya_m')));
  });

  testWidgets('нет сети: снекбар с текстом ошибки, поля без ошибок', (
    tester,
  ) async {
    final h = await AuthHarness.start(
      tester,
      server: (call) =>
          throw const SocketException('Connection refused (test)'),
    );
    await fill(h, 'anya_m', _password);

    await signIn(tester);

    expect(
      find.text('Нет связи с сервером. Проверь интернет и попробуй ещё раз'),
      findsOneWidget,
    );
    expect(h.errorUnder('Логин'), isNull);
    expect(h.errorUnder('Пароль'), isNull);
    expect(
      h.linesOf('auth', Level.WARNING),
      contains(contains('login failed ApiNetworkFailure: connection')),
    );
    expect(h.logs.text, isNot(contains(_password)));
  });

  testWidgets('слишком много попыток (429) - снекбар', (tester) async {
    final h = await AuthHarness.start(
      tester,
      server: (call) => FakeReply.error(429, 'too_many_attempts'),
    );
    await fill(h, 'anya_m', _password);

    await signIn(tester);

    expect(find.text('Слишком много попыток. Попробуй позже'), findsOneWidget);
    expect(h.errorUnder('Пароль'), isNull);
  });

  testWidgets('успешный вход: сессия в хранилище, отметка о входе, сразу '
      'главная; в логе результат без пароля и токенов', (tester) async {
    final h = await AuthHarness.start(
      tester,
      server: (call) => signedIn(access: _access, refresh: _refresh),
    );
    await fill(h, 'anya_m', _password);

    await signIn(tester);
    await tester.pumpAndSettle();

    expect(h.session, isA<SessionActive>());
    expect(h.session.userId, 'user-server-77');
    expect(h.values.data.keys, {SessionStore.userKey, SessionStore.tokensKey});
    expect(h.values.data[SessionStore.tokensKey], contains(_access));
    expect(
      await tester.runAsync(
        () => h.container
            .read(prefsRepositoryProvider)
            .getBool(PrefKeys.signedInBefore),
      ),
      isTrue,
    );
    expect(find.byType(MonthScreen), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
    expect(
      h.linesOf('auth', Level.INFO),
      contains(
        matches(
          RegExp(
            r'login ok userId=user-server-77 login=an\*\*\* '
            r'rid=ridauthscreen001 in \d+ms$',
          ),
        ),
      ),
    );
    for (final secret in [_password, _access, _refresh, 'anya_m']) {
      expect(h.logs.text, isNot(contains(secret)), reason: secret);
    }
  });

  testWidgets('сервер ответил, но сессия не записалась: снекбар, остаёмся на '
      'входе', (tester) async {
    final h = await AuthHarness.start(tester, server: (call) => signedIn());
    h.values.failWriteOf = SessionStore.userKey;
    await fill(h, 'anya_m', _password);

    await signIn(tester);

    expect(
      find.text('Не получилось сохранить вход на телефоне. Попробуй ещё раз'),
      findsOneWidget,
    );
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(h.session, isA<SessionAbsent>());
    expect(
      h.linesOf('auth', Level.SEVERE),
      contains(
        contains(
          'login accepted by server but session not saved on the phone '
          'userId=user-server-77 login=an***',
        ),
      ),
    );
  });

  testWidgets('«Забыл пароль?» открывает восстановление поверх входа, '
      '«назад» возвращает на вход', (tester) async {
    final h = await AuthHarness.start(tester, server: _noServer);

    await h.tapText('Забыл пароль?');
    expect(find.byType(ForgotPasswordScreen), findsOneWidget);
    expect(find.text('Восстановить доступ'), findsOneWidget);

    await h.tapLabel('Назад');
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(
      h.linesOf('auth', Level.FINE),
      containsAllInOrder([
        endsWith('auth stack: login → /auth/forgot'),
        endsWith('auth stack: forgot password → back to login'),
      ]),
    );
  });

  testWidgets('области нажатия ссылок не меньше 48 dp', (tester) async {
    await AuthHarness.start(tester, server: _noServer);

    for (final label in ['Забыл пароль?', 'Зарегистрироваться']) {
      final size = tester.getSize(
        find.ancestor(of: find.text(label), matching: find.byType(InkWell)),
      );
      expect(size.height, greaterThanOrEqualTo(48), reason: label);
      expect(size.width, greaterThanOrEqualTo(48), reason: label);
    }
  });
}
