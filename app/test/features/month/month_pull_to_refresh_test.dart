import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/api/token_store.dart';
import 'package:milionchik/data/current_user.dart';
import 'package:milionchik/data/repositories/budgets_repository.dart';
import 'package:milionchik/data/repositories/categories_repository.dart';
import 'package:milionchik/data/repositories/outbox_queue.dart';
import 'package:milionchik/data/session/session.dart';
import 'package:milionchik/data/session/session_store.dart';
import 'package:milionchik/features/month/month_screen.dart';
import 'package:shared/shared.dart';

import '../../data/api/fake_api_adapter.dart';
import '../../data/sync/pull_fixture.dart';
import '../auth/auth_harness.dart';
import '../recurring/recurring_fixture.dart' show writeWhileShown;

const _session = Session(
  user: SessionUser(userId: pullUserId, login: 'anya_m', displayName: 'Аня'),
  tokens: AuthTokens(accessToken: pullAccess, refreshToken: pullRefresh),
);

final _personal = serverPersonal();

final _presets = serverPresets(_personal.id);

FakeReply _noServer(FakeCall call) =>
    throw StateError('no request expected, got ${call.method} ${call.path}');

Finder get _scroll => find.descendant(
  of: find.byType(RefreshIndicator),
  matching: find.byType(SingleChildScrollView),
);

Future<void> _pullDown(WidgetTester tester) async {
  await tester.fling(_scroll.first, const Offset(0, 400), 1200);
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('потянуть вниз на главной: pull с причиной manual, новая трата '
      'с сервера видна, индикатор шапки не включается', (tester) async {
    final pull = FakePullServer([
      SyncPullResponse(
        expenses: [
          serverExpense(
            id: 'e-pulled',
            budgetId: _personal.id,
            categoryId: _presets[2].id,
            kopecks: 123400,
            seq: 31,
          ),
        ],
        cursor: 31,
        hasMore: false,
      ),
    ]);
    final h = await AuthHarness.start(
      tester,
      server: pull.handle,
      session: _session,
    );
    await writeWhileShown(tester, () async {
      await SessionStore(h.values).save(_session);
      final user = SessionCurrentUser(pullUserId);
      final outbox = DriftOutboxQueue(h.db);
      await DriftBudgetsRepository(
        h.db,
        currentUser: user,
        outbox: outbox,
      ).applyFromServer([_personal]);
      await DriftCategoriesRepository(
        h.db,
        currentUser: user,
        outbox: outbox,
      ).applyFromServer(_presets);
    });
    await tester.pumpAndSettle();
    expect(find.byType(MonthScreen), findsOneWidget);
    expect(pull.cursors, isEmpty);
    expect(find.text(Money(123400).format()), findsNothing);

    await _pullDown(tester);

    expect(pull.cursors, [0]);
    expect(find.text(Money(123400).format()), findsWidgets);
    expect(find.bySemanticsLabel('Синхронизировано'), findsOneWidget);
    expect(
      h.linesOf('month', Level.FINE),
      contains(endsWith('month pulled down → pull reason=manual')),
    );
    expect(
      h.linesOf('month', Level.FINE),
      isNot(contains(contains('header sync indicator'))),
    );
    expect(
      h.linesOf('sync', Level.INFO),
      contains(
        matches(
          RegExp(
            r'pull done reason=manual pages=1 entities=1 .*expenses=1 '
            r'.*cursor=0→31 in \d+ms$',
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('без входа (демо-данные): потянуть вниз ничего не запрашивает', (
    tester,
  ) async {
    final h = await AuthHarness.start(
      tester,
      server: _noServer,
      signInRequired: false,
    );
    expect(find.byType(MonthScreen), findsOneWidget);

    await _pullDown(tester);

    expect(h.adapter.calls, isEmpty);
    expect(
      h.linesOf('sync', Level.INFO),
      contains(
        endsWith(
          'pull skipped reason=manual: session absent, nothing to load from '
          'the server',
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
