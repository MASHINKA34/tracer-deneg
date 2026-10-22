import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/recurring_service.dart';
import 'package:shared/shared.dart';

import 'recurring_harness.dart';

void main() {
  late RecurringHarness r;

  setUp(() async => r = await RecurringHarness().seed());

  tearDown(() => r.dispose());

  Future<void> expectNoDuplicates(String ruleId, int count) async {
    final expenses = await r.expensesOf(ruleId);
    expect(expenses, hasLength(count));
    expect(expenses.map((e) => e.id).toSet(), hasLength(count));
    final upserts = [
      for (final row in await r.repo.outboxRows())
        if (row.entity == SyncEntity.expense) row.entityId,
    ];
    expect(upserts, [for (final e in expenses) e.id]);
    expect(r.logs('recurring', Level.WARNING), isEmpty);
    expect(r.logs('repo', Level.WARNING), isEmpty);
  }

  test('два одновременных запуска одного сервиса: второй ждёт первый и '
      'ничего не создаёт', () async {
    final rule = await r.rule(day: 5, from: YearMonth(2026, 8));

    final results = await Future.wait([
      r.run(RecurringRunReason.startup),
      r.run(RecurringRunReason.dayChanged),
    ]);

    expect(results.map((x) => x.created), [3, 0]);
    expect(results.last.skippedExisting, 3);
    await expectNoDuplicates(rule.id, 3);
    expect(
      r.lines('recurring'),
      contains(endsWith('run (day changed) queued behind 1 unfinished run(s)')),
    );
  });

  test('одновременные запуски двух экземпляров на одной базе (провайдер '
      'пересоздан, хук синхронизации, фон) — без дублей', () async {
    final rule = await r.rule(day: 5, from: YearMonth(2026, 7));
    final other = r.newService();
    final background = RecurringService.forDatabase(r.repo.db, clock: r.clock);

    final results = await Future.wait([
      r.service.run(RecurringRunReason.startup),
      other.afterSync(),
      background.forBackground(),
    ]);

    expect(results.map((x) => x.created).reduce((a, b) => a + b), 4);
    expect(results.map((x) => x.created), [4, 0, 0]);
    expect(results.every((x) => x.ok), isTrue);
    await expectNoDuplicates(rule.id, 4);
  });
}
