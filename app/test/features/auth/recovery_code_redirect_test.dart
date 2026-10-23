import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/auth_gate.dart';
import 'package:milionchik/core/router.dart';
import 'package:milionchik/data/api/api_exception.dart';
import 'package:milionchik/data/session/session.dart';
import 'package:milionchik/data/session/session_state.dart';
import 'package:milionchik/data/session/session_store.dart';
import 'package:milionchik/features/auth/login_screen.dart';
import 'package:milionchik/features/auth/recovery_code_screen.dart';

import 'auth_harness.dart';

const _user = SessionUser(
  userId: 'user-server-77',
  login: 'anya_m',
  displayName: 'Аня',
);

String _location(WidgetTester tester) =>
    GoRouter.of(tester.element(find.byType(Navigator).first))
        .routerDelegate
        .currentConfiguration
        .uri
        .toString();

void main() {
  group('authRedirect с неподтверждённым кодом восстановления', () {
    final sessions = <SessionState>[
      const SessionActive(_user),
      const SessionAbsent(),
      const SessionEnded(_user, SessionEndReason.refreshRejected),
    ];

    test('код ждёт подтверждения: любой адрес → экран кода при любой сессии, '
        'сам экран кода остаётся', () {
      for (final session in sessions) {
        for (final path in [
          AppRoutes.month,
          AppRoutes.login,
          AppRoutes.register,
          AppRoutes.forgotPassword,
          'milionchik://add',
        ]) {
          expect(
            authRedirect(
              uri: Uri.parse(path),
              session: session,
              signInRequired: true,
              recoveryCodePending: true,
            ),
            AppRoutes.recoveryCode,
            reason: '${session.name} $path',
          );
        }
        expect(
          authRedirect(
            uri: Uri.parse(AppRoutes.recoveryCode),
            session: session,
            signInRequired: true,
            recoveryCodePending: true,
          ),
          isNull,
          reason: session.name,
        );
      }
    });

    test('кода нет: с экрана кода - на главную с сессией, на вход без неё', () {
      final code = Uri.parse(AppRoutes.recoveryCode);
      expect(
        authRedirect(
          uri: code,
          session: const SessionActive(_user),
          signInRequired: true,
        ),
        AppRoutes.month,
      );
      for (final session in sessions.skip(1)) {
        for (final required in [true, false]) {
          expect(
            authRedirect(uri: code, session: session, signInRequired: required),
            AppRoutes.login,
            reason: '${session.name} signInRequired=$required',
          );
        }
      }
    });
  });

  testWidgets('регистрация прошла, но сессия не записалась: код всё равно '
      'показан, после «Продолжить» - вход', (tester) async {
    final h = await AuthHarness.start(
      tester,
      server: (call) =>
          signedIn(status: 201, login: 'anya', recoveryCode: 'WZ5N-QR8H-MV3T'),
    );
    h.values.failWriteOf = SessionStore.userKey;
    await h.tapText('Зарегистрироваться');
    await h.enter('Как тебя зовут', 'Аня');
    await h.enter('Логин', 'anya');
    await h.enter('Пароль', 'Pass-Word-Redirect-Twelve');
    await h.enter('Повтори пароль', 'Pass-Word-Redirect-Twelve');

    await h.tapText('Создать аккаунт');

    expect(find.byType(RecoveryCodeScreen), findsOneWidget);
    expect(find.text('WZ5N-QR8H-MV3T'), findsOneWidget);
    expect(h.session, isA<SessionAbsent>());
    expect(
      h.linesOf('auth', Level.SEVERE),
      contains(
        contains(
          'register accepted by server but session not saved on the phone '
          'userId=user-server-77 login=an*** rid=ridauthscreen001',
        ),
      ),
    );

    await h.tapText('Я сохранил код в надёжном месте');
    await h.tapText('Продолжить');

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(RecoveryCodeScreen), findsNothing);
    expect(_location(tester), AppRoutes.login);
    expect(
      h.linesOf('auth', Level.FINE),
      contains(
        endsWith(
          'auth stack: /auth/code has no code to show and session is absent '
          '→ /auth/login',
        ),
      ),
    );
    for (final secret in ['WZ5N-QR8H-MV3T', 'WZ5NQR8HMV3T']) {
      expect(h.logs.text, isNot(contains(secret)), reason: secret);
    }
  });
}
