import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/data/current_user.dart';
import 'package:milionchik/data/queries/budget_queries.dart';
import 'package:milionchik/data/repositories/expenses_repository.dart';
import 'package:milionchik/data/repositories/outbox_queue.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:shared/shared.dart';

import '../../features/budgets/budget_screen_fixture.dart';
import '../../features/profile/profile_fixture.dart';
import '../../support/app_scope.dart';
import '../api/fake_api_adapter.dart';

void main() {
  late LogCapture logs;

  setUp(() => logs = LogCapture());

  tearDown(() => logs.dispose());

  Expense expense(
    String id, {
    required String budgetId,
    required LocalDate day,
    DateTime? deletedAt,
  }) => Expense(
    id: id,
    budgetId: budgetId,
    categoryId: BudgetScreenFixture.category(0),
    amount: Money(99900),
    spentOn: day,
    authorId: dimaId,
    createdAt: DateTime(2026, 10, 19, 20).toUtc(),
    updatedAt: DateTime(2026, 10, 19, 20).toUtc(),
    updatedBy: dimaId,
    deletedAt: deletedAt,
  );

  test('последние траты бюджета: по дате, затем по времени записи, не больше '
      'limit; удалённые и траты других бюджетов не попадают; в логе бюджет, '
      'limit и число строк', () async {
    final db = openTestDatabase();
    await BudgetScreenFixture.seed(db, owner: true);
    await BudgetScreenFixture.addExpenses(db, 4);
    await DriftExpensesRepository(
      db,
      currentUser: LocalPrefsCurrentUser(DriftPrefsRepository(db)),
      outbox: DriftOutboxQueue(db),
    ).applyFromServer([
      expense(
        'expense-deleted',
        budgetId: familyId,
        day: LocalDate(2026, 10, 19),
        deletedAt: DateTime(2026, 10, 19, 21).toUtc(),
      ),
      expense(
        'expense-personal',
        budgetId: profilePersonalId,
        day: LocalDate(2026, 10, 19),
      ),
    ]);
    final queries = DriftBudgetQueries(db);

    final recent = await queries.watchRecentExpenses(familyId, limit: 5).first;

    expect(
      [for (final e in recent) e.id],
      [
        'expense-food',
        'expense-home',
        'expense-health',
        'expense-extra-3',
        'expense-extra-2',
      ],
    );
    expect(
      [
        for (final e
            in await queries.watchRecentExpenses(familyId, limit: 2).first)
          e.id,
      ],
      ['expense-food', 'expense-home'],
    );
    expect(
      logs.linesOf('query'),
      contains(
        matches(
          'query recent expenses (slow )?budget=$familyId limit=5 rows=5 '
          'trigger=listen in \\d+ms',
        ),
      ),
    );
    expect(logs.text, isNot(contains('Лента')));
  });
}
