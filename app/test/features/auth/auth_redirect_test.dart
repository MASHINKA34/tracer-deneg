import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/auth_gate.dart';
import 'package:milionchik/core/router.dart';
import 'package:milionchik/data/api/api_exception.dart';
import 'package:milionchik/data/api/token_store.dart';
import 'package:milionchik/data/session/session.dart';
import 'package:milionchik/data/session/session_providers.dart';
import 'package:milionchik/data/session/session_state.dart';
import 'package:milionchik/features/auth/login_screen.dart';
import 'package:milionchik/features/month/month_screen.dart';
import 'package:milionchik/ui/components/bottom_nav.dart';

import '../../data/api/fake_api_adapter.dart';
import 'auth_harness.dart';

const _user = SessionUser(
  userId: 'user-server-77',
  login: 'anya_m',
  displayName: 'Аня',
);

const _session = Session(
  user: _user,
  tokens: AuthTokens(
    accessToken: 'ACCESS-redirect-alpha-bravo',
    refreshToken: 'REFRESH-redirect-charlie-delta',
  ),
);

FakeReply _noServer(FakeCall call) =>
    throw StateError('no request expected, got ${call.method} ${call.path}');

String _location(WidgetTester tester) =>
    GoRouter.of(tester.element(find.byType(Navigator).first))
        .routerDelegate
        .currentConfiguration
        .uri
        .toString();

void main() {
  group('authRedirect', () {
    final month = Uri.parse(AppRoutes.month);
    final login = Uri.parse(AppRoutes.login);

    test('нет сессии и вход обязателен: любой экран приложения → вход, экраны '
        'стека входа остаются', () {
      for (final session in [
        const SessionAbsent(),
        const SessionEnded(_user, SessionEndReason.refreshRejected),
      ]) {
        expect(
          authRedirect(uri: month, session: session, signInRequired: true),
          AppRoutes.login,
        );
        expect(
          authRedirect(
            uri: Uri.parse('milionchik://add'),
            session: session,
            signInRequired: true,
          ),
          AppRoutes.login,
        );
        expect(
          authRedirect(uri: login, session: session, signInRequired: true),
          isNull,
        );
        expect(
          authRedirect(
            uri: Uri.parse(AppRoutes.register),
            session: session,
            signInRequired: true,
          ),
          isNull,
        );
      }
    });

    test('сессия есть: стек входа → главная, остальное без изменений', () {
      const active = SessionActive(_user);
      for (final path in [
        AppRoutes.login,
        AppRoutes.register,
        AppRoutes.forgotPassword,
      ]) {
        expect(
          authRedirect(
            uri: Uri.parse(path),
            session: active,
            signInRequired: true,
          ),
          AppRoutes.month,
        );
      }
      expect(
        authRedirect(uri: month, session: active, signInRequired: true),
        isNull,
      );
    });

    test('вход не обязателен (DEV_SEED): без сессии приложение открыто', () {
      expect(
        authRedirect(
          uri: month,
          session: const SessionAbsent(),
          signInRequired: false,
        ),
        isNull,
      );
    });
  });

  testWidgets('без сессии приложение открывается на входе без нижнего меню, '
      'в логе переход стека входа', (tester) async {
    final h = await AuthHarness.start(tester, server: _noServer);

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(AppBottomNav), findsNothing);
    expect(find.byType(MonthScreen), findsNothing);
    expect(_location(tester), AppRoutes.login);
    expect(
      h.linesOf('auth', Level.FINE),
      contains(
        endsWith(
          'auth stack: session absent → /month needs sign-in → /auth/login',
        ),
      ),
    );
  });

  testWidgets('с сессией вход не показывается: главная с меню', (tester) async {
    await AuthHarness.start(tester, server: _noServer, session: _session);

    expect(find.byType(MonthScreen), findsOneWidget);
    expect(find.byType(AppBottomNav), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
  });

  testWidgets('сессия появилась (вход) → главная; сессия закончилась → снова '
      'вход', (tester) async {
    final h = await AuthHarness.start(tester, server: _noServer);
    expect(find.byType(LoginScreen), findsOneWidget);

    await tester.runAsync(
      () => h.container.read(sessionProvider.notifier).save(_session),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MonthScreen), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
    expect(_location(tester), AppRoutes.month);
    expect(
      h.linesOf('auth', Level.FINE),
      contains(
        endsWith(
          'auth stack: session active userId=user-server-77 → leaving '
          '/auth/login for /month',
        ),
      ),
    );

    h.container
        .read(sessionProvider.notifier)
        .ended(SessionEndReason.refreshRejected);
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(AppBottomNav), findsNothing);
  });

  testWidgets('глубокая ссылка milionchik://add без сессии ведёт на вход', (
    tester,
  ) async {
    final h = await AuthHarness.start(tester, server: _noServer);

    GoRouter.of(tester.element(find.byType(LoginScreen)))
        .go('milionchik://add');
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(
      h.linesOf('auth', Level.FINE),
      contains(
        endsWith(
          'auth stack: session absent → milionchik://add needs sign-in → '
          '/auth/login',
        ),
      ),
    );
  });

  testWidgets('вход не обязателен (DEV_SEED, тесты экранов): без сессии '
      'сразу главная', (tester) async {
    await AuthHarness.start(tester, server: _noServer, signInRequired: false);

    expect(find.byType(MonthScreen), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
  });
}
