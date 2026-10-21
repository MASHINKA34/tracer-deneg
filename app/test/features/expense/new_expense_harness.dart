import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/queries/month_queries.dart';
import 'package:milionchik/data/repositories/categories_repository.dart';
import 'package:milionchik/data/current_user.dart';
import 'package:milionchik/data/repositories/outbox_queue.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:milionchik/features/expense/new_expense_screen.dart';
import 'package:milionchik/ui/components/category_tile.dart';
import 'package:shared/shared.dart';

const String nbspace = ' ';

Finder inNewExpense(Finder finder) =>
    find.descendant(of: find.byType(NewExpenseScreen), matching: finder);

Finder keypadKey(String label) => inNewExpense(find.bySemanticsLabel(label));

Finder categoryTile(String name) =>
    inNewExpense(find.widgetWithText(CategoryTile, name));

String amountText(WidgetTester tester) => tester
    .widget<Text>(
      find
          .descendant(
            of: find.byKey(const ValueKey('new-expense-amount')),
            matching: find.byType(Text),
          )
          .first,
    )
    .data!;

Future<void> typeKeys(WidgetTester tester, String keys) async {
  for (final key in keys.split('')) {
    final finder = keypadKey(key);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<void> tapCategory(WidgetTester tester, String name) async {
  final tile = categoryTile(name);
  await tester.ensureVisible(tile);
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(of: tile, matching: find.byType(InkWell)));
  await tester.pumpAndSettle();
}

Future<List<Expense>> allExpenses(
  WidgetTester tester,
  AppDatabase db,
  String budgetId,
  LocalDate day,
) async => (await tester.runAsync(
  () => DriftMonthQueries(db).watchDayExpenses(budgetId, day).first,
))!;

Future<List<Category>> budgetCategories(
  WidgetTester tester,
  AppDatabase db,
  String budgetId,
) async => (await tester.runAsync(
  () => DriftCategoriesRepository(
    db,
    currentUser: LocalPrefsCurrentUser(DriftPrefsRepository(db)),
    outbox: DriftOutboxQueue(db),
  ).watchByBudget(budgetId).first,
))!;

int hapticCount(List<MethodCall> calls) => calls
    .where(
      (c) =>
          c.method == 'HapticFeedback.vibrate' &&
          c.arguments == 'HapticFeedbackType.lightImpact',
    )
    .length;
