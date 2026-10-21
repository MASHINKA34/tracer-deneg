import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:milionchik/core/router.dart';
import 'package:milionchik/data/current_user.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/queries/month_queries.dart';
import 'package:milionchik/data/repositories/expenses_repository.dart';
import 'package:milionchik/data/repositories/outbox_queue.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:milionchik/features/expense/edit_expense_screen.dart';
import 'package:milionchik/features/expense/expense_amount_sheet.dart';
import 'package:milionchik/features/month/day_sheet.dart';
import 'package:milionchik/ui/components/bottom_nav.dart';
import 'package:milionchik/ui/components/button.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';
import '../month/month_fixture.dart';
import '../shell/shell_harness.dart';

final LocalDate october19 = LocalDate(2026, 10, 19);

final class EditHarness {
  EditHarness(this.shell, this.budgetId, this.pyaterochka);

  final ShellHarness shell;
  final String budgetId;
  final Expense pyaterochka;

  WidgetTester get tester => shell.tester;

  AppDatabase get db => shell.db;

  static Future<EditHarness> start(
    WidgetTester tester, {
    Size size = const Size(360, 800),
    double bottomInset = 0,
    double topInset = 0,
  }) async {
    final db = openTestDatabase();
    final (budgetId, pyaterochka) = (await tester.runAsync(() async {
      final budgetId = await seedMockupOctober(db);
      final today = await DriftMonthQueries(db)
          .watchDayExpenses(budgetId, october19)
          .first;
      return (budgetId, today.singleWhere((e) => e.comment == 'Пятёрочка'));
    }))!;
    final shell = await ShellHarness.start(
      tester,
      db: db,
      size: size,
      bottomInset: bottomInset,
      topInset: topInset,
    );
    return EditHarness(shell, budgetId, pyaterochka);
  }

  ExpensesRepository get expenses => DriftExpensesRepository(
    db,
    currentUser: LocalPrefsCurrentUser(DriftPrefsRepository(db)),
    outbox: DriftOutboxQueue(db),
  );

  Future<List<Expense>> day(LocalDate day) async => (await tester.runAsync(
    () => DriftMonthQueries(db).watchDayExpenses(budgetId, day).first,
  ))!;

  Future<Expense?> stored(String id) =>
      tester.runAsync<Expense?>(() => expenses.watchById(id).first);

  Future<void> deleteWhileShown(String id) async {
    var done = false;
    unawaited(expenses.delete(id).whenComplete(() => done = true));
    for (var i = 0; i < 50 && !done; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(done, isTrue, reason: 'expense $id was not deleted');
    await tester.pumpAndSettle();
  }

  Future<int> outboxSize() async =>
      (await tester.runAsync(() => db.select(db.outbox).get()))!.length;

  Future<void> openDay(String date) async {
    await tester.tap(find.bySemanticsLabel(RegExp('^$date')));
    await tester.pumpAndSettle();
  }

  Future<void> openFromDaySheet(String date, String rowText) async {
    await openDay(date);
    await tester.tap(
      find.descendant(of: find.byType(DaySheet), matching: find.text(rowText)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(EditExpenseScreen), findsOneWidget);
  }

  Future<void> openById(String id) async {
    unawaited(
      GoRouter.of(tester.element(find.byType(AppBottomNav)))
          .push<void>(AppRoutes.expenseOf(id)),
    );
    await tester.pumpAndSettle();
  }

  Finder inEdit(Finder finder) =>
      find.descendant(of: find.byType(EditExpenseScreen), matching: finder);

  Finder get saveButton => inEdit(find.widgetWithText(AppButton, 'Сохранить'));

  bool get saveEnabled =>
      tester.widget<AppButton>(saveButton).onPressed != null;

  Finder row(String label) => inEdit(find.bySemanticsLabel(RegExp('^$label')));

  String rowLabel(String label) => tester.getSemantics(row(label)).label;

  Finder get amount => find.byKey(const ValueKey('edit-expense-amount'));

  Future<void> tapRow(String label) async {
    await tester.ensureVisible(row(label));
    await tester.pumpAndSettle();
    await tester.tap(row(label));
    await tester.pumpAndSettle();
  }

  Future<void> typeAmount(String keys) async {
    await tester.tap(amount);
    await tester.pumpAndSettle();
    expect(find.byType(ExpenseAmountSheet), findsOneWidget);
    await pressKeys(keys);
    await tester.tap(
      find.descendant(
        of: find.byType(ExpenseAmountSheet),
        matching: find.text('Готово'),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pressKeys(String keys) async {
    for (final key in keys.split('')) {
      final label = key == '<' ? 'Стереть' : key;
      await tester.tap(
        find.descendant(
          of: find.byType(ExpenseAmountSheet),
          matching: find.bySemanticsLabel(label),
        ),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> tapSave() async {
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
  }
}
