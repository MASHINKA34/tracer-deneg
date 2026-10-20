import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/data/repositories/repository_errors.dart';
import 'package:shared/shared.dart';

import 'repository_harness.dart';

void main() {
  late RepositoryHarness h;
  late SeededBudget b;

  setUp(() async {
    h = RepositoryHarness();
    b = await h.seedBudget();
  });

  tearDown(() => h.dispose());

  Future<Expense> spend(String categoryId, {String? budgetId}) =>
      h.expenses.create(
        budgetId: budgetId ?? b.id,
        categoryId: categoryId,
        amount: const Money.rubles(100),
        spentOn: LocalDate(2026, 10, 20),
      );

  Future<RecurringRule> rule(String categoryId) => h.recurring.create(
    budgetId: b.id,
    categoryId: categoryId,
    title: 'Абонемент',
    amount: const Money.rubles(2500),
    dayOfMonth: 5,
    startMonth: YearMonth(2026, 11),
  );

  Matcher failure(RepositoryFailure f) => throwsA(
    isA<RepositoryException>().having((e) => e.failure, 'failure', f),
  );

  test(
    'траты и регулярные переходят в «Другое», категория — надгробие',
    () async {
      final sport = b.byName('Спорт');
      final e1 = await spend(sport.id);
      final e2 = await spend(sport.id);
      final untouched = await spend(b.byName('Кафе').id);
      final r1 = await rule(sport.id);
      final queued = (await h.outboxRows()).length;
      h.advance(const Duration(minutes: 2));

      final deletion = await h.categories.delete(sport.id);

      expect(deletion.movedExpenses, 2);
      expect(deletion.movedRecurring, 1);
      expect(deletion.otherCategoryId, b.other.id);
      expect(deletion.category.deletedAt, h.clock);

      final live = await h.expenses.watchByBudget(b.id).first;
      final byId = {for (final e in live) e.id: e};
      expect(byId[e1.id]!.categoryId, b.other.id);
      expect(byId[e2.id]!.categoryId, b.other.id);
      expect(byId[e1.id]!.updatedAt, h.clock);
      expect(byId[e1.id]!.updatedBy, meId);
      expect(byId[untouched.id]!.categoryId, b.byName('Кафе').id);
      final rules = await h.recurring.watchByBudget(b.id).first;
      expect(rules.single.id, r1.id);
      expect(rules.single.categoryId, b.other.id);

      final categories = await h.categories.watchByBudget(b.id).first;
      expect(categories.map((c) => c.id), isNot(contains(sport.id)));
      expect(await h.categories.watchById(sport.id).first, isNull);

      final added = (await h.outboxRows()).skip(queued).toList();
      expect(
        [for (final r in added) '${r.entity.name}:${r.op.name}:${r.entityId}'],
        [
          'expense:upsert:${e1.id}',
          'expense:upsert:${e2.id}',
          'recurring:upsert:${r1.id}',
          'category:delete:${sport.id}',
        ],
      );
      expect(payloadOf(added[0]), byId[e1.id]!.toJson());
      expect(payloadOf(added[2]), rules.single.toJson());
      expect(added.last.payload, isNull);
      expect(added.last.notBefore, isNull);
    },
  );

  test('удалённые траты и чужой бюджет не переносятся', () async {
    final sport = b.byName('Спорт');
    final deleted = await spend(sport.id);
    await h.expenses.delete(deleted.id);
    final otherBudget = await h.seedBudget();
    final foreign = await spend(
      otherBudget.byName('Спорт').id,
      budgetId: otherBudget.id,
    );

    final deletion = await h.categories.delete(sport.id);

    expect(deletion.movedExpenses, 0);
    final row = await (h.db.select(
      h.db.expenses,
    )..where((e) => e.id.equals(deleted.id))).getSingle();
    expect(row.categoryId, sport.id);
    expect(
      (await h.expenses.watchById(foreign.id).first)!.categoryId,
      otherBudget.byName('Спорт').id,
    );
  });

  test('«Другое» нельзя удалить и переименовать — ошибка домена, ничего не пишется', () async {
    final before = await h.rowCounts();

    await expectLater(
      h.categories.delete(b.other.id),
      failure(RepositoryFailure.systemCategory),
    );
    await expectLater(
      h.categories.update(b.other.id, name: 'Прочее'),
      failure(RepositoryFailure.systemCategory),
    );
    await expectLater(
      h.categories.update(b.other.id, emoji: '🧺'),
      failure(RepositoryFailure.systemCategory),
    );

    expect(await h.rowCounts(), before);
    expect(await h.categories.watchById(b.other.id).first, b.other);
  });

  test(
    'без «Другое» в бюджете удаление отклоняется и ничего не меняет',
    () async {
      final sport = b.byName('Спорт');
      final expense = await spend(sport.id);
      await h.categories.applyFromServer([
        b.other.copyWith(deletedAt: h.clock, updatedAt: h.clock),
      ]);
      final before = await h.rowCounts();

      await expectLater(
        h.categories.delete(sport.id),
        failure(RepositoryFailure.otherCategoryMissing),
      );

      expect(await h.rowCounts(), before);
      expect(
        (await h.expenses.watchById(expense.id).first)!.categoryId,
        sport.id,
      );
      expect(await h.categories.watchById(sport.id).first, isNotNull);
    },
  );

  test('удалённую категорию повторно удалить нельзя — not_found', () async {
    final sport = b.byName('Спорт');
    await h.categories.delete(sport.id);
    await expectLater(
      h.categories.delete(sport.id),
      failure(RepositoryFailure.notFound),
    );
  });
}
