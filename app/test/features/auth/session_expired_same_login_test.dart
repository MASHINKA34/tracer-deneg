import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/session/session_providers.dart';
import 'package:milionchik/data/session/session_state.dart';
import 'package:milionchik/features/auth/login_screen.dart';
import 'package:milionchik/features/auth/recovery_code_screen.dart';
import 'package:milionchik/features/month/month_screen.dart';
import 'package:milionchik/ui/components/dialog.dart';

import '../profile/profile_fixture.dart';
import 'session_expired_fixture.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testUnmounting('вход тем же логином после истёкшей сессии: без диалога, '
      'траты и очередь на месте, загрузка продолжается с прежнего курсора', (
    tester,
  ) async {
    final server = ExpiredSessionServer();
    final h = await startSignedIn(tester, server);
    final before = await tableCounts(tester, h.db);
    await expireOnMonth(h);

    await submitLogin(h, login: ' Anya_M ');

    expect(find.byType(AppDialog), findsNothing);
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byType(MonthScreen), findsOneWidget);
    final state = h.container.read(sessionProvider);
    expect(state, isA<SessionActive>());
    expect(state.userId, profileUserId);
    expect(
      h.adapter.callsTo('/auth/login').single.json['login'],
      profileUser.login,
    );
    expect(await tableCounts(tester, h.db), before);
    expect(await outboxSize(tester, h.db), 3);
    expect(server.pulls[sameAccess], [keptCursor]);
    expect(await syncCursor(tester, h.db), keptCursor);

    final auth = h.linesOf('auth', Level.INFO);
    expect(
      auth,
      contains(
        matches(
          r'login after session end with the same login=an\*\*\* '
          r'previousUserId=user-server-77 previousLogin=an\*\*\* queue=3 → '
          r'usual sign-in, local data and queue kept \(counted in \d+ms\)$',
        ),
      ),
    );
    expect(
      auth,
      contains(
        endsWith(
          'login: same account userId=user-server-77 as the ended session → '
          'local data and queue kept, the queue goes to the server as usual',
        ),
      ),
    );
    expect(h.linesOf('repo'), isNot(contains(contains('account data'))));
    expect(h.logs.text, isNot(contains(userPassword)));
    expect(h.logs.text, isNot(contains(sameAccess)));
    expect(h.logs.text, isNot(contains(newRefresh)));
    expect(tester.takeException(), isNull);
  });

  testUnmounting('«Забыл пароль» тем же логином после истёкшей сессии: '
      'без диалога, данные телефона и очередь не стираются', (tester) async {
    final server = ExpiredSessionServer();
    final h = await startSignedIn(tester, server);
    final before = await tableCounts(tester, h.db);
    await expireOnMonth(h);

    await submitRecover(h, login: 'Anya_M');

    expect(find.byType(AppDialog), findsNothing);
    expect(find.byType(RecoveryCodeScreen), findsOneWidget);
    expect(h.adapter.callsTo('/auth/recover'), hasLength(1));
    expect(h.container.read(sessionProvider).userId, profileUserId);
    expect(await tableCounts(tester, h.db), before);
    expect(await outboxSize(tester, h.db), 3);
    expect(
      h.linesOf('auth', Level.INFO),
      contains(
        endsWith(
          'recover: same account userId=user-server-77 as the ended session '
          '→ local data and queue kept, the queue goes to the server as usual',
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
