import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/queries/recurring_queries.dart';
import 'package:shared/shared.dart';

import '../recurring/recurring_harness.dart';
import 'query_fixture.dart' show Watcher;

final YearMonth _october = YearMonth(2026, 10);

void main() {
  late RecurringHarness r;
  late DriftRecurringQueries queries;

  setUp(() async {
    r = await RecurringHarness().seed();
    r.today = LocalDate(2026, 10, 19);
    queries = DriftRecurringQueries(r.repo.db);
  });

  tearDown(() => r.dispose());

  test('19 октября: траты октября есть у правил на 3, 7 и 12 число, у правил '
      'на 24 и 28 — нет; ключ — id правила', () async {
    final rules = {
      for (final day in [3, 7, 12, 24, 28])
        day: await r.rule(day: day, from: _october),
    };
    expect((await r.run()).created, 3);

    final charges = await queries
        .watchMonthCharges(r.budget.id, _october)
        .first;

    expect(charges.keys.toSet(), {rules[3]!.id, rules[7]!.id, rules[12]!.id});
    expect(
      [
        for (final day in [3, 7, 12]) charges[rules[day]!.id]!.spentOn,
      ],
      [_october.dayOf(3), _october.dayOf(7), _october.dayOf(12)],
    );
    expect(
      charges[rules[3]!.id]!.id,
      recurringExpenseId(rules[3]!.id, _october),
    );
  });

  test('удалённая трата месяца, трата сентября, правило другого бюджета и '
      'обычная трата не попадают', () async {
    final kept = await r.rule(day: 7, from: YearMonth(2026, 9));
    final deleted = await r.rule(day: 3, from: _october);
    final other = await r.repo.seedBudget(id: 'budget-other');
    final foreign = await r.repo.recurring.create(
      budgetId: other.id,
      categoryId: other.byName('Связь').id,
      title: 'Чужая',
      amount: const Money.rubles(500),
      dayOfMonth: 5,
      startMonth: _october,
    );
    await r.run();
    await r.repo.expenses.delete(recurringExpenseId(deleted.id, _october));
    await r.repo.expenses.create(
      budgetId: r.budget.id,
      categoryId: r.budget.byName('Связь').id,
      amount: const Money.rubles(300),
      spentOn: _october.dayOf(10),
    );

    final october = await queries
        .watchMonthCharges(r.budget.id, _october)
        .first;
    final september = await queries
        .watchMonthCharges(r.budget.id, YearMonth(2026, 9))
        .first;
    final foreignOctober = await queries
        .watchMonthCharges(other.id, _october)
        .first;

    expect(october.keys, [kept.id]);
    expect(october[kept.id]!.recurringMonth, _october);
    expect(september.keys, [kept.id]);
    expect(september[kept.id]!.spentOn, LocalDate(2026, 9, 7));
    expect(foreignOctober.keys, [foreign.id]);
  });

  test('генератор создал трату — поток сразу отдаёт её; удалили — '
      'пропадает; в debug [query] имя, бюджет, месяц и число строк', () async {
    final rule = await r.rule(day: 19, from: _october);
    final watcher = Watcher(queries.watchMonthCharges(r.budget.id, _october));
    addTearDown(watcher.cancel);

    final before = await watcher.next();
    await r.run();
    final generated = await watcher.next();
    await r.repo.expenses.delete(recurringExpenseId(rule.id, _october));
    final removed = await watcher.next();

    expect(before, isEmpty);
    expect(generated.keys, [rule.id]);
    expect(removed, isEmpty);
    expect(
      r.lines('query', Level.FINE),
      contains(
        matches(
          'DEBUG \\[query\\] query recurring charges '
          'budget=${r.budget.id} month=2026-10 rows=1 trigger=change '
          'in \\d+ms',
        ),
      ),
    );
  });
}
