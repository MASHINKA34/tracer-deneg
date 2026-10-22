import 'package:flutter_test/flutter_test.dart';
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

  Future<RecurringRule> create() => h.recurring.create(
    budgetId: b.id,
    categoryId: b.byName('Связь').id,
    title: 'Спортзал',
    amount: const Money.rubles(2500),
    dayOfMonth: 5,
    startMonth: YearMonth(2026, 10),
  );

  test('живое правило: отдаётся с названием и без deletedAt', () async {
    final rule = await create();

    final seen = await h.recurring.watchByIdWithDeleted(rule.id).first;

    expect(seen, rule);
    expect(seen!.title, 'Спортзал');
    expect(seen.deletedAt, isNull);
  });

  test('удалённое правило: watchById молчит, а watchByIdWithDeleted отдаёт '
      'его с названием и deletedAt', () async {
    final rule = await create();
    h.advance(const Duration(days: 1));
    final tombstone = await h.recurring.delete(rule.id);

    expect(await h.recurring.watchById(rule.id).first, isNull);
    final seen = await h.recurring.watchByIdWithDeleted(rule.id).first;
    expect(seen, tombstone);
    expect(seen!.title, 'Спортзал');
    expect(seen.deletedAt, h.clock);
  });

  test('правила нет на телефоне: null', () async {
    expect(await h.recurring.watchByIdWithDeleted(newId()).first, isNull);
  });

  test('подписка видит удаление правила, пока открыта', () async {
    final rule = await create();
    final seen = <RecurringRule?>[];
    final sub = h.recurring.watchByIdWithDeleted(rule.id).listen(seen.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();

    await h.recurring.delete(rule.id);
    await pumpEventQueue();

    expect([for (final r in seen) r?.deletedAt != null], [false, true]);
    expect(seen.last!.title, 'Спортзал');
  });

  test('удалённое правило с сервера: отдаётся с deletedAt', () async {
    final at = DateTime.utc(2026, 10, 1, 7);
    final rule = RecurringRule(
      id: newId(),
      budgetId: b.id,
      categoryId: b.byName('Связь').id,
      title: 'Спортзал',
      amount: const Money.rubles(2500),
      dayOfMonth: 5,
      startMonth: YearMonth(2026, 10),
      createdAt: at,
      updatedAt: at,
      updatedBy: meId,
      deletedAt: at,
      seq: 4,
    );
    await h.recurring.applyFromServer([rule]);

    expect(await h.recurring.watchById(rule.id).first, isNull);
    expect(
      (await h.recurring.watchByIdWithDeleted(rule.id).first)?.deletedAt,
      at,
    );
  });
}
