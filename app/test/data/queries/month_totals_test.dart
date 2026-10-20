import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/ui/catalog/demo_months.dart';
import 'package:shared/shared.dart';

import 'query_fixture.dart';

void main() {
  late QueryHarness h;

  setUp(() async {
    h = QueryHarness();
    await h.seedMockup();
  });

  tearDown(() => h.dispose());

  test('суммы по дням октября - ровно как на макете 7:7', () async {
    final totals = await h.month.watchDayTotals(h.budget.id, october).first;

    expect(totals, demoAutumn.dayTotals);
    expect(totals.containsKey(4), isFalse);
    expect(totals[2], const Money.rubles(1280));
    expect(totals[17]!.formatCell(), '1${nbsp}450');
  });

  test('итог месяца 18 300 ₽ и 963 ₽ в день через shared', () async {
    final total = await h.month.watchMonthTotal(h.budget.id, october).first;
    final average = averagePerDay(
      monthTotal: total,
      month: october,
      today: today,
    );

    expect(total, const Money.rubles(18300));
    expect(total.formatTotal(), '18${nbsp}300$nbsp₽');
    expect(average!.formatTotal(), '963$nbsp₽');
  });

  test('шторка 17 октября: 1 450 ₽, больше среднего на 487 ₽', () async {
    final totals = await h.month.watchDayTotals(h.budget.id, october).first;
    final total = await h.month.watchMonthTotal(h.budget.id, october).first;
    final average = averagePerDay(
      monthTotal: total,
      month: october,
      today: today,
    )!;

    final difference = differenceFromAverage(
      daySum: totals[17]!,
      average: average,
    );

    expect(totals[17]!.formatTotal(), '1${nbsp}450$nbsp₽');
    expect(difference.formatTotal(), '487$nbsp₽');
  });

  test('итог и дни прошедших месяцев - как на карточках макета', () async {
    for (final demo in [demoWinter, demoSpring, demoSummer]) {
      final totals = await h.month
          .watchDayTotals(h.budget.id, demo.month)
          .first;
      final total = await h.month
          .watchMonthTotal(h.budget.id, demo.month)
          .first;

      expect(totals, demo.dayTotals, reason: demo.name);
      expect(total, Money.sum(demo.dayTotals.values), reason: demo.name);
    }
  });

  test('пустой месяц - пустая карта и 0 ₽, «—» в среднем', () async {
    final month = YearMonth(2026, 2);
    final totals = await h.month.watchDayTotals(h.budget.id, month).first;
    final total = await h.month.watchMonthTotal(h.budget.id, month).first;

    expect(totals, isEmpty);
    expect(total, Money.zero);
    expect(
      averagePerDay(monthTotal: total, month: month, today: today),
      isNull,
    );
  });

  test('траты дня - по времени создания, от ранней к поздней', () async {
    final names = h.categoryNames(h.budget);

    final day17 = await h.month
        .watchDayExpenses(h.budget.id, october.dayOf(17))
        .first;
    final day19 = await h.month
        .watchDayExpenses(h.budget.id, october.dayOf(19))
        .first;

    expect(
      describeSpends(day17, names),
      '17:Кафе:890$nbsp₽, 17:Продукты:560$nbsp₽',
    );
    expect(
      describeSpends(day19, names),
      '19:Кафе:210$nbsp₽, 19:Продукты:640$nbsp₽, 19:Транспорт:250$nbsp₽',
    );
    expect(day17.first.comment, 'Обед с коллегами');
  });

  test('другой бюджет считается отдельно', () async {
    final totals = await h.month
        .watchDayTotals(h.otherBudget.id, october)
        .first;
    final total = await h.month
        .watchMonthTotal(h.otherBudget.id, october)
        .first;

    expect(totals, {19: const Money.rubles(640)});
    expect(total, const Money.rubles(640));
  });

  test('реактивно: новая трата, удаление и отмена меняют сумму дня, итог '
      'и список дня', () async {
    final days = Watcher(h.month.watchDayTotals(h.budget.id, october));
    final total = Watcher(h.month.watchMonthTotal(h.budget.id, october));
    final list = Watcher(
      h.month.watchDayExpenses(h.budget.id, october.dayOf(20)),
    );
    addTearDown(() async {
      await days.cancel();
      await total.cancel();
      await list.cancel();
    });
    expect((await days.next())[20], isNull);
    expect(await total.next(), const Money.rubles(18300));
    expect(await list.next(), isEmpty);

    final created = await h.repo.expenses.create(
      budgetId: h.budget.id,
      categoryId: h.budget.byName('Кафе').id,
      amount: const Money.rubles(500),
      spentOn: october.dayOf(20),
      comment: 'Кофе',
    );

    expect((await days.next())[20], const Money.rubles(500));
    expect(await total.next(), const Money.rubles(18800));
    expect((await list.next()).map((e) => e.id), [created.id]);

    await h.repo.expenses.delete(created.id);

    expect((await days.next())[20], isNull);
    expect(await total.next(), const Money.rubles(18300));
    expect(await list.next(), isEmpty);

    await h.repo.expenses.undoDelete(created.id);

    expect((await days.next())[20], const Money.rubles(500));
    expect(await total.next(), const Money.rubles(18800));
    expect((await list.next()).single.id, created.id);
  });

  test('реактивно: правка суммы и перенос даты двигают суммы дней', () async {
    final days = Watcher(h.month.watchDayTotals(h.budget.id, october));
    addTearDown(days.cancel);
    final first = await days.next();
    final coffee = h.live.firstWhere(
      (e) => e.spentOn == october.dayOf(19) && e.amount.kopecks == 21000,
    );

    await h.repo.expenses.update(coffee.id, amount: const Money.rubles(310));
    final edited = await days.next();
    await h.repo.expenses.update(coffee.id, spentOn: october.dayOf(4));
    final moved = await days.next();

    expect(first[19], const Money.rubles(1100));
    expect(edited[19], const Money.rubles(1200));
    expect(moved[19], const Money.rubles(890));
    expect(moved[4], const Money.rubles(310));
  });
}
