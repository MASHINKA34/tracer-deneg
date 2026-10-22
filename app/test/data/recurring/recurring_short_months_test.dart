import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

import 'recurring_harness.dart';

void main() {
  late RecurringHarness r;

  setUp(() async => r = await RecurringHarness().seed());

  tearDown(() => r.dispose());

  test('правило на 31-е, обычный год: 27 февраля 2026 — февральской траты '
      'ещё нет, 28 февраля — трата 28-го', () async {
    final rule = await r.rule(day: 31, from: YearMonth(2026, 1));

    r.today = LocalDate(2026, 2, 27);
    final early = await r.run();
    expect(early.created, 1);
    expect((await r.expensesOf(rule.id)).map((e) => e.spentOn), [
      LocalDate(2026, 1, 31),
    ]);

    r.today = LocalDate(2026, 2, 28);
    final due = await r.run();
    expect(due.created, 1);
    expect(due.skippedExisting, 1);
    final expenses = await r.expensesOf(rule.id);
    expect(expenses.map((e) => e.spentOn), [
      LocalDate(2026, 1, 31),
      LocalDate(2026, 2, 28),
    ]);
    expect(expenses.last.recurringMonth, YearMonth(2026, 2));
    expect(
      expenses.last.id,
      recurringExpenseId(rule.id, YearMonth(2026, 2)),
    );
  });

  test('правило на 31-е, високосный 2028: 28 февраля — ещё нет, '
      '29 февраля — трата 29-го', () async {
    final rule = await r.rule(day: 31, from: YearMonth(2028, 2));

    r.today = LocalDate(2028, 2, 28);
    final early = await r.run();
    expect(early.created, 0);
    expect(await r.expensesOf(rule.id), isEmpty);

    r.today = LocalDate(2028, 2, 29);
    final due = await r.run();
    expect(due.created, 1);
    final expenses = await r.expensesOf(rule.id);
    expect(expenses.single.spentOn, LocalDate(2028, 2, 29));
    expect(expenses.single.recurringMonth, YearMonth(2028, 2));
  });

  test('правило на 31-е через февраль и апрель: даты 31.01, 28.02, 31.03, '
      '30.04', () async {
    final rule = await r.rule(day: 31, from: YearMonth(2026, 1));
    r.today = LocalDate(2026, 4, 30);

    final result = await r.run();

    expect(result.created, 4);
    expect((await r.expensesOf(rule.id)).map((e) => e.spentOn), [
      LocalDate(2026, 1, 31),
      LocalDate(2026, 2, 28),
      LocalDate(2026, 3, 31),
      LocalDate(2026, 4, 30),
    ]);
  });
}
