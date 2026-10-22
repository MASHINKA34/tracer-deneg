import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/features/expense/edit_expense_screen.dart';
import 'package:milionchik/features/expense/expense_comment_sheet.dart';
import 'package:milionchik/features/expense/expense_date_sheet.dart';
import 'package:milionchik/features/month/day_sheet.dart';
import 'package:milionchik/features/categories/categories_screen.dart';
import 'package:milionchik/ui/components/category_tile.dart';
import 'package:milionchik/ui/components/snackbar.dart';
import 'package:shared/shared.dart';

import 'edit_expense_harness.dart';

String _rub(String digits) => '${digits.replaceAll(' ', nbsp)}$nbsp₽';

Finder _inDay(Finder finder) =>
    find.descendant(of: find.byType(DaySheet), matching: finder);

Iterable<LogRecord> _expenseInfo(EditHarness h) => h.shell.records.where(
  (r) => r.loggerName == 'expense' && r.level == Level.INFO,
);

void main() {
  testWidgets('шторка дня 19 октября → «Пятёрочка» → экран как 43:4368: '
      '640 ₽, Продукты, «Сегодня, 19 октября», Пятёрочка, 👛 Личный; '
      '«Сохранить» неактивна, пока ничего не изменилось', (tester) async {
    final h = await EditHarness.start(tester);
    await h.openFromDaySheet('19 октября', 'Пятёрочка · 18:40');

    expect(h.inEdit(find.text('Трата')), findsOneWidget);
    expect(h.inEdit(find.text('640')), findsOneWidget);
    expect(h.inEdit(find.text('₽')), findsOneWidget);
    expect(
      h.inEdit(find.text('Нажми на сумму — откроется клавиатура')),
      findsOneWidget,
    );
    expect(h.rowLabel('Категория'), 'Категория, Продукты');
    expect(h.rowLabel('Дата'), 'Дата, Сегодня, 19$nbspоктября');
    expect(h.rowLabel('Комментарий'), 'Комментарий, Пятёрочка');
    expect(h.rowLabel('Бюджет'), 'Бюджет, 👛 Личный');
    expect(h.inEdit(find.text('Удалить трату')), findsOneWidget);
    expect(h.saveEnabled, isFalse);

    await h.tapSave();
    expect(find.byType(EditExpenseScreen), findsOneWidget);
    expect(
      _expenseInfo(h).where((r) => r.message.startsWith('expense up')),
      isEmpty,
    );
  });

  testWidgets('«Сохранить» неактивна без изменений: шторки даты и суммы '
      'закрыты без «Готово», сумма и дата возвращены к прежним — снова '
      'неактивна; после правки активна', (tester) async {
    final h = await EditHarness.start(tester);
    await h.openById(h.pyaterochka.id);
    expect(h.saveEnabled, isFalse);

    await h.tapRow('Дата');
    expect(find.byType(ExpenseDateSheet), findsOneWidget);
    await tester.tap(find.text('Вчера'));
    await tester.pumpAndSettle();
    await h.shell.systemBack();
    expect(find.byType(ExpenseDateSheet), findsNothing);
    expect(h.rowLabel('Дата'), 'Дата, Сегодня, 19$nbspоктября');
    expect(h.saveEnabled, isFalse);

    await tester.tap(h.amount);
    await tester.pumpAndSettle();
    await h.pressKeys('<<<99');
    await h.shell.systemBack();
    expect(h.inEdit(find.text('640')), findsOneWidget);
    expect(h.saveEnabled, isFalse);

    await h.typeAmount('<<<700');
    expect(h.inEdit(find.text('700')), findsOneWidget);
    expect(h.saveEnabled, isTrue);
    await h.typeAmount('<<<640');
    expect(h.saveEnabled, isFalse);

    await h.tapRow('Дата');
    await tester.tap(find.text('Вчера'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Готово'));
    await tester.pumpAndSettle();
    expect(h.rowLabel('Дата'), 'Дата, Вчера, 18$nbspоктября');
    expect(h.saveEnabled, isTrue);
    await h.tapRow('Дата');
    await tester.tap(find.text('Сегодня'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Готово'));
    await tester.pumpAndSettle();
    expect(h.saveEnabled, isFalse);
  });

  testWidgets('шторка дня → трата → сумма 640 → 1 250 → «Сохранить»: назад '
      'к шторке дня, 1 250 ₽ в шторке и 1 710 ₽ в календаре, в базе и в '
      'очереди отправки новая сумма, остальное как было', (tester) async {
    final h = await EditHarness.start(tester);
    final outboxBefore = await h.outboxSize();
    await h.openFromDaySheet('19 октября', 'Пятёрочка · 18:40');

    await h.typeAmount('<<<1250');
    expect(h.inEdit(find.text('1${nbsp}250')), findsOneWidget);
    expect(h.saveEnabled, isTrue);
    await h.tapSave();

    expect(find.byType(EditExpenseScreen), findsNothing);
    expect(find.byType(DaySheet), findsOneWidget);
    expect(_inDay(find.text(_rub('1 250'))), findsOneWidget);
    expect(_inDay(find.text(_rub('640'))), findsNothing);
    expect(
      find.bySemanticsLabel(RegExp('^19 октября, потрачено 1${nbsp}710 ')),
      findsOneWidget,
    );

    final saved = (await h.stored(h.pyaterochka.id))!;
    expect(saved.amount, const Money.rubles(1250));
    expect(saved.categoryId, h.pyaterochka.categoryId);
    expect(saved.spentOn, october19);
    expect(saved.comment, 'Пятёрочка');
    expect(saved.createdAt, h.pyaterochka.createdAt);
    expect(await h.outboxSize(), outboxBefore + 1);

    final info = _expenseInfo(h).map((r) => r.message).toList();
    expect(info, contains('expense edit opened id=${h.pyaterochka.id}'));
    expect(
      info.where((m) => m.startsWith('expense updated')).single,
      matches(
        '^expense updated id=${h.pyaterochka.id} budgetId=${h.budgetId} '
        r'fields=amount in \d+ms$',
      ),
    );
    expect(
      h.shell.navDebug(),
      contains('expense edit closed id=${h.pyaterochka.id} by save'),
    );
  });

  testWidgets('смена даты на «Позавчера» переносит трату с 19 на 17 '
      'октября: в шторке 19-го её нет, в календаре 460 ₽ и 2 090 ₽', (
    tester,
  ) async {
    final h = await EditHarness.start(tester);
    expect(await h.day(LocalDate(2026, 10, 17)), hasLength(2));
    await h.openFromDaySheet('19 октября', 'Пятёрочка · 18:40');

    await h.tapRow('Дата');
    await tester.tap(find.text('Позавчера'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Готово'));
    await tester.pumpAndSettle();
    expect(h.rowLabel('Дата'), 'Дата, 17$nbspоктября');
    await h.tapSave();

    expect(find.byType(DaySheet), findsOneWidget);
    expect(_inDay(find.textContaining('Пятёрочка')), findsNothing);
    expect(
      find.bySemanticsLabel(RegExp('^19 октября, потрачено 460 ')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('^17 октября, потрачено 2${nbsp}090 ')),
      findsOneWidget,
    );
    final moved = await h.day(LocalDate(2026, 10, 17));
    expect(moved, hasLength(3));
    expect(
      moved.singleWhere((e) => e.id == h.pyaterochka.id).amount,
      const Money.rubles(640),
    );
    expect(
      _expenseInfo(h).where((r) => r.message.startsWith('expense updated')),
      [
        isA<LogRecord>().having(
          (r) => r.message,
          'message',
          contains('fields=date in'),
        ),
      ],
    );
  });

  testWidgets('категория из шторки всех категорий и комментарий из шторки '
      'комментария сохраняются; текст комментария не попадает в логи', (
    tester,
  ) async {
    final h = await EditHarness.start(tester);
    await h.openById(h.pyaterochka.id);

    await h.tapRow('Категория');
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(CategoryTile, 'Кафе'),
        matching: find.byType(InkWell),
      ),
    );
    await tester.pumpAndSettle();
    expect(h.rowLabel('Категория'), 'Категория, Кафе');

    await h.tapRow('Комментарий');
    expect(find.byType(ExpenseCommentSheet), findsOneWidget);
    await tester.enterText(find.byType(EditableText), '  Лента у дома ');
    await tester.pump();
    await tester.tap(find.text('Готово'));
    await tester.pumpAndSettle();
    expect(h.rowLabel('Комментарий'), 'Комментарий, Лента у дома');
    expect(h.saveEnabled, isTrue);
    await h.tapSave();

    final saved = (await h.stored(h.pyaterochka.id))!;
    final categories = await tester.runAsync(
      () => h.db.select(h.db.categories).get(),
    );
    expect(
      categories!.singleWhere((c) => c.id == saved.categoryId).name,
      'Кафе',
    );
    expect(saved.comment, 'Лента у дома');
    expect(saved.amount, const Money.rubles(640));
    expect(
      _expenseInfo(h).map((r) => r.message),
      contains(matches(r'fields=category,comment in \d+ms$')),
    );
    for (final r in h.shell.records) {
      expect('${r.message} ${r.error}', isNot(contains('Лента')));
    }
  });

  testWidgets('«Настроить» в шторке категорий открывает «Категории», '
      'категория траты не меняется', (tester) async {
    final h = await EditHarness.start(tester);
    await h.openById(h.pyaterochka.id);
    await h.tapRow('Категория');
    await tester.tap(find.text('Настроить'));
    await tester.pumpAndSettle();
    expect(find.byType(CategoriesScreen), findsOneWidget);
    await h.shell.systemBack();
    expect(h.rowLabel('Категория'), 'Категория, Продукты');
    expect(h.saveEnabled, isFalse);
  });

  testWidgets('«назад» с несохранённой суммой: трата в базе прежняя, в '
      'debug-логе какие поля отброшены', (tester) async {
    final h = await EditHarness.start(tester);
    await h.openFromDaySheet('19 октября', 'Пятёрочка · 18:40');
    await h.typeAmount('<<<99');
    await h.shell.systemBack();

    expect(find.byType(EditExpenseScreen), findsNothing);
    expect(find.byType(DaySheet), findsOneWidget);
    expect((await h.stored(h.pyaterochka.id))!.amount, const Money.rubles(640));
    expect(
      h.shell.records.map((r) => r.message),
      contains(
        'expense edit id=${h.pyaterochka.id} closed by back with unsaved '
        'fields=amount → changes discarded',
      ),
    );
  });

  testWidgets('ошибка записи в базу: снекбар, экран и правка остаются, '
      'error [expense] с id и полями без значений параметров SQL', (
    tester,
  ) async {
    final h = await EditHarness.start(tester);
    await tester.runAsync(
      () => h.db.customStatement(
        'CREATE TRIGGER expenses_fail BEFORE UPDATE ON expenses '
        "BEGIN SELECT RAISE(ABORT, 'disk I/O error'); END",
      ),
    );
    await h.openById(h.pyaterochka.id);
    await h.typeAmount('<<<98765,43');
    await h.tapSave();

    expect(find.byType(EditExpenseScreen), findsOneWidget);
    expect(find.byType(AppSnackbar), findsOneWidget);
    expect(
      find.text('Не удалось сохранить изменения. Попробуй ещё раз'),
      findsOneWidget,
    );
    expect(h.inEdit(find.text('98${nbsp}765,43')), findsOneWidget);
    expect(h.saveEnabled, isTrue);

    final errors = [
      for (final r in h.shell.records)
        if (r.loggerName == 'expense' && r.level == Level.SEVERE) r,
    ];
    expect(errors, hasLength(1));
    expect(
      errors.single.message,
      matches(
        '^expense update failed id=${h.pyaterochka.id} fields=amount after '
        r'\d+ms, nothing saved: SqliteException',
      ),
    );
    expect(errors.single.message, contains('disk I/O error'));
    expect(errors.single.stackTrace, isNotNull);
    for (final r in h.shell.records.where((r) => r.level >= Level.INFO)) {
      final text = '${r.message} ${r.error}';
      expect(text, isNot(contains('9876543')), reason: text);
      expect(text, isNot(contains('Пятёрочка')), reason: text);
    }
    expect((await h.stored(h.pyaterochka.id))!.amount, const Money.rubles(640));

    await tester.runAsync(
      () => h.db.customStatement('DROP TRIGGER expenses_fail'),
    );
    await h.tapSave();
    expect(find.byType(EditExpenseScreen), findsNothing);
    expect((await h.stored(h.pyaterochka.id))!.amount, Money(9876543));
  });
}
