import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/data/providers.dart';
import 'package:shared/shared.dart';

import 'provider_harness.dart';

void main() {
  late ProviderHarness h;

  setUp(() => h = ProviderHarness());

  test('суммы по дням и итог месяца приходят через провайдеры после '
      'записи траты: in-memory база, часы 19.10.2026 18:40', () async {
    final budget = await h
        .read(budgetsRepositoryProvider)
        .createLocalPersonal();
    final categories = await h
        .read(categoriesRepositoryProvider)
        .watchByBudget(budget.id)
        .first;
    final food = categories.firstWhere((c) => c.name == 'Продукты');
    final cafe = categories.firstWhere((c) => c.name == 'Кафе');
    final today = h.read(clockProvider).today();
    final key = (budgetId: budget.id, month: YearMonth.of(today));

    final days = h.watch(dayTotalsProvider(key));
    final total = h.watch(monthTotalProvider(key));
    final list = h.watch(
      dayExpensesProvider((budgetId: budget.id, day: today)),
    );

    expect(today, LocalDate(2026, 10, 19));
    expect(await days.data(), isEmpty);
    expect(await total.data(), Money.zero);
    expect(await list.data(), isEmpty);

    final expenses = h.read(expensesRepositoryProvider);
    final first = await expenses.create(
      budgetId: budget.id,
      categoryId: food.id,
      amount: Money.rubles(640),
      spentOn: today,
      comment: 'Пятёрочка',
    );

    expect(await days.data((d) => d.isNotEmpty), {19: Money.rubles(640)});
    expect(await total.data((m) => !m.isZero), Money.rubles(640));
    expect((await list.data((l) => l.isNotEmpty)).map((e) => e.id), [first.id]);
    expect(first.createdAt.isAtSameMomentAs(fixedNow), isTrue);

    h.now = fixedNow.add(const Duration(minutes: 20));
    await expenses.create(
      budgetId: budget.id,
      categoryId: cafe.id,
      amount: Money.rubles(350),
      spentOn: LocalDate(2026, 10, 17),
    );

    expect(await days.data((d) => d.length == 2), {
      17: Money.rubles(350),
      19: Money.rubles(640),
    });
    expect(await total.data((m) => m != Money.rubles(640)), Money.rubles(990));
    expect(list.last.requireValue.map((e) => e.id), [first.id]);
  });

  test('трата в другом месяце не попадает в октябрь, а ноябрьский '
      'провайдер её видит', () async {
    final budget = await h
        .read(budgetsRepositoryProvider)
        .createLocalPersonal();
    final other =
        (await h
                .read(categoriesRepositoryProvider)
                .watchByBudget(budget.id)
                .first)
            .last;
    final october = h.watch(
      monthTotalProvider((budgetId: budget.id, month: YearMonth(2026, 10))),
    );
    final november = h.watch(
      monthTotalProvider((budgetId: budget.id, month: YearMonth(2026, 11))),
    );
    expect(await october.data(), Money.zero);
    expect(await november.data(), Money.zero);

    await h
        .read(expensesRepositoryProvider)
        .create(
          budgetId: budget.id,
          categoryId: other.id,
          amount: Money.rubles(1200),
          spentOn: LocalDate(2026, 11, 2),
        );

    expect(await november.data((m) => !m.isZero), Money.rubles(1200));
    expect(october.last.requireValue, Money.zero);
  });

  test('часы из clockProvider доходят до репозиториев: createdAt, '
      'updatedAt траты и момент записи в outbox', () async {
    final budget = await h
        .read(budgetsRepositoryProvider)
        .createLocalPersonal();
    final category =
        (await h
                .read(categoriesRepositoryProvider)
                .watchByBudget(budget.id)
                .first)
            .first;
    h.now = DateTime(2026, 10, 20, 9, 15);

    final expense = await h
        .read(expensesRepositoryProvider)
        .create(
          budgetId: budget.id,
          categoryId: category.id,
          amount: Money.rubles(149, 90),
          spentOn: h.read(clockProvider).today(),
        );
    final rows = await h.db.select(h.db.outbox).get();

    expect(expense.spentOn, LocalDate(2026, 10, 20));
    expect(expense.createdAt.isAtSameMomentAs(h.now), isTrue);
    expect(expense.updatedAt.isAtSameMomentAs(h.now), isTrue);
    expect(
      rows.last.createdAt.isAtSameMomentAs(DateTime(2026, 10, 20, 9, 15)),
      isTrue,
    );
    expect(budget.createdAt.isAtSameMomentAs(fixedNow), isTrue);
  });
}
