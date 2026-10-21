import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/features/expense/new_expense_screen.dart';
import 'package:milionchik/features/month/month_screen.dart';
import 'package:milionchik/ui/components/bottom_nav.dart';
import 'package:milionchik/ui/components/button.dart';
import 'package:milionchik/ui/components/dialog.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';
import '../month/month_fixture.dart';
import '../shell/shell_harness.dart';
import 'new_expense_harness.dart';

final LocalDate _today = LocalDate(2026, 10, 19);

Finder get _dialog => find.byType(AppDialog);

Future<void> _tapClose(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel('Закрыть'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('без суммы крестик, «назад» и жест «назад» закрывают сразу, без '
      'диалога', (tester) async {
    final h = await ShellHarness.start(tester);

    await h.tapPlus();
    await _tapClose(tester);
    expect(_dialog, findsNothing);
    expect(find.byType(NewExpenseScreen), findsNothing);

    await h.tapPlus();
    await h.systemBack();
    expect(_dialog, findsNothing);
    expect(find.byType(NewExpenseScreen), findsNothing);

    await h.tapPlus();
    await typeKeys(tester, '5');
    await tester.tap(keypadKey('Стереть'));
    await tester.pumpAndSettle();
    await h.predictiveBackGesture();
    expect(_dialog, findsNothing);
    expect(find.byType(NewExpenseScreen), findsNothing);
    expect(find.byType(MonthScreen), findsOneWidget);
    expect(h.systemPops, 0);
  });

  testWidgets('с суммой крестик — диалог «Не сохранять?» с «Не сохранять» '
      '(красная) и «Остаться»; «Остаться» оставляет сумму', (tester) async {
    final h = await ShellHarness.start(tester);
    await h.tapPlus();
    await typeKeys(tester, '1250');

    await _tapClose(tester);
    expect(_dialog, findsOneWidget);
    expect(find.text('Не сохранять?'), findsOneWidget);
    final dialog = tester.widget<AppDialog>(_dialog);
    expect(dialog.primary.label, 'Не сохранять');
    expect(dialog.primary.destructive, isTrue);
    expect(dialog.secondary!.label, 'Остаться');
    expect(
      tester
          .widget<AppButton>(
            find.ancestor(
              of: find.text('Не сохранять'),
              matching: find.byType(AppButton),
            ),
          )
          .type,
      AppButtonType.danger,
    );

    await tester.tap(find.text('Остаться'));
    await tester.pumpAndSettle();
    expect(_dialog, findsNothing);
    expect(find.byType(NewExpenseScreen), findsOneWidget);
    expect(amountText(tester), '1${nbspace}250');

    await typeKeys(tester, '0');
    expect(amountText(tester), '12${nbspace}500');
  });

  testWidgets('«Не сохранять» закрывает экран, трата не записана', (
    tester,
  ) async {
    final db = openTestDatabase();
    final budgetId = (await tester.runAsync(() => seedMockupOctober(db)))!;
    final h = await ShellHarness.start(tester, db: db);
    final before = await allExpenses(tester, db, budgetId, _today);
    await h.tapPlus();
    await typeKeys(tester, '640');

    await _tapClose(tester);
    await tester.tap(find.text('Не сохранять'));
    await tester.pumpAndSettle();

    expect(_dialog, findsNothing);
    expect(find.byType(NewExpenseScreen), findsNothing);
    expect(find.byType(MonthScreen), findsOneWidget);
    expect(await allExpenses(tester, db, budgetId, _today), before);
    expect(h.navDebug(), contains('new expense closed by close button'));
  });

  testWidgets('с суммой системное «назад» — тот же диалог; «назад» в диалоге и '
      'тап мимо — остаться; «Не сохранять» после «назад» закрывает', (
    tester,
  ) async {
    final h = await ShellHarness.start(tester);
    await h.tapPlus();
    await typeKeys(tester, '99');

    await h.systemBack();
    expect(_dialog, findsOneWidget);
    expect(find.byType(NewExpenseScreen), findsOneWidget);
    await h.systemBack();
    expect(_dialog, findsNothing);
    expect(amountText(tester), '99');

    await h.systemBack();
    expect(_dialog, findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(_dialog, findsNothing);
    expect(amountText(tester), '99');

    await h.systemBack();
    await tester.tap(find.text('Не сохранять'));
    await tester.pumpAndSettle();
    expect(find.byType(NewExpenseScreen), findsNothing);
    expect(h.activeTab, AppNavTab.month);
    expect(h.systemPops, 0);
    expect(h.navDebug(), contains('new expense closed by back'));
  });

  testWidgets('с суммой жест «назад» (predictive back) — диалог, экран не '
      'уезжает; «Остаться» оставляет сумму', (tester) async {
    final h = await ShellHarness.start(tester);
    await h.tapTab('Профиль');
    await h.tapPlus();
    await typeKeys(tester, '3,5');

    await h.predictiveBackGesture();
    expect(_dialog, findsOneWidget);
    expect(tester.getRect(find.byType(NewExpenseScreen)).top, 0);
    await tester.tap(find.text('Остаться'));
    await tester.pumpAndSettle();
    expect(amountText(tester), '3,5');
    expect(find.byType(NewExpenseScreen), findsOneWidget);

    await h.predictiveBackGesture();
    await tester.tap(find.text('Не сохранять'));
    await tester.pumpAndSettle();
    expect(find.byType(NewExpenseScreen), findsNothing);
    expect(h.activeTab, AppNavTab.profile);
    expect(h.systemPops, 0);
  });

  testWidgets('логи диалога — debug [expense] с источником и выбором, без '
      'суммы', (tester) async {
    final h = await ShellHarness.start(tester);
    await h.tapPlus();
    await typeKeys(tester, '1250');

    await _tapClose(tester);
    expect(_dialog, findsOneWidget);
    await tester.tap(find.text('Остаться'));
    await tester.pumpAndSettle();
    await h.systemBack();
    await tester.tap(find.text('Не сохранять'));
    await tester.pumpAndSettle();

    final messages = [
      for (final r in h.records)
        if (r.loggerName == 'expense' && r.message.contains('discard') ||
            r.message.contains('close by'))
          r.message,
    ];
    expect(
      messages,
      containsAllInOrder([
        'new expense close by close button with amount entered → discard '
            'dialog',
        'new expense discard dialog → stay: amount kept',
        'new expense close by back with amount entered → discard dialog',
        'new expense discarded by back: amount dropped, nothing saved',
      ]),
    );
    for (final r in h.records.where(
      (r) => r.loggerName == 'expense' && r.message.contains('discard'),
    )) {
      expect(r.level, Level.FINE);
      expect(r.message, isNot(contains('1250')));
    }
  });
}
