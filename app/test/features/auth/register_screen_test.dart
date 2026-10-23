import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:milionchik/data/session/session_state.dart';
import 'package:milionchik/data/session/session_store.dart';
import 'package:milionchik/features/auth/login_screen.dart';
import 'package:milionchik/features/auth/recovery_code_screen.dart';
import 'package:milionchik/features/auth/register_screen.dart';
import 'package:milionchik/features/month/month_screen.dart';
import 'package:milionchik/ui/components/bottom_nav.dart';
import 'package:milionchik/ui/components/button.dart';
import 'package:milionchik/ui/components/snackbar.dart';

import '../../data/api/fake_api_adapter.dart';
import 'auth_harness.dart';

const _password = 'Pass-Word-Register-Sixty-Three';
const _recovery = 'RCVR-RGST-ZXCV';

FakeReply _noServer(FakeCall call) =>
    throw StateError('no request expected, got ${call.method} ${call.path}');

void main() {
  Future<AuthHarness> openRegister(
    WidgetTester tester, {
    FakeHandler server = _noServer,
  }) async {
    final h = await AuthHarness.start(tester, server: server);
    await h.tapText('Зарегистрироваться');
    expect(find.byType(RegisterScreen), findsOneWidget);
    return h;
  }

  Future<void> fill(
    AuthHarness h, {
    String name = 'Аня',
    String login = 'anya',
    String password = _password,
    String? repeat,
  }) async {
    await h.enter('Как тебя зовут', name);
    await h.enter('Логин', login);
    await h.enter('Пароль', password);
    await h.enter('Повтори пароль', repeat ?? password);
  }

  Future<void> create(WidgetTester tester) async {
    final button = find.widgetWithText(AppButton, 'Создать аккаунт');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets('«Зарегистрироваться» открывает регистрацию поверх входа без '
      'меню; стрелка «назад» возвращает на вход', (tester) async {
    final h = await openRegister(tester);

    expect(find.byType(AppBottomNav), findsNothing);
    expect(find.text('Регистрация'), findsOneWidget);
    expect(find.text('Минимум 6 символов'), findsOneWidget);

    await h.tapLabel('Назад');
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(RegisterScreen), findsNothing);
    expect(
      h.linesOf('auth', Level.FINE),
      containsAllInOrder([
        endsWith('auth stack: login → /auth/register'),
        endsWith('register screen opened'),
        endsWith('auth stack: register → back to login by back button'),
      ]),
    );
  });

  testWidgets('ссылка «Войти» на регистрации тоже возвращает на вход', (
    tester,
  ) async {
    final h = await openRegister(tester);

    await h.tapText('Войти');

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(RegisterScreen), findsNothing);
  });

  testWidgets('ошибки полей из shared под полями, повтор пароля сверяется, '
      'запроса нет', (tester) async {
    final h = await openRegister(tester);

    await create(tester);

    expect(h.errorUnder('Как тебя зовут'), 'Введи имя');
    expect(h.errorUnder('Логин'), 'Введи логин');
    expect(h.errorUnder('Пароль'), 'Введи пароль');
    expect(h.errorUnder('Повтори пароль'), isNull);
    expect(h.adapter.calls, isEmpty);
    expect(
      h.linesOf('auth', Level.FINE),
      contains(
        endsWith(
          'register blocked by validation name=name_empty login=login_empty '
          'password=password_empty repeat=none',
        ),
      ),
    );

    await fill(
      h,
      name: 'Очень длинное имя, которое никак не влезает в сорок',
      login: 'anya.m!',
      password: '123',
      repeat: '',
    );
    expect(
      h.errorUnder('Как тебя зовут'),
      'Имя слишком длинное: не больше 40 символов',
    );
    expect(
      h.errorUnder('Логин'),
      'В логине можно только латинские буквы, цифры, точку и подчёркивание',
    );
    expect(
      h.errorUnder('Пароль'),
      'Пароль слишком короткий: нужно от 6 символов',
    );

    await fill(h, repeat: '$_password-x');
    expect(h.errorUnder('Как тебя зовут'), isNull);
    expect(h.errorUnder('Логин'), isNull);
    expect(h.errorUnder('Пароль'), isNull);
    expect(h.errorUnder('Повтори пароль'), 'Пароли не совпадают');

    await create(tester);
    expect(h.adapter.calls, isEmpty);
  });

  testWidgets('логин занят (409 login_taken): ошибка под полем логина, '
      'остальные поля без ошибок; правка логина её убирает', (tester) async {
    final h = await openRegister(
      tester,
      server: (call) =>
          FakeReply.error(409, 'login_taken', 'Такой логин уже занят'),
    );
    await fill(h, name: '  Аня ', login: 'Anya');

    await create(tester);

    final call = h.adapter.calls.single;
    expect(call.path, '/api/v1/auth/register');
    expect(call.json, {
      'login': 'anya',
      'displayName': 'Аня',
      'password': _password,
      'deviceName': testDeviceName,
    });
    expect(h.errorUnder('Логин'), 'Такой логин уже занят');
    expect(h.errorUnder('Как тебя зовут'), isNull);
    expect(h.errorUnder('Пароль'), isNull);
    expect(h.errorUnder('Повтори пароль'), isNull);
    expect(find.byType(AppSnackbar), findsNothing);
    expect(
      h.linesOf('auth', Level.INFO),
      contains(
        matches(
          RegExp(
            r'register rejected code=login_taken status=409 login=an\*\*\* '
            r'rid=ridauthscreen001 in \d+ms$',
          ),
        ),
      ),
    );

    await h.enter('Логин', 'anya_m');
    expect(h.errorUnder('Логин'), isNull);
  });

  testWidgets('ошибка проверки на сервере (400 password_too_short) - под '
      'полем пароля', (tester) async {
    final h = await openRegister(
      tester,
      server: (call) => FakeReply.error(400, 'password_too_short'),
    );
    await fill(h);

    await create(tester);

    expect(
      h.errorUnder('Пароль'),
      'Пароль слишком короткий: нужно от 6 символов',
    );
    expect(find.byType(AppSnackbar), findsNothing);
  });

  testWidgets('сетевые и серверные ошибки - снекбаром, поля без ошибок', (
    tester,
  ) async {
    var status = 503;
    final h = await openRegister(
      tester,
      server: (call) => status == 429
          ? FakeReply.error(429, 'too_many_attempts')
          : FakeReply.error(503, 'internal', 'Сломалось'),
    );
    await fill(h);

    await create(tester);
    expect(
      find.text('На сервере что-то сломалось. Попробуй позже'),
      findsOneWidget,
    );
    expect(h.errorUnder('Логин'), isNull);

    status = 429;
    await create(tester);
    expect(find.text('Слишком много попыток. Попробуй позже'), findsOneWidget);
    expect(h.errorUnder('Логин'), isNull);
    expect(h.adapter.calls, hasLength(2));
  });

  testWidgets('успешная регистрация: сессия сохранена, экран кода, после '
      '«Продолжить» главная, код восстановления не попадает в лог', (
    tester,
  ) async {
    final h = await openRegister(
      tester,
      server: (call) =>
          signedIn(status: 201, login: 'anya', recoveryCode: _recovery),
    );
    await fill(h);

    await create(tester);
    await tester.pumpAndSettle();

    expect(h.session, isA<SessionActive>());
    expect(h.values.data.keys, {SessionStore.userKey, SessionStore.tokensKey});
    expect(
      await tester.runAsync(
        () => h.container
            .read(prefsRepositoryProvider)
            .getBool(PrefKeys.signedInBefore),
      ),
      isTrue,
    );
    expect(find.byType(RecoveryCodeScreen), findsOneWidget);
    expect(find.text(_recovery), findsOneWidget);
    expect(find.byType(MonthScreen), findsNothing);
    expect(find.byType(RegisterScreen), findsNothing);
    expect(find.byType(LoginScreen), findsNothing);

    await h.tapText('Я сохранил код в надёжном месте');
    await h.tapText('Продолжить');

    expect(find.byType(MonthScreen), findsOneWidget);
    expect(find.byType(RecoveryCodeScreen), findsNothing);
    expect(
      h.linesOf('auth', Level.INFO),
      contains(
        matches(
          RegExp(
            r'register ok userId=user-server-77 login=an\*\*\* '
            r'recoveryCode=issued rid=ridauthscreen001 in \d+ms$',
          ),
        ),
      ),
    );
    for (final secret in [_password, _recovery, 'Аня']) {
      expect(h.logs.text, isNot(contains(secret)), reason: secret);
    }
  });

  testWidgets('кнопка недоступна, пока идёт запрос: второй запрос не уходит', (
    tester,
  ) async {
    final h = await openRegister(
      tester,
      server: (call) async {
        await Future<void>.delayed(const Duration(seconds: 1));
        return FakeReply.error(409, 'login_taken');
      },
    );
    await fill(h);
    final button = find.widgetWithText(AppButton, 'Создать аккаунт');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();

    await tester.tap(button);
    await tester.pump();
    expect(tester.widget<AppButton>(button).onPressed, isNull);
    await tester.tap(button, warnIfMissed: false);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(h.adapter.calls, hasLength(1));
    expect(tester.widget<AppButton>(button).onPressed, isNotNull);
    expect(tester.widget<TextField>(h.input('Логин')).enabled, isNot(false));
  });
}
