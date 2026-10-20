import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/repositories/repository_errors.dart';
import 'package:shared/shared.dart';

import 'repository_harness.dart';

void main() {
  late RepositoryHarness h;
  late SeededBudget personal;

  setUp(() async {
    h = RepositoryHarness();
    personal = await h.seedBudget(id: 'b-personal');
  });

  tearDown(() => h.dispose());

  BudgetMember member(String budgetId, String userId) => BudgetMember(
    budgetId: budgetId,
    userId: userId,
    role: userId == meId ? MemberRole.owner : MemberRole.member,
    avatarColor: CategoryColor.blue,
    joinedAt: DateTime.utc(2026, 10, 1),
  );

  test('чтение: живые бюджеты, личный первым', () async {
    final shared = await h.seedBudget(id: 'b-shared', kind: BudgetKind.shared);
    await h.budgets.applyFromServer([
      Budget(
        id: 'b-dead',
        kind: BudgetKind.shared,
        name: 'Старый',
        emoji: '🗑',
        ownerId: meId,
        createdAt: h.clock,
        updatedAt: h.clock,
        updatedBy: serverUserId,
        deletedAt: h.clock,
      ),
    ]);

    final all = await h.budgets.watchAll().first;
    expect(all.map((b) => b.id), [personal.id, shared.id]);
    expect(await h.budgets.watchById('b-dead').first, isNull);
    expect(await h.budgets.watchById(personal.id).first, personal.budget);
    expect(await h.outboxRows(), isEmpty);
  });

  test('правка названия и эмодзи: одна запись upsert', () async {
    h.advance(const Duration(hours: 1));
    final updated = await h.budgets.update(
      personal.id,
      name: ' Мой ',
      emoji: '🏦',
    );

    expect(updated.name, 'Мой');
    expect(updated.emoji, '🏦');
    expect(updated.updatedAt, h.clock);
    expect(updated.updatedBy, meId);
    expect(updated.ownerId, personal.budget.ownerId);
    expect(updated.seq, personal.budget.seq);

    final rows = await h.outboxRows();
    expect(rows, hasLength(1));
    expect(rows.single.entity, SyncEntity.budget);
    expect(rows.single.op, SyncOp.upsert);
    expect(payloadOf(rows.single), updated.toJson());
  });

  test(
    'правка с ошибкой валидации и неизвестного бюджета — ничего не пишется',
    () async {
      final before = await h.rowCounts();
      await expectLater(
        h.budgets.update(personal.id, name: 'я' * 31),
        throwsA(
          isA<RepositoryException>().having(
            (e) => e.validation,
            'validation',
            ValidationError.budgetNameTooLong,
          ),
        ),
      );
      await expectLater(
        h.budgets.update('missing', name: 'Новый'),
        throwsA(
          isA<RepositoryException>().having(
            (e) => e.failure,
            'failure',
            RepositoryFailure.notFound,
          ),
        ),
      );
      expect(await h.rowCounts(), before);
    },
  );

  test(
    'очистка по removedBudgetIds удаляет данные бюджета и его записи outbox',
    () async {
      final shared = await h.seedBudget(
        id: 'b-shared',
        kind: BudgetKind.shared,
      );
      await h.members.applyMembersFromServer([
        member(shared.id, meId),
        member(shared.id, 'user-friend'),
        member(personal.id, meId),
      ]);
      final sharedExpense = await h.expenses.create(
        budgetId: shared.id,
        categoryId: shared.byName('Кафе').id,
        amount: const Money.rubles(300),
        spentOn: LocalDate(2026, 10, 20),
      );
      await h.recurring.create(
        budgetId: shared.id,
        categoryId: shared.other.id,
        title: 'Аренда',
        amount: const Money.rubles(30000),
        dayOfMonth: 1,
        startMonth: YearMonth(2026, 11),
      );
      await h.categories.create(
        budgetId: shared.id,
        name: 'Дача',
        emoji: '🌻',
        color: CategoryColor.green,
      );
      await h.budgets.update(shared.id, name: 'Семья');
      final personalExpense = await h.expenses.create(
        budgetId: personal.id,
        categoryId: personal.byName('Кафе').id,
        amount: const Money.rubles(100),
        spentOn: LocalDate(2026, 10, 20),
      );

      final removal = await h.budgets.removeBudgetData([shared.id]);

      expect(removal.budgets, 1);
      expect(removal.members, 2);
      expect(removal.categories, 12);
      expect(removal.expenses, 1);
      expect(removal.recurring, 1);
      expect(removal.outbox, 4);

      expect(await h.budgets.watchAll().first, [personal.budget]);
      expect(await h.expenses.watchById(sharedExpense.id).first, isNull);
      expect((await h.db.select(h.db.expenses).get()).map((e) => e.id), [
        personalExpense.id,
      ]);
      expect(
        (await h.db.select(h.db.categories).get())
            .map((c) => c.budgetId)
            .toSet(),
        {personal.id},
      );
      expect(await h.db.select(h.db.recurringRules).get(), isEmpty);
      expect(await h.members.watchByBudget(shared.id).first, isEmpty);
      expect(await h.members.watchByBudget(personal.id).first, hasLength(1));
      final rows = await h.outboxRows();
      expect(rows.map((r) => r.entityId), [personalExpense.id]);

      expect(
        h.repoLogs(Level.INFO).map((r) => r.message),
        contains(
          matches(
            RegExp(
              r'^budget data removed ids=b-shared budgets=1 members=2 '
              r'categories=12 expenses=1 recurring=1 outbox=4 in \d+ms$',
            ),
          ),
        ),
      );
    },
  );
}
