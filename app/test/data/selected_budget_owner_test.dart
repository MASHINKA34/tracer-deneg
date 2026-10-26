import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/current_user.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/repositories/budgets_repository.dart';
import 'package:milionchik/data/repositories/expenses_repository.dart';
import 'package:milionchik/data/repositories/outbox_queue.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:milionchik/data/session/session.dart';
import 'package:milionchik/data/session/session_providers.dart';
import 'package:milionchik/data/session/session_state.dart';
import 'package:milionchik/features/export/export_budget_sheet.dart';
import 'package:shared/shared.dart';

import 'provider_harness.dart';
import 'sync/pull_fixture.dart';

const _user = SessionUser(
  userId: pullUserId,
  login: 'anya_m',
  displayName: 'Аня',
);

void main() {
  test('после входа выбран личный бюджет вошедшего, а не созданный на '
      'телефоне до входа; тот скрыт, но его траты и outbox на месте', () async {
    final h = ProviderHarness(
      overrides: [
        sessionProvider.overrideWithBuild(
          (ref, _) => const SessionActive(_user),
        ),
      ],
    );
    final before = await DriftBudgetsRepository(
      h.db,
      currentUser: LocalPrefsCurrentUser(DriftPrefsRepository(h.db)),
      outbox: DriftOutboxQueue(h.db),
      now: () => DateTime.utc(2026, 10, 19, 8),
    ).createLocalPersonal();
    final localUser = LocalPrefsCurrentUser(DriftPrefsRepository(h.db));
    final category = (await h.db.select(h.db.categories).get()).first;
    final spent =
        await DriftExpensesRepository(
          h.db,
          currentUser: localUser,
          outbox: DriftOutboxQueue(h.db),
        ).create(
          budgetId: before.id,
          categoryId: category.id,
          amount: Money(25000),
          spentOn: LocalDate(2026, 10, 19),
        );
    final outboxBefore = await h.read(outboxQueueProvider).count();
    expect(outboxBefore, 13);
    final selected = h.watch(selectedBudgetIdProvider);
    expect(await selected.data(), isNull);

    final server = serverPersonal(createdAt: DateTime.utc(2026, 10, 21, 8));
    await h.read(budgetsRepositoryProvider).applyFromServer([
      server,
      serverShared(),
    ]);

    expect(await selected.data((id) => id != null), server.id);
    expect(
      before.createdAt.isBefore(server.createdAt),
      isTrue,
      reason: 'the hidden budget is older: order alone would pick it',
    );
    final exported = h.watch(exportBudgetsProvider);
    expect(
      [for (final b in await exported.data((list) => list.length == 2)) b.id],
      [server.id, 'budget-family'],
    );
    expect(await h.read(outboxQueueProvider).count(), outboxBefore);
    final rows = await h.db
        .customSelect(
          'SELECT id FROM budgets WHERE id = ?',
          variables: [Variable.withString(before.id)],
        )
        .get();
    expect(rows, hasLength(1));
    final expense = await h
        .read(expensesRepositoryProvider)
        .watchById(spent.id)
        .first;
    expect(expense?.budgetId, before.id);
    expect(
      h.lines('budgets', Level.INFO),
      containsAllInOrder([
        endsWith(
          'selected budget: none, no personal budget of userId=$pullUserId '
          'yet (comes with the first pull) hiddenPersonal=1 (personal budgets '
          'of another owner, e.g. made on this phone before sign-in: kept in '
          'the database, not shown)',
        ),
        contains(
          'selected budget budgetId=${server.id} reason=personal '
          'userId=$pullUserId hiddenPersonal=1',
        ),
      ]),
    );
  });

  test(
    'без входа (демо-данные): выбран первый личный бюджет, как раньше',
    () async {
      final h = ProviderHarness();
      final selected = h.watch(selectedBudgetIdProvider);
      await h.read(budgetsRepositoryProvider).applyFromServer([
        serverPersonal(ownerId: 'user-someone'),
      ]);

      expect(await selected.data((id) => id != null), 'budget-personal');
      expect(
        [for (final b in await h.watch(exportBudgetsProvider).data()) b.id],
        ['budget-personal'],
      );
    },
  );
}
