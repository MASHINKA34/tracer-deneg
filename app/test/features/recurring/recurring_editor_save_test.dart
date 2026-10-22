import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/router.dart';
import 'package:milionchik/features/month/month_screen.dart';
import 'package:milionchik/features/recurring/recurring_editor_screen.dart';
import 'package:milionchik/features/recurring/recurring_screen.dart';
import 'package:shared/shared.dart';

import 'recurring_editor_harness.dart';
import 'recurring_fixture.dart';

Future<RecurringRule> _created(RecurringEditorHarness h, String title) async =>
    (await h.rules()).singleWhere((r) => r.title == title);

void _expectNoSecrets(RecurringEditorHarness h, List<String> secrets) {
  for (final r in h.shell.records.where((r) => r.level >= Level.INFO)) {
    final text = '${r.message} ${r.error ?? ''}';
    for (final secret in secrets) {
      expect(text, isNot(contains(secret)), reason: text);
    }
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('новое правило на сегодня (19-е): «Сохранить» → назад к '
      'списку, правило с 2026-10 и трата 19 октября сразу в календаре; info '
      '[recurring] с id, днём и мс, генератор «rule saved» создал 1; '
      'названия и суммы на info нет', (tester) async {
    final h = await RecurringEditorHarness.start(tester);
    await h.openNew();
    await h.typeTitle('Квартплата');
    await h.enterAmount('4500');
    await h.pickCategory('Интернет');
    expect(h.rowLabel('День списания'), 'День списания, 19-е число');

    await h.save();

    expect(find.byType(RecurringEditorScreen), findsNothing);
    expect(find.byType(RecurringScreen), findsOneWidget);
    expect(h.location, AppRoutes.recurring);
    final rule = await _created(h, 'Квартплата');
    expect(rule.dayOfMonth, 19);
    expect(rule.startMonth, october);
    expect(rule.amount, Money.rubles(4500));
    expect(rule.categoryId, h.budget.categoryIds['Интернет']);
    expect(rule.budgetId, h.budget.id);
    final expenses = await h.expensesOf(rule.id);
    expect(expenses, hasLength(1));
    final expense = expenses.single;
    expect(expense.id, recurringExpenseId(rule.id, october));
    expect(expense.spentOn, LocalDate(2026, 10, 19));
    expect(expense.amount, Money.rubles(4500));
    expect(expense.comment, 'Квартплата');
    expect(expense.recurringMonth, october);

    await h.shell.tapTab('Месяц');
    expect(find.byType(MonthScreen), findsOneWidget);
    expect(find.textContaining('Квартплата'), findsWidgets);

    final info = h.messages(Level.INFO).toList();
    expect(
      info,
      containsAllInOrder([
        matches(
          '^recurring rule created id=${rule.id} budgetId=${h.budget.id} '
          'day=19 from=2026-10 firstCharge=2026-10-19 today=2026-10-19 '
          r'in \d+ms$',
        ),
        matches(
          r'^run \(rule saved\) today=2026-10-19 rules=6 created=1 '
          r'skipped=3 existing=3 deleted=0 in \d+ms$',
        ),
      ]),
    );
    expect(
      h.messages(),
      contains(
        matches(
          r'^recurring save new: generator after save created=1 skipped=3 '
          r'in \d+ms$',
        ),
      ),
    );
    expect(h.logs(Level.WARNING), isEmpty);
    _expectNoSecrets(h, ['Квартплата', '4500', '4 500', '450000']);
  });

  testWidgets('новое правило на вчера (18-е): трат нет, правило с ноября '
      '(первая трата 18 ноября), в «Скоро» на вкладке', (tester) async {
    final h = await RecurringEditorHarness.start(tester);
    await h.openNew();
    await h.typeTitle('Квартплата');
    await h.enterAmount('4500');
    await h.pickCategory('Интернет');
    await h.pickDay(18);

    await h.save();

    expect(find.byType(RecurringScreen), findsOneWidget);
    final rule = await _created(h, 'Квартплата');
    expect(rule.dayOfMonth, 18);
    expect(rule.startMonth, YearMonth(2026, 11));
    expect(await h.expensesOf(rule.id), isEmpty);
    expect(find.text('каждое 18-е · через 30 дней'), findsOneWidget);
    expect(
      h.messages(Level.INFO),
      containsAllInOrder([
        matches(
          '^recurring rule created id=${rule.id} budgetId=${h.budget.id} '
          'day=18 from=2026-11 firstCharge=2026-11-18 today=2026-10-19 '
          r'in \d+ms$',
        ),
        matches(r'^run \(rule saved\) today=2026-10-19 rules=6 created=0 '),
      ]),
    );
  });

  testWidgets('правка суммы, названия и категории спортзала меняет только '
      'правило: октябрьская трата 2 900 ₽ «Спортзал «Территория»» в «Спорте» '
      'осталась как была, новой нет', (tester) async {
    final h = await RecurringEditorHarness.start(tester);
    final gym = h.budget.rules[gymTitle]!;
    final before = await h.expensesOf(gym.id);
    expect(before, hasLength(1));
    await h.openRule(gymTitle);

    await h.typeTitle('Фитнес');
    await h.enterAmount('<<<<3200');
    await h.pickCategory('Кино');
    await h.save();

    expect(find.byType(RecurringEditorScreen), findsNothing);
    final rule = (await h.rules()).singleWhere((r) => r.id == gym.id);
    expect(rule.title, 'Фитнес');
    expect(rule.amount, Money.rubles(3200));
    expect(rule.categoryId, h.budget.categoryIds['Кино']);
    expect(rule.dayOfMonth, 12);
    expect(rule.startMonth, october);
    final after = await h.expensesOf(gym.id);
    expect(after, hasLength(1));
    expect(after.single.id, before.single.id);
    expect(after.single.amount, Money.rubles(2900));
    expect(after.single.comment, gymTitle);
    expect(after.single.categoryId, h.budget.categoryIds['Спорт']);
    expect(after.single.spentOn, LocalDate(2026, 10, 12));
    expect(
      h.messages(Level.INFO),
      contains(
        matches(
          '^recurring rule updated id=${gym.id} budgetId=${h.budget.id} '
          'fields=title,amount,category day=12 from=2026-10 '
          r'in \d+ms, created expenses unchanged$',
        ),
      ),
    );
    _expectNoSecrets(h, ['Фитнес', '3200', '3 200', '320000']);
  });

  testWidgets('день «Музыки» 24 → 5 до первой траты: старт пересчитан на '
      'ноябрь как у нового правила, трата 5 октября задним числом не '
      'создаётся', (tester) async {
    final h = await RecurringEditorHarness.start(tester);
    final music = h.budget.rules['Музыка']!;
    await h.openRule('Музыка');

    await h.pickDay(5);
    await h.save();

    final rule = (await h.rules()).singleWhere((r) => r.id == music.id);
    expect(rule.dayOfMonth, 5);
    expect(rule.startMonth, YearMonth(2026, 11));
    expect(await h.expensesOf(music.id), isEmpty);
    expect(
      h.messages(Level.INFO),
      contains(
        matches(
          '^recurring rule updated id=${music.id} budgetId=${h.budget.id} '
          r'fields=day day=5 from=2026-11 \(was 2026-10: no charge was due '
          r'yet, start recounted as for a new rule\) in \d+ms, created '
          r'expenses unchanged$',
        ),
      ),
    );
  });

  testWidgets('день «Музыки» 24 → 19 (сегодня): старт прежний, трата 19 '
      'октября появляется сразу', (tester) async {
    final h = await RecurringEditorHarness.start(tester);
    final music = h.budget.rules['Музыка']!;
    await h.openRule('Музыка');

    await h.pickDay(19);
    await h.save();

    final rule = (await h.rules()).singleWhere((r) => r.id == music.id);
    expect(rule.dayOfMonth, 19);
    expect(rule.startMonth, october);
    final expenses = await h.expensesOf(music.id);
    expect(expenses.map((e) => e.spentOn), [LocalDate(2026, 10, 19)]);
    expect(expenses.single.amount, Money.rubles(199));
  });

  testWidgets('день спортзала 12 → 25 после октябрьской траты: старт '
      'прежний, второй траты за октябрь нет', (tester) async {
    final h = await RecurringEditorHarness.start(tester);
    final gym = h.budget.rules[gymTitle]!;
    await h.openRule(gymTitle);

    await h.pickDay(25);
    await h.save();

    final rule = (await h.rules()).singleWhere((r) => r.id == gym.id);
    expect(rule.dayOfMonth, 25);
    expect(rule.startMonth, october);
    final expenses = await h.expensesOf(gym.id);
    expect(expenses.map((e) => e.spentOn), [LocalDate(2026, 10, 12)]);
  });

  testWidgets('ничего не поменяли — «Сохранить» просто возвращает к списку '
      'без записи и без запуска генератора', (tester) async {
    final h = await RecurringEditorHarness.start(tester);
    final gym = h.budget.rules[gymTitle]!;
    await h.openRule(gymTitle);

    await h.save();

    expect(find.byType(RecurringEditorScreen), findsNothing);
    final rule = (await h.rules()).singleWhere((r) => r.id == gym.id);
    expect(rule.updatedAt, gym.updatedAt);
    expect(
      h.messages(),
      contains(
        'recurring save id=${gym.id}: nothing changed → back without writing',
      ),
    );
    expect(h.messages(), isNot(contains(startsWith('run (rule saved)'))));
  });
}
