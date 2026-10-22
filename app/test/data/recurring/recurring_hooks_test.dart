import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/recurring_service.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:shared/shared.dart';

import 'recurring_harness.dart';

void main() {
  late RecurringHarness r;

  setUp(() async => r = await RecurringHarness().seed());

  tearDown(() => r.dispose());

  test('afterSync: правило пришло синхронизацией — трата создаётся, причина '
      '«after sync»', () async {
    final at = DateTime.utc(2026, 10, 1, 7);
    final rule = RecurringRule(
      id: 'rule-from-server',
      budgetId: r.budget.id,
      categoryId: r.budget.byName('Связь').id,
      title: internetTitle,
      amount: const Money.rubles(650),
      dayOfMonth: 3,
      startMonth: YearMonth(2026, 10),
      createdAt: at,
      updatedAt: at,
      updatedBy: serverUserId,
      seq: 41,
    );
    await r.repo.recurring.applyFromServer([rule]);

    final result = await r.service.afterSync();

    expect(result.reason, RecurringRunReason.afterSync);
    expect(result.created, 1);
    expect(
      (await r.expensesOf(rule.id)).single.id,
      recurringExpenseId(rule.id, YearMonth(2026, 10)),
    );
    expect(
      r.lines('recurring', Level.INFO).single,
      matches(
        RegExp(
          r'INFO  \[recurring\] run \(after sync\) today=2026-10-22 rules=1 '
          r'created=1 skipped=0 existing=0 deleted=0 in \d+ms$',
        ),
      ),
    );
  });

  test('forBackground на базе без провайдеров: автор — локальный '
      'пользователь, outbox, причина «background»', () async {
    final rule = await r.rule(day: 22, from: YearMonth(2026, 10));
    final localUser = await DriftPrefsRepository(r.repo.db)
        .putStringIfAbsent(PrefKeys.localUserId, () => 'user-local');

    final background = RecurringService.forDatabase(r.repo.db, clock: r.clock);
    final result = await background.forBackground();

    expect(result.reason, RecurringRunReason.background);
    expect(result.today, LocalDate(2026, 10, 22));
    expect(result.created, 1);
    expect(result.ok, isTrue);
    final expense = (await r.expensesOf(rule.id)).single;
    expect(expense.spentOn, LocalDate(2026, 10, 22));
    expect(expense.authorId, localUser);
    final upserts = [
      for (final row in await r.repo.outboxRows())
        if (row.entityId == expense.id) row.op,
    ];
    expect(upserts, [SyncOp.upsert]);
    expect(
      r.lines('recurring', Level.INFO).single,
      contains('run (background) today=2026-10-22 rules=1 created=1'),
    );

    final again = await r.service.afterSync();
    expect(again.created, 0);
    expect(again.skippedExisting, 1);
  });
}
