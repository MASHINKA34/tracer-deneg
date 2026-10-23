import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/auth_gate.dart';
import 'package:milionchik/data/api/api_exception.dart';
import 'package:milionchik/data/session/session_providers.dart';
import 'package:milionchik/data/session/session_state.dart';
import 'package:milionchik/features/auth/login_screen.dart';
import 'package:milionchik/features/month/month_screen.dart';
import 'package:milionchik/ui/components/bottom_nav.dart';

import '../profile/profile_fixture.dart';
import '../profile/profile_harness.dart';
import 'session_expired_fixture.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testUnmounting('refresh отклонён при загрузке: экран входа с текстом «Сессия '
      'закончилась, войди снова», траты, очередь, курсор и сессия на телефоне '
      'не тронуты', (tester) async {
    final server = ExpiredSessionServer();
    final h = await startSignedIn(tester, server);
    final before = await tableCounts(tester, h.db);
    expect(before['outbox'], 3);
    expect(before['expenses'], 3);
    expect(find.byType(MonthScreen), findsOneWidget);

    await pullDownOnMonth(h);

    expect(server.order, [
      'GET /api/v1/sync/pull',
      'POST /api/v1/auth/refresh',
    ]);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(AppBottomNav), findsNothing);
    expect(find.text('Сессия закончилась, войди снова'), findsOneWidget);
    expect(
      find.text('Войди — и траты подтянутся на этот телефон'),
      findsNothing,
    );
    expect(find.text('Не удалось загрузить'), findsNothing);

    final state = h.container.read(sessionProvider);
    expect(state, isA<SessionEnded>());
    expect((state as SessionEnded).reason, SessionEndReason.refreshRejected);
    expect(await tableCounts(tester, h.db), before);
    expect(await syncCursor(tester, h.db), keptCursor);
    final stored = await tester.runAsync(
      () => h.container.read(sessionStoreProvider).read(),
    );
    expect(stored?.user, profileUser);

    expect(
      h.linesOf('auth', Level.INFO),
      contains(
        matches(
          r'refresh token rejected → re-login reason=refreshRejected '
          r'userId=user-server-77 queue=3 → sign-in screen with "session '
          r'ended" notice, local data and queue kept \(counted in \d+ms\)$',
        ),
      ),
    );
    expect(
      h.linesOf('month', Level.INFO),
      contains(
        endsWith(
          'pull failed #1 reason=manual ApiSessionExpired: session ended → '
          'sign-in screen, no retry snackbar, data on the phone kept',
        ),
      ),
    );
    expect(
      h.linesOf('auth', Level.INFO),
      contains(
        endsWith(
          'login screen opened after session end reason=refreshRejected '
          'userId=user-server-77 → "session ended" notice shown, local data '
          'kept',
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testUnmounting('без истёкшей сессии на входе прежний подзаголовок', (
    tester,
  ) async {
    await ProfileHarness.start(
      tester,
      user: null,
      seed: false,
      overrides: [signInRequiredProvider.overrideWithValue(true)],
    );

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(
      find.text('Войди — и траты подтянутся на этот телефон'),
      findsOneWidget,
    );
    expect(find.text('Сессия закончилась, войди снова'), findsNothing);
  });
}
