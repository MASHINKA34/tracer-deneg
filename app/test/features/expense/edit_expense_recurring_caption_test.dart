import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/data/current_user.dart';
import 'package:milionchik/data/recurring_service.dart';
import 'package:milionchik/data/repositories/categories_repository.dart';
import 'package:milionchik/data/repositories/outbox_queue.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:milionchik/data/repositories/recurring_repository.dart';
import 'package:milionchik/features/expense/edit_expense_screen.dart';
import 'package:milionchik/features/month/day_sheet.dart';
import 'package:milionchik/ui/tokens/tokens.g.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';
import '../../support/test_fonts.dart';
import 'edit_expense_harness.dart';

const String _named = 'Создано регулярной тратой «Спортзал»';
const String _unnamed = 'Создано регулярной тратой';
const String _syncHint =
    'Изменения уходят на сервер сразу или когда появится сеть.';

final YearMonth _september = YearMonth(2026, 9);
final YearMonth _october = YearMonth(2026, 10);

DriftRecurringRepository _rules(EditHarness h) => DriftRecurringRepository(
  h.db,
  currentUser: LocalPrefsCurrentUser(DriftPrefsRepository(h.db)),
  outbox: DriftOutboxQueue(h.db),
);

Future<RecurringRule> _gym(EditHarness h) async {
  final rule = await h.tester.runAsync(() async {
    final user = LocalPrefsCurrentUser(DriftPrefsRepository(h.db));
    final categories = await DriftCategoriesRepository(
      h.db,
      currentUser: user,
      outbox: DriftOutboxQueue(h.db),
    ).watchByBudget(h.budgetId).first;
    final rule = await _rules(h).create(
      budgetId: h.budgetId,
      categoryId: categories.firstWhere((c) => c.name == 'Спорт').id,
      title: 'Спортзал',
      amount: const Money.rubles(2500),
      dayOfMonth: 5,
      startMonth: _september,
    );
    await _run(h);
    return rule;
  });
  await h.tester.pumpAndSettle();
  return rule!;
}

Future<RecurringRunResult> _run(EditHarness h) => RecurringService.forDatabase(
  h.db,
  clock: Clock(now: () => testNow),
).run(RecurringRunReason.startup);

Future<void> _deleteRule(EditHarness h, String id) async {
  var done = false;
  unawaited(_rules(h).delete(id).whenComplete(() => done = true));
  for (var i = 0; i < 50 && !done; i++) {
    await h.tester.pump(const Duration(milliseconds: 20));
  }
  expect(done, isTrue, reason: 'recurring rule $id was not deleted');
  await h.tester.pumpAndSettle();
}

Finder _inDay(Finder finder) =>
    find.descendant(of: find.byType(DaySheet), matching: finder);

List<String> _notFoundLines(EditHarness h) => [
  for (final r in h.shell.records)
    if (r.message.startsWith('recurring rule not found for expense'))
      '${r.level.name} [${r.loggerName}] ${r.message}',
];

void main() {
  testWidgets('шторка дня 5 октября: строка «Спортзал» как у обычной траты, '
      'без пометки; в правке под полями «Создано регулярной тратой '
      '«Спортзал»» стилем подписи о синхронизации, над ней; у обычной '
      '«Пятёрочки» подписи нет', (tester) async {
    await loadTestFonts();
    final h = await EditHarness.start(tester, topInset: 32);
    await _gym(h);
    await tester.pumpAndSettle();

    await h.openDay('5 октября');
    expect(_inDay(find.text('Спортзал')), findsOneWidget);
    expect(_inDay(find.textContaining('регулярн')), findsNothing);
    final daySemantics = tester
        .getSemantics(find.byType(DaySheet))
        .getSemanticsData()
        .label;
    expect(daySemantics, isNot(contains('регулярн')));

    await tester.tap(_inDay(find.text('Спортзал')));
    await tester.pumpAndSettle();
    expect(find.byType(EditExpenseScreen), findsOneWidget);
    expect(h.rowLabel('Комментарий'), 'Комментарий, Спортзал');

    final caption = h.inEdit(find.text(_named));
    final hint = h.inEdit(find.text(_syncHint));
    expect(caption, findsOneWidget);
    expect(h.inEdit(find.textContaining('регулярн')), findsOneWidget);

    final captionStyle = tester.widget<Text>(caption).style!;
    final hintStyle = tester.widget<Text>(hint).style!;
    expect(captionStyle, hintStyle);
    expect(captionStyle.fontSize, 12);
    expect(captionStyle.color, neutralLight.textTertiary);

    final fieldsBottom = tester.getRect(h.row('Бюджет')).bottom + 4;
    expect(tester.getRect(caption).top, fieldsBottom + 16);
    expect(tester.getRect(caption).left, 16);
    expect(tester.getRect(caption).height, 16);
    expect(tester.getRect(hint).top, tester.getRect(caption).bottom);
    expect(tester.getRect(h.saveButton).top, 504);

    await h.shell.systemBack();
    await h.shell.systemBack();
    await h.openById(h.pyaterochka.id);
    expect(h.rowLabel('Комментарий'), 'Комментарий, Пятёрочка');
    expect(h.inEdit(find.textContaining('регулярн')), findsNothing);
    expect(h.inEdit(find.text(_syncHint)), findsOneWidget);
    expect(tester.getRect(h.saveButton).top, 488);
    expect(_notFoundLines(h), isEmpty);
  });

  testWidgets('правило «Спортзал» удалено: «Создано регулярной тратой» без '
      'названия; debug [expense] «recurring rule not found for expense» '
      'с id траты и правила, reason=deleted, один раз; названия нет ни в '
      'одном логе', (tester) async {
    final h = await EditHarness.start(tester);
    final rule = await _gym(h);
    await _deleteRule(h, rule.id);
    final expenseId = recurringExpenseId(rule.id, _october);

    await h.openById(expenseId);
    expect(h.rowLabel('Комментарий'), 'Комментарий, Спортзал');
    expect(h.inEdit(find.text(_unnamed)), findsOneWidget);
    expect(h.inEdit(find.textContaining('«')), findsNothing);

    await h.typeAmount('<<<<2700');
    expect(h.inEdit(find.text(_unnamed)), findsOneWidget);

    expect(_notFoundLines(h), [
      'FINE [expense] recurring rule not found for expense id=$expenseId '
          'recurringId=${rule.id} reason=deleted → caption without rule name',
    ]);
    for (final r in h.shell.records) {
      expect(r.message, isNot(contains('Спортзал')), reason: r.message);
      expect('${r.error}', isNot(contains('Спортзал')), reason: r.message);
    }
  });

  testWidgets('правило удалили, пока открыта правка: подпись теряет название, '
      'reason=deleted', (tester) async {
    final h = await EditHarness.start(tester);
    final rule = await _gym(h);
    final expenseId = recurringExpenseId(rule.id, _october);
    await h.openById(expenseId);
    expect(h.inEdit(find.text(_named)), findsOneWidget);
    expect(_notFoundLines(h), isEmpty);

    await _deleteRule(h, rule.id);

    expect(find.byType(EditExpenseScreen), findsOneWidget);
    expect(h.inEdit(find.text(_named)), findsNothing);
    expect(h.inEdit(find.text(_unnamed)), findsOneWidget);
    expect(_notFoundLines(h), [
      'FINE [expense] recurring rule not found for expense id=$expenseId '
          'recurringId=${rule.id} reason=deleted → caption without rule name',
    ]);
  });

  testWidgets('трата пришла с сервера раньше своего правила: «Создано '
      'регулярной тратой» без названия, reason=missing', (tester) async {
    final h = await EditHarness.start(tester);
    final ruleId = newId();
    final expenseId = recurringExpenseId(ruleId, _october);
    final at = DateTime.utc(2026, 10, 5, 6);
    await tester.runAsync(
      () => h.expenses.applyFromServer([
        Expense(
          id: expenseId,
          budgetId: h.budgetId,
          categoryId: h.pyaterochka.categoryId,
          amount: const Money.rubles(2500),
          spentOn: LocalDate(2026, 10, 5),
          comment: 'Спортзал',
          authorId: 'user-server',
          recurringId: ruleId,
          recurringMonth: _october,
          createdAt: at,
          updatedAt: at,
          updatedBy: 'user-server',
          seq: 7,
        ),
      ]),
    );

    await h.openById(expenseId);
    expect(h.inEdit(find.text(_unnamed)), findsOneWidget);
    expect(h.inEdit(find.textContaining('«')), findsNothing);
    expect(_notFoundLines(h), [
      'FINE [expense] recurring rule not found for expense id=$expenseId '
          'recurringId=$ruleId reason=missing → caption without rule name',
    ]);
  });

  testWidgets('правка траты «Спортзал» за октябрь меняет только её: сумма '
      '2 700, recurringId и месяц на месте, правило и сентябрьская трата '
      'прежние; повторный запуск генератора правку не трогает; подпись с '
      'названием остаётся', (tester) async {
    final h = await EditHarness.start(tester);
    final rule = await _gym(h);
    final octoberId = recurringExpenseId(rule.id, _october);
    final septemberId = recurringExpenseId(rule.id, _september);
    final september = await h.stored(septemberId);
    expect(september, isNotNull);

    await h.openById(octoberId);
    await h.typeAmount('<<<<2700');
    await h.tapSave();
    expect(find.byType(EditExpenseScreen), findsNothing);

    final october = (await h.stored(octoberId))!;
    expect(october.amount, const Money.rubles(2700));
    expect(october.recurringId, rule.id);
    expect(october.recurringMonth, _october);
    expect(await h.stored(septemberId), september);
    final storedRule = await tester.runAsync(
      () => _rules(h).watchById(rule.id).first,
    );
    expect(storedRule, rule);

    final rerun = (await tester.runAsync(() => _run(h)))!;
    expect(rerun.created, 0);
    expect((await h.stored(octoberId))!.amount, const Money.rubles(2700));

    await h.openById(octoberId);
    expect(h.inEdit(find.text('2 700'.replaceAll(' ', nbsp))), findsOneWidget);
    expect(h.inEdit(find.text(_named)), findsOneWidget);
  });
}
