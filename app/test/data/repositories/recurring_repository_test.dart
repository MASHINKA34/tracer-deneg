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

  Future<RecurringRule> create({int day = 24}) => h.recurring.create(
    budgetId: b.id,
    categoryId: b.byName('Связь').id,
    title: ' Интернет ',
    amount: const Money.rubles(650),
    dayOfMonth: day,
    startMonth: YearMonth(2026, 10),
  );

  test('создание: правило и одна запись upsert с полной моделью', () async {
    final rule = await create();

    expect(rule.title, 'Интернет');
    expect(rule.createdAt, h.clock);
    expect(rule.updatedAt, h.clock);
    expect(rule.updatedBy, meId);
    expect(await h.recurring.watchById(rule.id).first, rule);

    final rows = await h.outboxRows();
    expect(rows, hasLength(1));
    expect(rows.single.entity, SyncEntity.recurring);
    expect(rows.single.op, SyncOp.upsert);
    expect(payloadOf(rows.single), rule.toJson());
  });

  test('правка: одна запись upsert', () async {
    final rule = await create();
    h.advance(const Duration(days: 1));
    final updated = await h.recurring.update(
      rule.id,
      amount: const Money.rubles(700),
      dayOfMonth: 31,
    );
    expect(updated.amount, const Money.rubles(700));
    expect(updated.dayOfMonth, 31);
    expect(updated.title, rule.title);
    expect(updated.updatedAt, h.clock);

    final rows = await h.outboxRows();
    expect(rows, hasLength(2));
    expect(payloadOf(rows.last), updated.toJson());
  });

  test('удаление: надгробие, одна запись delete, в чтении не видно', () async {
    final rule = await create();
    final tombstone = await h.recurring.delete(rule.id);

    expect(tombstone.deletedAt, h.clock);
    final rows = await h.outboxRows();
    expect(rows, hasLength(2));
    expect(rows.last.op, SyncOp.delete);
    expect(rows.last.entityId, rule.id);
    expect(rows.last.payload, isNull);
    expect(rows.last.notBefore, isNull);
    expect(await h.recurring.watchById(rule.id).first, isNull);
    expect(await h.recurring.watchByBudget(b.id).first, isEmpty);
  });

  test('чтение по дню списания', () async {
    final later = await create(day: 28);
    final early = await create(day: 3);
    expect((await h.recurring.watchByBudget(b.id).first).map((r) => r.id), [
      early.id,
      later.id,
    ]);
  });

  test('ошибка валидации — ничего не пишется', () async {
    final rule = await create();
    final before = await h.rowCounts();
    Matcher invalid(ValidationError e) => throwsA(
      isA<RepositoryException>().having((x) => x.validation, 'validation', e),
    );

    await expectLater(
      create(day: 0),
      invalid(ValidationError.dayOfMonthInvalid),
    );
    await expectLater(
      create(day: 32),
      invalid(ValidationError.dayOfMonthInvalid),
    );
    await expectLater(
      h.recurring.update(rule.id, title: ' '),
      invalid(ValidationError.recurringTitleEmpty),
    );
    await expectLater(
      h.recurring.update(rule.id, title: 'я' * 41),
      invalid(ValidationError.recurringTitleTooLong),
    );
    await expectLater(
      h.recurring.update(rule.id, amount: Money.zero),
      invalid(ValidationError.amountEmpty),
    );

    expect(await h.rowCounts(), before);
  });

  test('применение с сервера без записи в outbox', () async {
    final rule = RecurringRule(
      id: 'rule-server',
      budgetId: b.id,
      categoryId: b.other.id,
      title: 'Аренда',
      amount: const Money.rubles(30000),
      dayOfMonth: 1,
      startMonth: YearMonth(2026, 9),
      createdAt: h.clock,
      updatedAt: h.clock,
      updatedBy: serverUserId,
      seq: 5,
    );
    await h.recurring.applyFromServer([rule]);
    expect(await h.recurring.watchById(rule.id).first, rule);
    expect(await h.outboxRows(), isEmpty);
  });
}
