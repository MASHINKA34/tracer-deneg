import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/session/session_state.dart';
import 'package:milionchik/data/session/session_store.dart';
import 'package:milionchik/features/auth/forgot_password_screen.dart';
import 'package:milionchik/features/auth/login_screen.dart';
import 'package:milionchik/features/auth/recovery_code_screen.dart';
import 'package:milionchik/features/auth/recovery_code_state.dart';
import 'package:milionchik/features/month/month_screen.dart';
import 'package:milionchik/ui/components/button.dart';
import 'package:milionchik/ui/components/snackbar.dart';

import '../../data/api/fake_api_adapter.dart';
import 'auth_harness.dart';

const _password = 'Pass-Word-Recover-Seventy-Four';
const _oldCode = 'k7qm-4xpa-9trb';
const _oldCompact = 'K7QM4XPA9TRB';
const _newCode = 'WZ5N-QR8H-MV3T';
const _access = 'ACCESS-recover-india-juliet';
const _refresh = 'REFRESH-recover-kilo-lima';

FakeReply _noServer(FakeCall call) =>
    throw StateError('no request expected, got ${call.method} ${call.path}');

void main() {
  Future<AuthHarness> openForgot(
    WidgetTester tester, {
    FakeHandler server = _noServer,
  }) async {
    final h = await AuthHarness.start(tester, server: server);
    await h.tapText('Забыл пароль?');
    expect(find.byType(ForgotPasswordScreen), findsOneWidget);
    return h;
  }

  Future<void> fill(
    AuthHarness h, {
    String login = 'Anya_M',
    String code = _oldCode,
    String password = _password,
    String? repeat,
  }) async {
    await h.enter('Логин', login);
    await h.enter('Код восстановления', code);
    await h.enter('Новый пароль', password);
    await h.enter('Повтори пароль', repeat ?? password);
  }

  Future<void> submit(WidgetTester tester) async {
    final button = find.widgetWithText(AppButton, 'Сменить пароль');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets('код в нижнем регистре с дефисами уходит на POST /auth/recover '
      'без дефисов прописными; новый код на том же экране кода, затем '
      'главная', (tester) async {
    final h = await openForgot(
      tester,
      server: (call) =>
          signedIn(access: _access, refresh: _refresh, recoveryCode: _newCode),
    );
    await fill(h);

    await submit(tester);

    final call = h.adapter.calls.single;
    expect(call.method, 'POST');
    expect(call.path, '/api/v1/auth/recover');
    expect(call.header('Authorization'), isNull);
    expect(call.json, {
      'login': 'anya_m',
      'recoveryCode': _oldCompact,
      'newPassword': _password,
      'deviceName': testDeviceName,
    });
    expect(h.session, isA<SessionActive>());
    expect(h.values.data.keys, {SessionStore.userKey, SessionStore.tokensKey});
    expect(find.byType(RecoveryCodeScreen), findsOneWidget);
    expect(find.text(_newCode), findsOneWidget);
    expect(find.byType(ForgotPasswordScreen), findsNothing);
    expect(
      h.container.read(pendingRecoveryCodeProvider)?.reason,
      RecoveryCodeReason.recover,
    );

    await h.tapText('Я сохранил код в надёжном месте');
    await h.tapText('Продолжить');

    expect(find.byType(MonthScreen), findsOneWidget);
    expect(
      h.linesOf('auth', Level.INFO),
      containsAllInOrder([
        endsWith('recovery code kept in memory until confirmed reason=recover'),
        matches(
          RegExp(
            r'recover ok userId=user-server-77 login=an\*\*\* '
            r'recoveryCode=issued rid=ridauthscreen001 in \d+ms$',
          ),
        ),
        endsWith(
          'recovery code screen shown reason=recover (code is never '
          'logged)',
        ),
      ]),
    );
    for (final secret in [
      _password,
      _oldCode,
      _oldCompact,
      _newCode,
      _newCode.replaceAll('-', ''),
      _access,
      _refresh,
      'anya_m',
    ]) {
      expect(h.logs.text, isNot(contains(secret)), reason: secret);
    }
  });

  testWidgets('ввод кода без учёта регистра, дефисов и пробелов; '
      'похожие O/I/L читаются как 0/1', (tester) async {
    final h = await openForgot(
      tester,
      server: (call) => FakeReply.error(401, 'bad_credentials'),
    );
    for (final (typed, sent) in [
      ('k7qm4xpa9trb', 'K7QM4XPA9TRB'),
      (' K7QM 4XPA 9TRB ', 'K7QM4XPA9TRB'),
      ('k7qm-4xpa-9trb', 'K7QM4XPA9TRB'),
      ('o1il-oooo-1111', '011100001111'),
    ]) {
      await fill(h, code: typed);
      await submit(tester);
      expect(h.adapter.calls.last.json['recoveryCode'], sent, reason: typed);
    }
    expect(h.adapter.calls, hasLength(4));
  });

  testWidgets('ошибки полей до запроса: пустые поля, код не из 12 символов '
      'алфавита, пароль короткий, повтор не совпадает', (tester) async {
    final h = await openForgot(tester);

    await submit(tester);
    expect(h.errorUnder('Логин'), 'Введи логин');
    expect(h.errorUnder('Код восстановления'), 'Введи код восстановления');
    expect(h.errorUnder('Новый пароль'), 'Введи пароль');
    expect(h.errorUnder('Повтори пароль'), isNull);
    expect(
      h.linesOf('auth', Level.FINE),
      contains(
        endsWith(
          'recover blocked by validation login=login_empty '
          'code=recovery_code_empty password=password_empty repeat=none',
        ),
      ),
    );

    for (final code in ['K7QM-4XPA', 'K7QM-4XPA-9TRB-1', 'K7QM-4XPA-9TRU']) {
      await fill(h, code: code, password: '123', repeat: '');
      expect(
        h.errorUnder('Код восстановления'),
        'Проверь код: в нём 12 латинских букв и цифр',
        reason: code,
      );
      expect(
        h.errorUnder('Новый пароль'),
        'Пароль слишком короткий: нужно от 6 символов',
      );
    }

    await fill(h, repeat: '$_password-x');
    expect(h.errorUnder('Логин'), isNull);
    expect(h.errorUnder('Код восстановления'), isNull);
    expect(h.errorUnder('Новый пароль'), isNull);
    expect(h.errorUnder('Повтори пароль'), 'Пароли не совпадают');

    await submit(tester);
    expect(h.adapter.calls, isEmpty);
    expect(find.byType(ForgotPasswordScreen), findsOneWidget);
  });

  testWidgets('401 bad_credentials: «Неверный логин или код восстановления» '
      'под кодом, без снекбара; правка кода убирает ошибку', (tester) async {
    final h = await openForgot(
      tester,
      server: (call) => FakeReply.error(
        401,
        'bad_credentials',
        'Неверный логин или код восстановления',
      ),
    );
    await fill(h);

    await submit(tester);

    expect(
      h.errorUnder('Код восстановления'),
      'Неверный логин или код восстановления',
    );
    expect(h.errorUnder('Логин'), isNull);
    expect(h.errorUnder('Новый пароль'), isNull);
    expect(find.byType(AppSnackbar), findsNothing);
    expect(h.session, isA<SessionAbsent>());
    expect(h.container.read(pendingRecoveryCodeProvider), isNull);
    expect(
      h.linesOf('auth', Level.INFO),
      contains(
        matches(
          RegExp(
            r'recover rejected code=bad_credentials status=401 '
            r'login=an\*\*\* rid=ridauthscreen001 in \d+ms$',
          ),
        ),
      ),
    );

    await h.enter('Код восстановления', 'K7QM-4XPA-9TRC');
    expect(h.errorUnder('Код восстановления'), isNull);
    for (final secret in [_password, _oldCompact, 'anya_m']) {
      expect(h.logs.text, isNot(contains(secret)), reason: secret);
    }
  });

  testWidgets('400 password_too_short - под новым паролем; 429 и сеть - '
      'снекбаром', (tester) async {
    var status = 400;
    final h = await openForgot(
      tester,
      server: (call) => switch (status) {
        400 => FakeReply.error(400, 'password_too_short'),
        429 => FakeReply.error(429, 'too_many_attempts'),
        _ => FakeReply.error(503, 'internal', 'Сломалось'),
      },
    );
    await fill(h);

    await submit(tester);
    expect(
      h.errorUnder('Новый пароль'),
      'Пароль слишком короткий: нужно от 6 символов',
    );
    expect(find.byType(AppSnackbar), findsNothing);

    status = 429;
    await submit(tester);
    expect(find.text('Слишком много попыток. Попробуй позже'), findsOneWidget);
    expect(h.errorUnder('Код восстановления'), isNull);

    status = 503;
    await submit(tester);
    expect(
      find.text('На сервере что-то сломалось. Попробуй позже'),
      findsOneWidget,
    );
    expect(h.adapter.calls, hasLength(3));
    expect(find.byType(ForgotPasswordScreen), findsOneWidget);
  });

  testWidgets('стрелка «назад» возвращает на вход', (tester) async {
    final h = await openForgot(tester);

    await h.tapLabel('Назад');

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(ForgotPasswordScreen), findsNothing);
    expect(
      h.linesOf('auth', Level.FINE),
      containsAllInOrder([
        endsWith('forgot password screen opened'),
        endsWith('auth stack: forgot password → back to login'),
      ]),
    );
  });

  testWidgets('кнопка недоступна, пока идёт запрос: второй запрос не уходит', (
    tester,
  ) async {
    final h = await openForgot(
      tester,
      server: (call) async {
        await Future<void>.delayed(const Duration(seconds: 1));
        return FakeReply.error(401, 'bad_credentials');
      },
    );
    await fill(h);
    final button = find.widgetWithText(AppButton, 'Сменить пароль');
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
