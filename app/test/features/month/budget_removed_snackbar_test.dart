import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/api/token_store.dart';
import 'package:milionchik/data/current_user.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/repositories/budgets_repository.dart';
import 'package:milionchik/data/repositories/categories_repository.dart';
import 'package:milionchik/data/repositories/outbox_queue.dart';
import 'package:milionchik/data/session/session.dart';
import 'package:milionchik/data/session/session_store.dart';
import 'package:milionchik/features/month/month_screen.dart';
import 'package:milionchik/ui/components/snackbar.dart';
import 'package:shared/shared.dart';

import '../../data/sync/pull_fixture.dart';
import '../auth/auth_harness.dart';
import '../auth/session_expired_fixture.dart' show testUnmounting;
import '../recurring/recurring_fixture.dart' show writeWhileShown;

const _session = Session(
  user: SessionUser(userId: pullUserId, login: 'anya_m', displayName: 'Аня'),
  tokens: AuthTokens(accessToken: pullAccess, refreshToken: pullRefresh),
);

final _personal = serverPersonal();

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

Future<AuthHarness> _openFamily(WidgetTester tester, Budget family) async {
  final pull = FakePullServer([
    SyncPullResponse(removedBudgetIds: [family.id], cursor: 40, hasMore: false),
  ]);
  final h = await AuthHarness.start(
    tester,
    server: pull.handle,
    session: _session,
    overrides: [
      selectedBudgetIdProvider.overrideWith(
        (ref) => ref
            .watch(budgetsRepositoryProvider)
            .watchAll()
            .map(
              (all) =>
                  all.any((b) => b.id == family.id) ? family.id : _personal.id,
            )
            .distinct(),
      ),
    ],
  );
  await writeWhileShown(tester, () async {
    await SessionStore(h.values).save(_session);
    const user = SessionCurrentUser(pullUserId);
    final outbox = DriftOutboxQueue(h.db);
    await DriftBudgetsRepository(
      h.db,
      currentUser: user,
      outbox: outbox,
    ).applyFromServer([_personal, family]);
    final categories = DriftCategoriesRepository(
      h.db,
      currentUser: user,
      outbox: outbox,
    );
    await categories.applyFromServer(serverPresets(_personal.id));
    await categories.applyFromServer(serverPresets(family.id, firstSeq: 20));
  });
  await tester.pumpAndSettle();
  expect(find.byType(MonthScreen), findsOneWidget);
  expect(find.text('Семья'), findsWidgets);
  return h;
}

Future<int> _budgets(WidgetTester tester, AuthHarness h) async =>
    (await tester.runAsync(() => h.db.select(h.db.budgets).get()))!.length;

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testUnmounting('открыт общий «Семья», исключили: после «потянуть вниз» '
      'снекбар «Тебя исключили из бюджета «Семья»», показан личный', (
    tester,
  ) async {
    final h = await _openFamily(tester, serverShared());

    await _pullDown(tester);

    expect(find.text('Тебя исключили из бюджета «Семья»'), findsOneWidget);
    expect(find.byType(AppSnackbar), findsOneWidget);
    expect(await _budgets(tester, h), 1);
    expect(find.text(DriftBudgetsRepository.personalName), findsWidgets);
    expect(
      h.linesOf('month', Level.INFO),
      contains(
        endsWith(
          'budget removed notice #1 budgetId=budget-family kind=excluded → '
          'snackbar, personal budget shown',
        ),
      ),
    );
    expect(h.logs.text, isNot(contains('Семья')));
    expect(tester.takeException(), isNull);
  });

  testUnmounting('открыт свой общий «Семья», удалён с другого телефона: '
      'снекбар «Бюджет «Семья» удалён»', (tester) async {
    final h = await _openFamily(tester, serverShared(ownerId: pullUserId));

    await _pullDown(tester);

    expect(find.text('Бюджет «Семья» удалён'), findsOneWidget);
    expect(await _budgets(tester, h), 1);
    expect(tester.takeException(), isNull);
  });
}
