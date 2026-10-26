import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/features/expense/new_expense_screen.dart';

import '../../support/app_scope.dart';
import '../../support/test_fonts.dart';
import '../month/month_fixture.dart';
import '../shell/shell_harness.dart';
import 'new_expense_harness.dart';

const List<String> _keys = [
  '1',
  '2',
  '3',
  '4',
  '5',
  '6',
  '7',
  '8',
  '9',
  ',',
  '0',
  'Стереть',
];

Future<ShellHarness> _open(
  WidgetTester tester, {
  required Size size,
  required double scale,
  double topInset = 24,
  double bottomInset = 48,
}) async {
  await loadTestFonts();
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  final db = openTestDatabase();
  await tester.runAsync(() => seedMockupOctober(db));
  final h = await ShellHarness.start(
    tester,
    db: db,
    size: size,
    topInset: topInset,
    bottomInset: bottomInset,
  );
  await h.tapPlus();
  return h;
}

Finder _keypad() => inNewExpense(find.byType(ExpenseKeypad));

Finder _scrollView() => inNewExpense(find.byType(CustomScrollView));

Rect _amount(WidgetTester tester) =>
    tester.getRect(find.byKey(const ValueKey('new-expense-amount')));

ScrollPosition _position(WidgetTester tester) => tester
    .state<ScrollableState>(inNewExpense(find.byType(Scrollable)))
    .position;

Iterable<String> _expenseDebug(ShellHarness h) => h.records
    .where((r) => r.loggerName == 'expense' && r.level == Level.FINE)
    .map((r) => r.message);

void main() {
  testWidgets('320 × 711 (api30 при 320 dp), шрифт 2.0: клавиатура закреплена '
      'внизу, на первом экране видны сумма и все клавиши, набранное видно '
      'сразу, категории — прокруткой над клавиатурой', (tester) async {
    final h = await _open(tester, size: const Size(320, 711), scale: 2);
    expect(tester.takeException(), isNull);

    expect(
      find.descendant(of: _scrollView(), matching: find.byType(ExpenseKeypad)),
      findsNothing,
    );
    final panel = tester.getRect(_keypad());
    expect(panel.bottom, 711);
    for (final key in _keys) {
      final rect = tester.getRect(keypadKey(key));
      expect(rect.top, greaterThanOrEqualTo(panel.top), reason: key);
      expect(rect.bottom, lessThanOrEqualTo(711 - 48), reason: key);
    }
    final amount = _amount(tester);
    expect(amount.top, greaterThan(24));
    expect(amount.bottom, lessThanOrEqualTo(panel.top));

    for (final key in ['1', '2', '5']) {
      await tester.tap(keypadKey(key));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(amountText(tester), '125');
    expect(_amount(tester).top, amount.top);
    expect(_amount(tester).bottom, lessThanOrEqualTo(panel.top));

    final tile = categoryTile('Развлечения');
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    expect(tester.getRect(tile).bottom, lessThanOrEqualTo(panel.top));
    expect(tester.getRect(_keypad()), panel);
    expect(
      _expenseDebug(h),
      contains(startsWith('new expense keypad pinned at the bottom: content ')),
    );
    expect(
      _expenseDebug(h).firstWhere((m) => m.startsWith('new expense keypad')),
      endsWith('textScale=2.00 → amount, chips and categories scroll above it'),
    );
  });

  testWidgets('клавиатура закреплена, экран прокручен к категориям: нажатие '
      'клавиши возвращает к сумме', (tester) async {
    final h = await _open(tester, size: const Size(320, 711), scale: 2);
    final amount = _amount(tester);

    _position(tester).jumpTo(_position(tester).maxScrollExtent);
    await tester.pumpAndSettle();
    expect(_amount(tester).bottom, lessThan(amount.top));

    await tester.tap(keypadKey('7'));
    await tester.pumpAndSettle();

    expect(_position(tester).pixels, 0);
    expect(_amount(tester).top, amount.top);
    expect(amountText(tester), '7');
    expect(
      _expenseDebug(h),
      contains(
        allOf(
          startsWith('new expense key pressed with the amount scrolled away '),
          endsWith('→ scrolling back to the amount'),
        ),
      ),
    );
  });

  testWidgets('без анимаций система: возврат к сумме сразу, без прокрутки', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final h = await _open(tester, size: const Size(320, 711), scale: 2);

    _position(tester).jumpTo(_position(tester).maxScrollExtent);
    await tester.pump();
    await tester.tap(keypadKey('3'));
    await tester.pump();

    expect(_position(tester).pixels, 0);
    expect(
      _expenseDebug(h),
      contains(endsWith('→ scrolling back to the amount without animation')),
    );
  });

  testWidgets('360 × 800, шрифт 1.0: всё помещается — клавиатура в общем '
      'потоке, как раньше, и не закрепляется', (tester) async {
    final h = await _open(
      tester,
      size: const Size(360, 800),
      scale: 1,
      topInset: 32,
      bottomInset: 0,
    );

    expect(
      find.descendant(of: _scrollView(), matching: find.byType(ExpenseKeypad)),
      findsOneWidget,
    );
    expect(_position(tester).maxScrollExtent, 0);
    expect(
      _expenseDebug(h).where((m) => m.startsWith('new expense keypad')),
      isEmpty,
    );
  });

  testWidgets('шрифт 2.0 → 1.0 на открытом экране: клавиатура возвращается '
      'в поток', (tester) async {
    final h = await _open(
      tester,
      size: const Size(360, 800),
      scale: 2,
      topInset: 32,
      bottomInset: 0,
    );
    expect(
      find.descendant(of: _scrollView(), matching: find.byType(ExpenseKeypad)),
      findsNothing,
    );

    tester.platformDispatcher.textScaleFactorTestValue = 1;
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: _scrollView(), matching: find.byType(ExpenseKeypad)),
      findsOneWidget,
    );
    expect(
      _expenseDebug(h),
      contains(
        allOf(
          startsWith('new expense keypad back in the flow: content '),
          endsWith('textScale=1.00 → everything fits'),
        ),
      ),
    );
  });
}
