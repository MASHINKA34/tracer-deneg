import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/repositories/expenses_repository.dart';
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

  Future<Expense> createCoffee() => h.expenses.create(
    budgetId: b.id,
    categoryId: b.byName('Кафе').id,
    amount: const Money.rubles(640),
    spentOn: LocalDate(2026, 10, 20),
    comment: '  Ёлки, Кофе  ',
  );

  test(
    'создание: трата и одна запись outbox upsert с полной моделью',
    () async {
      final expense = await createCoffee();

      expect(expense.authorId, meId);
      expect(expense.updatedBy, meId);
      expect(expense.createdAt, h.clock);
      expect(expense.updatedAt, h.clock);
      expect(expense.comment, 'Ёлки, Кофе');
      expect(isUuid(expense.id), isTrue);

      final rows = await h.outboxRows();
      expect(rows, hasLength(1));
      final entry = rows.single;
      expect(entry.entity, SyncEntity.expense);
      expect(entry.entityId, expense.id);
      expect(entry.op, SyncOp.upsert);
      expect(entry.createdAt, h.clock);
      expect(entry.notBefore, isNull);
      expect(payloadOf(entry), expense.toJson());
      expect(Expense.fromJson(payloadOf(entry)), expense);

      expect(await h.expenses.watchById(expense.id).first, expense);
    },
  );

  test('колонка поиска комментария заполняется при записи', () async {
    final expense = await createCoffee();
    final row = await (h.db.select(
      h.db.expenses,
    )..where((e) => e.id.equals(expense.id))).getSingle();
    expect(row.commentSearch, 'елки, кофе');

    h.advance(const Duration(minutes: 1));
    await h.expenses.update(expense.id, comment: 'ПЯТЁРОЧКА');
    final updated = await (h.db.select(
      h.db.expenses,
    )..where((e) => e.id.equals(expense.id))).getSingle();
    expect(updated.comment, 'ПЯТЁРОЧКА');
    expect(updated.commentSearch, 'пятерочка');
  });

  test(
    'правка: одна запись upsert с новым updatedAt и полной моделью',
    () async {
      final created = await createCoffee();
      h.advance(const Duration(minutes: 3));

      final updated = await h.expenses.update(
        created.id,
        amount: const Money.rubles(700),
        categoryId: b.byName('Продукты').id,
      );

      expect(updated.amount, const Money.rubles(700));
      expect(updated.categoryId, b.byName('Продукты').id);
      expect(updated.updatedAt, h.clock);
      expect(updated.createdAt, created.createdAt);
      expect(updated.authorId, meId);

      final rows = await h.outboxRows();
      expect(rows, hasLength(2));
      expect(rows.last.op, SyncOp.upsert);
      expect(payloadOf(rows.last), updated.toJson());
    },
  );

  test(
    'несколько правок до отправки — записи по порядку, не схлопываются',
    () async {
      final created = await createCoffee();
      for (final rub in [100, 200, 300]) {
        h.advance(const Duration(seconds: 10));
        await h.expenses.update(created.id, amount: Money.rubles(rub));
      }
      final rows = await h.outboxRows();
      expect(rows.map((r) => r.entityId).toSet(), {created.id});
      expect(rows.map((r) => payloadOf(r)['amountKopecks']), [
        64000,
        10000,
        20000,
        30000,
      ]);
      expect(rows.map((r) => r.id).toList(), orderedEquals([1, 2, 3, 4]));
    },
  );

  test(
    'удаление: надгробие, запись delete без payload, в чтении не видна',
    () async {
      final created = await createCoffee();
      h.advance(const Duration(minutes: 1));

      final tombstone = await h.expenses.delete(created.id);

      expect(tombstone.deletedAt, h.clock);
      expect(tombstone.updatedAt, h.clock);
      final rows = await h.outboxRows();
      expect(rows, hasLength(2));
      final entry = rows.last;
      expect(entry.entity, SyncEntity.expense);
      expect(entry.entityId, created.id);
      expect(entry.op, SyncOp.delete);
      expect(entry.payload, isNull);
      expect(entry.createdAt, h.clock);
      expect(entry.notBefore, h.clock.add(expenseUndoWindow));

      final stored = await h.db.select(h.db.expenses).getSingle();
      expect(stored.deletedAt, h.clock);
      expect(await h.expenses.watchById(created.id).first, isNull);
      expect(await h.expenses.watchByBudget(b.id).first, isEmpty);
    },
  );

  test('чтение бюджета — только живые траты своего бюджета', () async {
    final other = await h.seedBudget();
    final kept = await createCoffee();
    final removed = await createCoffee();
    await h.expenses.create(
      budgetId: other.id,
      categoryId: other.byName('Кафе').id,
      amount: const Money.rubles(1),
      spentOn: LocalDate(2026, 10, 20),
    );
    await h.expenses.delete(removed.id);
    await h.expenses.applyFromServer([
      Expense(
        id: 'server-dead',
        budgetId: b.id,
        categoryId: b.other.id,
        amount: const Money.rubles(5),
        spentOn: LocalDate(2026, 10, 19),
        authorId: serverUserId,
        createdAt: h.clock,
        updatedAt: h.clock,
        updatedBy: serverUserId,
        deletedAt: h.clock,
        seq: 7,
      ),
    ]);

    final live = await h.expenses.watchByBudget(b.id).first;
    expect(live.map((e) => e.id), [kept.id]);
  });

  test('правка и удаление удалённой или чужой траты — not_found, ничего не пишется', () async {
    final created = await createCoffee();
    await h.expenses.delete(created.id);
    final before = await h.rowCounts();

    for (final action in <Future<Object?> Function()>[
      () => h.expenses.update(created.id, amount: const Money.rubles(1)),
      () => h.expenses.delete(created.id),
      () => h.expenses.update('missing', amount: const Money.rubles(1)),
    ]) {
      await expectLater(
        action(),
        throwsA(
          isA<RepositoryException>().having(
            (e) => e.failure,
            'failure',
            RepositoryFailure.notFound,
          ),
        ),
      );
    }
    expect(await h.rowCounts(), before);
  });

  test(
    'ошибка валидации — исключение домена с кодом, ничего не пишется',
    () async {
      final created = await createCoffee();
      final before = await h.rowCounts();

      Matcher validation(ValidationError error) => throwsA(
        isA<RepositoryException>()
            .having((e) => e.failure, 'failure', RepositoryFailure.validation)
            .having((e) => e.validation, 'validation', error)
            .having((e) => e.code, 'code', error.code),
      );

      await expectLater(
        h.expenses.create(
          budgetId: b.id,
          categoryId: b.other.id,
          amount: Money.zero,
          spentOn: LocalDate(2026, 10, 20),
        ),
        validation(ValidationError.amountEmpty),
      );
      await expectLater(
        h.expenses.create(
          budgetId: b.id,
          categoryId: b.other.id,
          amount: const Money(maxExpenseKopecks + 1),
          spentOn: LocalDate(2026, 10, 20),
        ),
        validation(ValidationError.amountTooLarge),
      );
      await expectLater(
        h.expenses.create(
          budgetId: b.id,
          categoryId: b.other.id,
          amount: const Money.rubles(1),
          spentOn: LocalDate(2026, 10, 20),
          comment: 'я' * 101,
        ),
        validation(ValidationError.commentTooLong),
      );
      await expectLater(
        h.expenses.update(created.id, amount: const Money(-5)),
        validation(ValidationError.amountNegative),
      );

      expect(await h.rowCounts(), before);
      expect(
        (await h.expenses.watchById(created.id).first)!.amount.kopecks,
        64000,
      );
    },
  );

  test(
    'сбой записи в очередь откатывает трату: ни траты, ни outbox; error в логе',
    () async {
      await h.db.customStatement(
        'CREATE TRIGGER outbox_broken BEFORE INSERT ON outbox '
        "BEGIN SELECT RAISE(ABORT, 'outbox is broken'); END",
      );

      await expectLater(
        createCoffee(),
        throwsA(isNot(isA<RepositoryException>())),
      );

      expect(await h.db.select(h.db.expenses).get(), isEmpty);
      expect(await h.outboxRows(), isEmpty);
      final errors = h.repoLogs(Level.SEVERE);
      expect(errors, hasLength(1));
      expect(
        errors.single.message,
        matches(
          RegExp(
            r'^expense create failed id=[0-9a-f-]{36} after \d+ms, '
            r'transaction rolled back: SqliteException.*outbox is broken',
          ),
        ),
      );
      expect(errors.single.stackTrace, isNotNull);
      expect(errors.single.error, isNotNull);
    },
  );

  test('применение с сервера пишет трату без записи в outbox', () async {
    final created = await createCoffee();
    await h.outbox.remove((await h.outboxRows()).map((r) => r.id));

    final fromServer = created.copyWith(
      amount: const Money.rubles(999),
      comment: 'С сервера',
      updatedAt: h.clock.add(const Duration(minutes: 5)),
      updatedBy: serverUserId,
      seq: 42,
    );
    await h.expenses.applyFromServer([fromServer]);

    expect(await h.outboxRows(), isEmpty);
    expect(await h.expenses.watchById(created.id).first, fromServer);
    final row = await h.db.select(h.db.expenses).getSingle();
    expect(row.serverSeq, 42);
    expect(row.commentSearch, 'с сервера');
  });
}
