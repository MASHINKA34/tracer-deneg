import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/l10n/app_localizations.dart';
import 'package:milionchik/ui/components/expense_row.dart';

import '../../support/app_scope.dart';
import '../../support/test_fonts.dart';
import '../shell/shell_harness.dart';
import 'recurring_fixture.dart';

const String _tail = '. Сами появляются в календаре в день списания';

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('ru'));
  });

  test('число платежей: 1 платёж, 2–4 платежа, 5–20 платежей, 21 платёж, '
      '22 платежа, 111 платежей', () {
    expect(
      {
        for (final n in [1, 2, 4, 5, 11, 14, 20, 21, 22, 25, 101, 111])
          n: l10n.recurringSummary(n),
      },
      {
        1: '1 платёж$_tail',
        2: '2 платежа$_tail',
        4: '4 платежа$_tail',
        5: '5 платежей$_tail',
        11: '11 платежей$_tail',
        14: '14 платежей$_tail',
        20: '20 платежей$_tail',
        21: '21 платёж$_tail',
        22: '22 платежа$_tail',
        25: '25 платежей$_tail',
        101: '101 платёж$_tail',
        111: '111 платежей$_tail',
      },
    );
  });

  test('дни до списания: через 1 день, 2–4 дня, 5–20 дней, 21 день, 22 дня, '
      '31 день', () {
    expect(
      {
        for (final n in [1, 2, 3, 5, 11, 12, 21, 22, 25, 30, 31])
          n: l10n.recurringInDays(n),
      },
      {
        1: 'через 1 день',
        2: 'через 2 дня',
        3: 'через 3 дня',
        5: 'через 5 дней',
        11: 'через 11 дней',
        12: 'через 12 дней',
        21: 'через 21 день',
        22: 'через 22 дня',
        25: 'через 25 дней',
        30: 'через 30 дней',
        31: 'через 31 день',
      },
    );
    expect(l10n.recurringEvery(1), 'каждое 1-е');
    expect(l10n.recurringEvery(31), 'каждое 31-е');
  });

  testWidgets('одно правило на завтра, 20-е: «1 платёж», «каждое 20-е · '
      'через 1 день»; два правила — «2 платежа»', (tester) async {
    await loadTestFonts();
    final db = openTestDatabase();
    final budget = (await tester.runAsync(() async {
      final b = await seedRecurringBudget(db);
      await b.rule('Облако', rubles: 149, day: 20);
      return b;
    }))!;
    final h = await ShellHarness.start(tester, db: db);
    await h.tapTab('Регулярные');

    expect(find.text('1 платёж$_tail'), findsOneWidget);
    expect(
      tester.widget<ExpenseRow>(find.byType(ExpenseRow)).subtitle,
      'каждое 20-е · через 1 день',
    );
    expect(find.text('Уже списано в октябре'), findsNothing);

    await writeWhileShown(
      tester,
      () => budget.rule('Музыка', rubles: 199, day: 21),
    );

    expect(find.text('2 платежа$_tail'), findsOneWidget);
    expect(
      [
        for (final row in tester.widgetList<ExpenseRow>(
          find.byType(ExpenseRow),
        ))
          row.subtitle,
      ],
      ['каждое 20-е · через 1 день', 'каждое 21-е · через 2 дня'],
    );
  });
}
