import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/session/session_state.dart';
import 'package:milionchik/features/auth/login_screen.dart';
import 'package:milionchik/features/expense/new_expense_screen.dart';
import 'package:milionchik/features/month/month_controller.dart';
import 'package:milionchik/features/month/month_screen.dart';
import 'package:milionchik/ui/components/bottom_nav.dart';
import 'package:milionchik/ui/components/button.dart';
import 'package:shared/shared.dart';

import '../../data/api/fake_api_adapter.dart';
import '../../data/sync/pull_fixture.dart' show serverPersonal;
import 'auth_harness.dart';
import 'session_expired_fixture.dart' show testUnmounting;

const _password = 'Pass-Word-Deep-Link-Juliett';

FakeReply _server(FakeCall call) {
  final path = call.path;
  if (path.endsWith('/auth/login')) return signedIn();
  if (path.endsWith('/sync/pull')) {
    return FakeReply.json(
      200,
      SyncPullResponse(
        budgets: [serverPersonal()],
        cursor: 1,
        hasMore: false,
      ).toJson(),
    );
  }
  if (path.endsWith('/sync/push')) {
    final request = SyncPushRequest.fromJson(call.json);
    return FakeReply.json(
      200,
      SyncPushResponse(
        applied: [for (final c in request.changes) c.id],
        rejected: const [],
        cursor: 1,
      ).toJson(),
    );
  }
  if (path.endsWith('/me')) return FakeReply.json(200, serverUser());
  return FakeReply.error(404, 'not_found');
}

Future<AuthHarness> _start(WidgetTester tester, {String? coldLink}) {
  if (coldLink != null) {
    tester.platformDispatcher.defaultRouteNameTestValue = coldLink;
    addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
  }
  return AuthHarness.start(tester, server: _server);
}

Future<void> _sendLink(WidgetTester tester, String link) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.navigation.name,
    SystemChannels.navigation.codec.encodeMethodCall(
      MethodCall('pushRouteInformation', <String, Object?>{'location': link}),
    ),
    (_) {},
  );
  await tester.pumpAndSettle();
}

Future<void> _signIn(AuthHarness h) async {
  await h.enter('Логин', 'anya_m');
  await h.enter('Пароль', _password);
  await h.tester.tap(find.widgetWithText(AppButton, 'Войти'));
  await h.tester.pumpAndSettle();
  await h.tester.pumpAndSettle();
}

void main() {
  testUnmounting('холодный старт по milionchik://add без сессии: сначала '
      'вход, после входа — «Новая трата» поверх главной', (tester) async {
    final h = await _start(tester, coldLink: 'milionchik://add');

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(NewExpenseScreen), findsNothing);
    expect(
      h.linesOf('nav', Level.INFO),
      contains(
        endsWith(
          'deep link milionchik://add router=first screen → /auth/login first, '
          '/expense/new over /month after sign-in',
        ),
      ),
    );

    await _signIn(h);

    expect(h.session, isA<SessionActive>());
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byType(NewExpenseScreen), findsOneWidget);
    expect(find.byType(MonthScreen, skipOffstage: false), findsOneWidget);
    expect(
      h.linesOf('nav', Level.INFO),
      contains(
        endsWith(
          'deep link milionchik://add after sign-in → /expense/new over /month',
        ),
      ),
    );

    await tester.tap(find.bySemanticsLabel('Закрыть'));
    await tester.pumpAndSettle();
    expect(find.byType(NewExpenseScreen), findsNothing);
    expect(find.byType(MonthScreen), findsOneWidget);
    expect(h.logs.text, isNot(contains(_password)));
  });

  testUnmounting('тёплый старт milionchik://month на экране входа: вход '
      'остаётся, после входа — главная на текущем месяце', (tester) async {
    final h = await _start(tester);
    expect(find.byType(LoginScreen), findsOneWidget);

    await _sendLink(tester, 'milionchik://month?from=QUERY-VALUE-XRAY');

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(
      h.linesOf('nav', Level.INFO),
      contains(
        endsWith(
          'deep link milionchik://month router=on /auth/login '
          'query=ignored → /auth/login first, /month on the current month '
          'after sign-in',
        ),
      ),
    );

    await _signIn(h);

    expect(find.byType(MonthScreen), findsOneWidget);
    expect(find.byType(NewExpenseScreen), findsNothing);
    expect(h.container.read(monthControllerProvider), YearMonth(2026, 10));
    expect(
      h.linesOf('nav', Level.INFO),
      contains(
        endsWith(
          'deep link milionchik://month after sign-in → /month on the current '
          'month',
        ),
      ),
    );
    expect(h.logs.text, isNot(contains('QUERY-VALUE-XRAY')));
  });

  testUnmounting('новая ссылка на входе заменяет прежнюю, неизвестная — '
      'после входа просто главная', (tester) async {
    final h = await _start(tester, coldLink: 'milionchik://add');

    await _sendLink(tester, 'milionchik://unknown/path');

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(
      h.linesOf('nav', Level.WARNING),
      contains(
        endsWith(
          'deep link milionchik://unknown/path router=on /auth/login: '
          'unknown link, known: milionchik://add, milionchik://month → '
          '/auth/login, nothing to open after sign-in',
        ),
      ),
    );

    await _signIn(h);

    expect(find.byType(MonthScreen), findsOneWidget);
    expect(find.byType(NewExpenseScreen), findsNothing);
    final tab = tester.widget<AppBottomNav>(find.byType(AppBottomNav)).active;
    expect(tab, AppNavTab.month);
    expect(
      h.linesOf('nav', Level.INFO).where((l) => l.contains('after sign-in →')),
      isEmpty,
    );
  });
}
