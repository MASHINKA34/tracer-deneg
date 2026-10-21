import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/repositories/expenses_repository.dart';
import 'package:milionchik/data/repositories/outbox_queue.dart';
import 'package:milionchik/features/month/day_sheet.dart';
import 'package:shared/shared.dart';

import 'expense_delete_harness.dart';

void main() {
  testWidgets('смахивание «Пятёрочки» в «Сегодня»: строки нет, итог дня '
      '1 100 → 460, снекбар «Трата 640 ₽ удалена · Отменить» над меню как '
      '43:4434, в очереди delete с отсрочкой 5 с, info-лог с id и откуда', (
    tester,
  ) async {
    final h = await DeleteHarness.start(tester);
    expect(h.inToday(find.text(rub('1 100'))), findsOneWidget);

    await h.swipe(h.todayRow('Пятёрочка · 18:40'));

    expect(h.todayRow('Пятёрочка · 18:40'), findsNothing);
    expect(h.todayRow('Метро, 2 поездки · 12:40'), findsOneWidget);
    expect(h.inToday(find.text(rub('460'))), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('^19 октября, потрачено 460 ')),
      findsOneWidget,
    );
    expect(h.snackbar, findsOneWidget);
    expect(find.text('Трата ${rub('640')} удалена'), findsOneWidget);
    expect(h.undoButton, findsOneWidget);
    final rect = tester.getRect(h.snackbar);
    expect(rect.left, 12);
    expect(rect.right, 348);
    expect(rect.height, 44);
    expect(rect.bottom, h.navTop - 21);
    expect(rect.bottom, 698);

    expect(await h.stored(h.pyaterochka.id), isNull);
    final delete = (await h.outbox()).last;
    expect(delete.op, SyncOp.delete);
    expect(delete.entityId, h.pyaterochka.id);
    expect(delete.notBefore!.difference(delete.createdAt), expenseUndoWindow);
    expect(
      h.messages('expense', Level.INFO),
      contains(
        matches(
          '^expense deleted id=${h.pyaterochka.id} budgetId=${h.budgetId} '
          r'from=today swipe in \d+ms, undo snackbar for 5s$',
        ),
      ),
    );
  });

  testWidgets('«Отменить» через 4 с: трата снова в «Сегодня» и в календаре, '
      'delete снят из очереди, снекбар скрыт, info-лог inTime=true', (
    tester,
  ) async {
    final h = await DeleteHarness.start(tester);
    final outboxBefore = (await h.outbox()).length;
    await h.swipe(h.todayRow('Пятёрочка · 18:40'));
    await h.waitSinceDelete(const Duration(seconds: 4));
    expect(h.snackbar, findsOneWidget);

    await h.tapUndo();

    expect(h.todayRow('Пятёрочка · 18:40'), findsOneWidget);
    expect(h.inToday(find.text(rub('1 100'))), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('^19 октября, потрачено 1${nbsp}100 ')),
      findsOneWidget,
    );
    expect(h.snackbar, findsNothing);
    expect(await h.stored(h.pyaterochka.id), isNotNull);
    expect(await h.outbox(), hasLength(outboxBefore));
    expect(
      h.messages('expense', Level.INFO),
      contains(
        matches(
          '^expense undo id=${h.pyaterochka.id} from=today swipe '
          r'inTime=true after 4\d\d\dms of 5000ms: expense restored in \d+ms$',
        ),
      ),
    );

    await h.wait(const Duration(seconds: 2));
    expect(h.todayRow('Пятёрочка · 18:40'), findsOneWidget);
    expect(
      h.messages('expense', Level.FINE),
      isNot(contains(startsWith('expense undo window expired'))),
    );
  });

  testWidgets('через 5 с (подменённые часы) снекбар уходит, трата остаётся '
      'удалённой, итог дня 460 ₽, delete в очереди готов к отправке, '
      'debug-лог об истечении окна', (tester) async {
    final h = await DeleteHarness.start(tester);
    await h.swipe(h.todayRow('Пятёрочка · 18:40'));
    await h.waitSinceDelete(const Duration(milliseconds: 4999));
    expect(h.snackbar, findsOneWidget);
    expect(h.undoButton.hitTestable(), findsOneWidget);
    expect(await h.due(), isNot(contains(_deleteOf(h.pyaterochka.id))));

    await h.wait(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();

    expect(h.snackbar, findsNothing);
    expect(h.todayRow('Пятёрочка · 18:40'), findsNothing);
    expect(h.inToday(find.text(rub('460'))), findsOneWidget);
    expect(await h.stored(h.pyaterochka.id), isNull);
    expect(await h.due(), contains(_deleteOf(h.pyaterochka.id)));
    expect(
      h.messages('expense', Level.FINE),
      contains(
        'expense undo window expired id=${h.pyaterochka.id} after 5000ms: '
        'snackbar hidden, expense stays deleted, outbox delete is due',
      ),
    );

    expect(
      await tester.runAsync(() => h.expenses.undoDelete(h.pyaterochka.id)),
      isFalse,
    );
  });

  testWidgets('второе удаление заменяет снекбар: виден один «Трата 250 ₽ '
      'удалена», «Отменить» возвращает только «Метро», «Пятёрочка» остаётся '
      'удалённой', (tester) async {
    final h = await DeleteHarness.start(tester);
    await h.swipe(h.todayRow('Пятёрочка · 18:40'));
    await h.wait(const Duration(seconds: 2));
    await h.swipe(h.todayRow('Метро, 2 поездки · 12:40'));

    expect(h.snackbar, findsOneWidget);
    expect(find.text('Трата ${rub('250')} удалена'), findsOneWidget);
    expect(find.text('Трата ${rub('640')} удалена'), findsNothing);
    expect(
      find.bySemanticsLabel(RegExp('^19 октября, потрачено 210 ')),
      findsOneWidget,
    );
    expect(
      h.messages('expense', Level.FINE),
      contains(
        'expense undo offer id=${h.pyaterochka.id} replaced by '
        'id=${h.metro.id}: id=${h.pyaterochka.id} stays deleted',
      ),
    );

    await h.wait(const Duration(seconds: 4));
    await h.tapUndo();

    expect(h.todayRow('Метро, 2 поездки · 12:40'), findsOneWidget);
    expect(h.todayRow('Пятёрочка · 18:40'), findsNothing);
    expect(h.inToday(find.text(rub('460'))), findsOneWidget);
    expect(await h.stored(h.metro.id), isNotNull);
    expect(await h.stored(h.pyaterochka.id), isNull);
    expect(await h.due(), contains(_deleteOf(h.pyaterochka.id)));
    expect(await h.due(), isNot(contains(_deleteOf(h.metro.id))));
  });

  testWidgets('шторка дня 19 октября: смахивание убирает трату из шторки, '
      'снекбар виден поверх шторки, «Отменить» возвращает её в шторку', (
    tester,
  ) async {
    final h = await DeleteHarness.start(tester);
    await h.openDay('19 октября');
    expect(find.byType(DaySheet), findsOneWidget);

    await h.swipe(h.dayRow('Кофе с собой · 09:15'));

    expect(h.dayRow('Кофе с собой · 09:15'), findsNothing);
    expect(h.inDay(find.text(rub('890'))), findsOneWidget);
    expect(find.text('Трата ${rub('210')} удалена'), findsOneWidget);
    final hit = tester.hitTestOnBinding(tester.getCenter(h.undoButton));
    expect(
      hit.path.any((e) => e.target == tester.renderObject(h.undoButton)),
      isTrue,
      reason: '«Отменить» не закрыт шторкой',
    );
    expect(
      h.messages('expense', Level.INFO),
      contains(
        matches(
          '^expense deleted id=${h.coffee.id} budgetId=${h.budgetId} '
          r'from=day sheet swipe in \d+ms',
        ),
      ),
    );

    await h.tapUndo();

    expect(find.byType(DaySheet), findsOneWidget);
    expect(h.dayRow('Кофе с собой · 09:15'), findsOneWidget);
    expect(h.inDay(find.text(rub('1 100'))), findsOneWidget);
  });

  testWidgets('TalkBack: у строки траты действие «Удалить трату» — удаляет '
      'со снекбаром, как смахивание', (tester) async {
    final semantics = tester.ensureSemantics();
    final h = await DeleteHarness.start(tester);
    final label = 'Продукты, Пятёрочка, 18:40, 640 рублей';
    final node = tester.getSemantics(find.bySemanticsLabel(label));
    expect(node.getSemanticsData().customSemanticsActionIds, isNotEmpty);

    tester.semantics.customAction(
      find.semantics.byLabel(label),
      CustomSemanticsAction(label: 'Удалить трату'),
    );
    await h.settle();

    expect(h.todayRow('Пятёрочка · 18:40'), findsNothing);
    expect(find.text('Трата ${rub('640')} удалена'), findsOneWidget);
    expect(
      h.messages('expense', Level.INFO),
      contains(
        startsWith(
          'expense deleted id=${h.pyaterochka.id} budgetId=${h.budgetId} '
          'from=today talkback action',
        ),
      ),
    );
    semantics.dispose();
  });

  testWidgets('шрифт 2.0 на 320 dp: текст снекбара переносится на две '
      'строки без уменьшения, снекбар в пределах экрана над меню', (
    tester,
  ) async {
    final h = await DeleteHarness.start(
      tester,
      size: const Size(320, 800),
      textScale: 2,
    );
    await h.swipe(h.todayRow('Пятёрочка · 18:40'));

    final rect = tester.getRect(h.snackbar);
    expect(rect.left, 12);
    expect(rect.right, 308);
    expect(rect.height, greaterThan(44));
    expect(rect.bottom, h.navTop - 21);
    final text = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: h.snackbar,
        matching: find.text('Трата ${rub('640')} удалена'),
      ),
    );
    expect(text.textScaler.scale(14), 28);
    expect(text.size.height, greaterThanOrEqualTo(2 * 20 * 2));
    expect(tester.getRect(h.undoButton).right, lessThanOrEqualTo(rect.right));
  });
}

Matcher _deleteOf(String id) => isA<PendingChange>()
    .having((c) => c.change.op, 'op', SyncOp.delete)
    .having((c) => c.change.id, 'id', id);
