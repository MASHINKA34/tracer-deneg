import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/features/expense/edit_expense_screen.dart';
import 'package:milionchik/features/month/day_sheet.dart';
import 'package:milionchik/features/month/month_screen.dart';
import 'package:milionchik/ui/components/button.dart';
import 'package:shared/shared.dart';

import 'expense_delete_harness.dart';

Finder _inEdit(Finder finder) =>
    find.descendant(of: find.byType(EditExpenseScreen), matching: finder);

Future<void> _tapDeleteButton(WidgetTester tester) async {
  final button = _inEdit(find.widgetWithText(AppButton, 'Удалить трату'));
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
}

Future<void> _settleWatchingMissing(DeleteHarness h) async {
  for (var i = 0; i < 40; i++) {
    await h.tester.pump(const Duration(milliseconds: 16));
    expect(
      find.text('Трата не найдена'),
      findsNothing,
      reason: 'экран траты не должен мигать «Трата не найдена» при уходе',
    );
  }
  await h.tester.pumpAndSettle();
}

void main() {
  testWidgets('«Сегодня» → «Пятёрочка» → «Удалить трату»: назад на главную, '
      'трата удалена, снекбар «Трата 640 ₽ удалена» над меню, без '
      'мигания «Трата не найдена»; «Отменить» возвращает трату', (
    tester,
  ) async {
    final h = await DeleteHarness.start(tester);
    await tester.tap(h.todayRow('Пятёрочка · 18:40'));
    await tester.pumpAndSettle();
    expect(find.byType(EditExpenseScreen), findsOneWidget);

    await _tapDeleteButton(tester);
    await _settleWatchingMissing(h);

    expect(find.byType(EditExpenseScreen), findsNothing);
    expect(find.byType(MonthScreen), findsOneWidget);
    expect(h.todayRow('Пятёрочка · 18:40'), findsNothing);
    expect(h.inToday(find.text(rub('460'))), findsOneWidget);
    expect(find.text('Трата ${rub('640')} удалена'), findsOneWidget);
    expect(tester.getRect(h.snackbar).bottom, h.navTop - 21);
    expect(await h.stored(h.pyaterochka.id), isNull);
    expect(
      h.messages('expense', Level.INFO),
      contains(
        matches(
          '^expense deleted id=${h.pyaterochka.id} budgetId=${h.budgetId} '
          r'from=edit button in \d+ms, undo snackbar for 5s$',
        ),
      ),
    );
    expect(
      h.messages('expense', Level.INFO),
      isNot(contains(contains('deleted while the screen was open'))),
    );
    expect(
      h.messages('expense', Level.WARNING),
      isNot(contains(contains('not found'))),
    );

    await h.tapUndo();
    expect(h.todayRow('Пятёрочка · 18:40'), findsOneWidget);
    expect(h.inToday(find.text(rub('1 100'))), findsOneWidget);
  });

  testWidgets('шторка дня → «Метро» → корзина в шапке: назад к шторке дня, '
      'трата из шторки ушла, снекбар «Трата 250 ₽ удалена» поверх шторки, '
      'несохранённая правка суммы не записана', (tester) async {
    final h = await DeleteHarness.start(tester);
    await h.openDay('19 октября');
    await tester.tap(h.dayRow('Метро, 2 поездки · 12:40'));
    await tester.pumpAndSettle();
    expect(find.byType(EditExpenseScreen), findsOneWidget);

    await tester.tap(_inEdit(find.bySemanticsLabel('Удалить трату')).first);
    await _settleWatchingMissing(h);

    expect(find.byType(EditExpenseScreen), findsNothing);
    expect(find.byType(DaySheet), findsOneWidget);
    expect(h.dayRow('Метро, 2 поездки · 12:40'), findsNothing);
    expect(h.inDay(find.text(rub('850'))), findsOneWidget);
    expect(find.text('Трата ${rub('250')} удалена'), findsOneWidget);
    expect(h.undoButton.hitTestable(), findsOneWidget);
    expect(
      h.messages('expense', Level.INFO),
      contains(startsWith('expense deleted id=${h.metro.id} ')),
    );
    expect(
      h.messages('expense', Level.INFO).last,
      contains('from=edit top bar'),
    );

    await h.tapUndo();
    expect(h.dayRow('Метро, 2 поездки · 12:40'), findsOneWidget);
    final restored = (await h.stored(h.metro.id))!;
    expect(restored.amount, const Money.rubles(250));
  });

  testWidgets('удаление с экрана траты, пока снекбар прошлого удаления ещё '
      'виден: остаётся один снекбар — о последней трате', (tester) async {
    final h = await DeleteHarness.start(tester);
    await h.swipe(h.todayRow('Кофе с собой · 09:15'));
    expect(find.text('Трата ${rub('210')} удалена'), findsOneWidget);

    await tester.tap(h.todayRow('Пятёрочка · 18:40'));
    await tester.pumpAndSettle();
    await _tapDeleteButton(tester);
    await h.settle();

    expect(h.snackbar, findsOneWidget);
    expect(find.text('Трата ${rub('640')} удалена'), findsOneWidget);
    expect(find.text('Трата ${rub('210')} удалена'), findsNothing);
    expect(await h.stored(h.coffee.id), isNull);
    expect(await h.stored(h.pyaterochka.id), isNull);
  });
}
