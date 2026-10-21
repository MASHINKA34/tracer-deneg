import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/features/expense/expense_amount_sheet.dart';
import 'package:milionchik/ui/components/button.dart';

import 'edit_expense_harness.dart';
import 'new_expense_harness.dart' show hapticCount, nbspace;

Finder _inSheet(Finder finder) =>
    find.descendant(of: find.byType(ExpenseAmountSheet), matching: finder);

String _sheetAmount(WidgetTester tester) => tester
    .widget<Text>(
      _inSheet(
        find.descendant(
          of: find.byKey(const ValueKey('new-expense-amount')),
          matching: find.byType(Text),
        ),
      ).first,
    )
    .data!;

bool _doneEnabled(WidgetTester tester) =>
    tester
        .widget<AppButton>(_inSheet(find.widgetWithText(AppButton, 'Готово')))
        .onPressed !=
    null;

Future<EditHarness> _openSheet(WidgetTester tester) async {
  final h = await EditHarness.start(tester);
  await h.openById(h.pyaterochka.id);
  await tester.tap(h.amount);
  await tester.pumpAndSettle();
  expect(find.byType(ExpenseAmountSheet), findsOneWidget);
  return h;
}

void main() {
  testWidgets('тап по сумме открывает шторку с клавиатурой и текущей суммой '
      '640, «Готово» активна; вибрация на каждое нажатие', (tester) async {
    final h = await _openSheet(tester);
    expect(_sheetAmount(tester), '640');
    expect(_inSheet(find.text('Сумма')), findsOneWidget);
    expect(_doneEnabled(tester), isTrue);

    final haptics = hapticCount(h.shell.platformCalls);
    await h.pressKeys('5');
    expect(_sheetAmount(tester), '6${nbspace}405');
    expect(hapticCount(h.shell.platformCalls) - haptics, 1);
  });

  testWidgets('149,90 из траты дописывается: третий знак после запятой и '
      'вторая запятая не вводятся, больше 10 000 000 тоже', (tester) async {
    final h = await _openSheet(tester);
    await h.pressKeys('<<<149,909,');
    expect(_sheetAmount(tester), '149,90');

    await h.pressKeys('<<<<<<1000000000');
    expect(_sheetAmount(tester), '10${nbspace}000${nbspace}000');
    expect(
      h.shell.records
          .where((r) => r.loggerName == 'expense' && r.level == Level.FINE)
          .map((r) => r.message),
      contains('amount sheet keypad digit 0 rejected text=10000000'),
    );
  });

  testWidgets('стёрто всё (долгое нажатие «Стереть») — 0, «Готово» неактивна; '
      'закрытие жестом «назад» оставляет сумму траты 640', (tester) async {
    final h = await _openSheet(tester);
    await tester.longPress(_inSheet(find.bySemanticsLabel('Стереть')));
    await tester.pumpAndSettle();
    expect(_sheetAmount(tester), '0');
    expect(_doneEnabled(tester), isFalse);

    await h.shell.systemBack();
    expect(find.byType(ExpenseAmountSheet), findsNothing);
    expect(h.inEdit(find.text('640')), findsOneWidget);
    expect(h.saveEnabled, isFalse);
    expect(
      h.shell.records.map((r) => r.message),
      contains(
        matches(
          r'^amount sheet closed without done after \d+ms: back gesture, tap '
          r'outside or swipe down, amount stays kopecks=64000$',
        ),
      ),
    );
  });

  testWidgets('«Готово» ставит 149,9 на экран правки как 149,90 и закрывает '
      'шторку', (tester) async {
    final h = await _openSheet(tester);
    await h.pressKeys('<<<149,9');
    await tester.tap(_inSheet(find.text('Готово')));
    await tester.pumpAndSettle();

    expect(find.byType(ExpenseAmountSheet), findsNothing);
    expect(h.inEdit(find.text('149,90')), findsOneWidget);
    expect(h.saveEnabled, isTrue);
    expect(tester.getSemantics(h.amount).value, '149 рублей 90 копеек');
  });
}
