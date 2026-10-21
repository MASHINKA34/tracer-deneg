import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/features/expense/new_expense_screen.dart';

import '../shell/shell_harness.dart';
import 'new_expense_harness.dart';

double _shakeDx(WidgetTester tester) => tester
    .widget<Transform>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('new-expense-amount')),
            matching: find.byType(Transform),
          )
          .first,
    )
    .transform
    .getTranslation()
    .x;

double _caretOpacity(WidgetTester tester) => tester
    .widget<Opacity>(
      find.ancestor(
        of: find.byKey(const ValueKey('new-expense-caret')),
        matching: find.byType(Opacity),
      ),
    )
    .opacity;

void main() {
  testWidgets('пустая сумма — «0» серым и подпись «Сумма», «1250» → «1 250», '
      'стереть и набрать «149,9»', (tester) async {
    final h = await ShellHarness.start(tester);
    await h.tapPlus();

    expect(inNewExpense(find.text('Сумма')), findsOneWidget);
    expect(amountText(tester), '0');
    Color? colorOf(Finder text) => tester.widget<Text>(text).style!.color;
    final amount = find
        .descendant(
          of: find.byKey(const ValueKey('new-expense-amount')),
          matching: find.byType(Text),
        )
        .first;
    final tertiary = colorOf(inNewExpense(find.text('Сумма')));
    expect(colorOf(amount), tertiary);

    await typeKeys(tester, '1250');
    expect(amountText(tester), '1${nbspace}250');
    expect(colorOf(amount), isNot(tertiary));

    for (var i = 0; i < 4; i++) {
      await tester.tap(keypadKey('Стереть'));
      await tester.pump();
    }
    expect(amountText(tester), '0');

    await typeKeys(tester, '149,9');
    expect(amountText(tester), '149,9');
  });

  testWidgets('третий знак после запятой не вводится, запятая одна, «,» на '
      'пустой сумме даёт «0,», ведущих нулей нет', (tester) async {
    final h = await ShellHarness.start(tester);
    await h.tapPlus();

    await typeKeys(tester, ',');
    expect(amountText(tester), '0,');
    await typeKeys(tester, '5,');
    expect(amountText(tester), '0,5');
    await typeKeys(tester, '57');
    expect(amountText(tester), '0,55');

    await tester.longPress(keypadKey('Стереть'));
    await tester.pumpAndSettle();
    expect(amountText(tester), '0');

    await typeKeys(tester, '007');
    expect(amountText(tester), '7');
    await typeKeys(tester, '49,999');
    expect(amountText(tester), '749,99');
  });

  testWidgets('больше 10 000 000 ₽ не набрать: девятая цифра и копейки сверх '
      'максимума не вводятся', (tester) async {
    final h = await ShellHarness.start(tester);
    await h.tapPlus();

    await typeKeys(tester, '10000000');
    expect(amountText(tester), '10${nbspace}000${nbspace}000');
    await typeKeys(tester, '0');
    expect(amountText(tester), '10${nbspace}000${nbspace}000');
    await typeKeys(tester, ',01');
    expect(amountText(tester), '10${nbspace}000${nbspace}000,0');
    await typeKeys(tester, '0');
    expect(amountText(tester), '10${nbspace}000${nbspace}000,00');

    await tester.longPress(keypadKey('Стереть'));
    await tester.pumpAndSettle();
    await typeKeys(tester, '9999999,99');
    expect(amountText(tester), '9${nbspace}999${nbspace}999,99');
  });

  testWidgets('каждое нажатие клавиши — лёгкая вибрация, и принятое, и '
      'отклонённое', (tester) async {
    final h = await ShellHarness.start(tester);
    await h.tapPlus();
    final before = hapticCount(h.platformCalls);

    await typeKeys(tester, '1,234');

    expect(hapticCount(h.platformCalls) - before, 5);
    expect(amountText(tester), '1,23');
  });

  testWidgets('отклонённая цифра встряхивает сумму и возвращает её на место; '
      'принятая цифра и «Стереть» — нет', (tester) async {
    final h = await ShellHarness.start(tester);
    await h.tapPlus();
    await typeKeys(tester, '1,23');
    expect(_shakeDx(tester), 0);

    await tester.tap(keypadKey('4'));
    await tester.pump();
    final offsets = <double>[];
    for (var i = 0; i < 6; i++) {
      await tester.pump(amountShakeDuration ~/ 7);
      offsets.add(_shakeDx(tester));
    }
    expect(offsets.where((dx) => dx.abs() > 1), isNotEmpty);
    expect(offsets.any((dx) => dx < 0) && offsets.any((dx) => dx > 0), isTrue);
    await tester.pumpAndSettle();
    expect(_shakeDx(tester), 0);
    expect(amountText(tester), '1,23');

    await tester.tap(keypadKey('Стереть'));
    await tester.pump();
    await tester.pump(amountShakeDuration ~/ 7);
    expect(amountText(tester), '1,2');
    expect(_shakeDx(tester), 0);

    await tester.tap(keypadKey('5'));
    await tester.pump();
    await tester.pump(amountShakeDuration ~/ 7);
    expect(amountText(tester), '1,25');
    expect(_shakeDx(tester), 0);
  });

  testWidgets('каретка мигает каждые 530 мс и снова видна после нажатия', (
    tester,
  ) async {
    final h = await ShellHarness.start(tester);
    await h.tapPlus();

    expect(_caretOpacity(tester), 1);
    await tester.pump(caretBlinkInterval);
    expect(_caretOpacity(tester), 0);
    await tester.pump(caretBlinkInterval);
    expect(_caretOpacity(tester), 1);
    await tester.pump(caretBlinkInterval);
    expect(_caretOpacity(tester), 0);

    await tester.tap(keypadKey('7'));
    await tester.pump();
    expect(_caretOpacity(tester), 1);
    await tester.pump(caretBlinkInterval - const Duration(milliseconds: 10));
    expect(_caretOpacity(tester), 1);
  });

  testWidgets('при «Убрать анимацию» каретка видна всегда, сумма не '
      'встряхивается', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final h = await ShellHarness.start(tester);
    await h.tapPlus();
    await typeKeys(tester, '1,23');

    for (var i = 0; i < 4; i++) {
      await tester.pump(caretBlinkInterval);
      expect(_caretOpacity(tester), 1);
    }
    await tester.tap(keypadKey('4'));
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await tester.pump(amountShakeDuration ~/ 7);
      expect(_shakeDx(tester), 0);
    }
    expect(amountText(tester), '1,23');
  });

  testWidgets('TalkBack: сумма читается словами «Сумма, 1 250 рублей», '
      'клавиши — цифрами, «,» и «Стереть»', (tester) async {
    final semantics = tester.ensureSemantics();
    final h = await ShellHarness.start(tester);
    await h.tapPlus();
    await typeKeys(tester, '1250');

    final amount = tester.getSemantics(find.bySemanticsLabel('Сумма').first);
    expect(amount.label, 'Сумма');
    expect(amount.value, '1${nbspace}250 рублей');
    for (final key in ['0', '1', '9', ',', 'Стереть']) {
      expect(keypadKey(key), findsOneWidget, reason: key);
    }
    semantics.dispose();
  });

  testWidgets('логи ввода — debug [expense] с причиной отказа, сумма только '
      'на debug', (tester) async {
    final h = await ShellHarness.start(tester);
    await h.tapPlus();
    await typeKeys(tester, '12,345');
    await tester.longPress(keypadKey('Стереть'));
    await tester.pumpAndSettle();
    await typeKeys(tester, ',,');

    final expense = [
      for (final r in h.records)
        if (r.loggerName == 'expense') r,
    ];
    expect(expense.where((r) => r.level > Level.FINE), isEmpty);
    expect(
      expense.map((r) => r.message),
      containsAllInOrder([
        'new expense opened date=2026-10-19 from=today today=2026-10-19',
        'keypad digit 1 → text=1 kopecks=100',
        'keypad digit 2 → text=12 kopecks=1200',
        'keypad comma → text=12, kopecks=1200',
        'keypad digit 3 → text=12,3 kopecks=1230',
        'keypad digit 4 → text=12,34 kopecks=1234',
        'keypad digit 5 rejected: only 2 digits after comma text=12,34',
        'keypad clear: amount reset by long press on backspace',
        'keypad comma → text=0, kopecks=0',
        'keypad comma rejected: comma is already entered text=0,',
      ]),
    );
  });
}
