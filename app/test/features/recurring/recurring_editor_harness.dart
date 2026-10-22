import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/recurring_service.dart';
import 'package:milionchik/data/repositories/records.dart';
import 'package:milionchik/features/expense/category_grid.dart';
import 'package:milionchik/features/expense/expense_amount_sheet.dart';
import 'package:milionchik/features/recurring/recurring_day_sheet.dart';
import 'package:milionchik/features/recurring/recurring_editor_screen.dart';
import 'package:milionchik/ui/components/button.dart';
import 'package:milionchik/ui/components/category_tile.dart';
import 'package:milionchik/ui/components/text_field.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';
import '../shell/shell_harness.dart';
import 'recurring_fixture.dart';

final class RecurringEditorHarness {
  RecurringEditorHarness(this.shell, this.budget);

  final ShellHarness shell;
  final RecurringBudget budget;

  WidgetTester get tester => shell.tester;

  static Future<RecurringEditorHarness> start(
    WidgetTester tester, {
    bool mockup = true,
    DateTime? now,
    Size size = const Size(360, 800),
  }) async {
    final db = openTestDatabase();
    final budget = (await tester.runAsync(
      () => mockup
          ? seedRecurringMockup(db, now: now)
          : seedRecurringBudget(db, now: now),
    ))!;
    final shell = await ShellHarness.start(
      tester,
      db: db,
      now: now,
      size: size,
    );
    return RecurringEditorHarness(shell, budget);
  }

  Future<T> read<T>(Future<T> Function() body) async =>
      (await tester.runAsync(body)) as T;

  GoRouter get router =>
      GoRouter.of(tester.element(find.byType(Navigator).first));

  String get location => router.state.uri.toString();

  Future<void> openNew() async {
    await shell.tapTab('Регулярные');
    await tester.tap(find.bySemanticsLabel('Добавить регулярную трату').first);
    await tester.pumpAndSettle();
    expect(find.byType(RecurringEditorScreen), findsOneWidget);
  }

  Future<void> openRule(String title) async {
    await shell.tapTab('Регулярные');
    await tester.ensureVisible(find.text(title));
    await tester.pumpAndSettle();
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
    expect(find.byType(RecurringEditorScreen), findsOneWidget);
  }

  Finder inEditor(Finder finder) =>
      find.descendant(of: find.byType(RecurringEditorScreen), matching: finder);

  Finder get titleField => inEditor(
    find.descendant(
      of: find.byType(AppTextField).first,
      matching: find.byType(EditableText),
    ),
  );

  Future<void> typeTitle(String text) async {
    await tester.enterText(titleField, text);
    await tester.pump();
  }

  Finder get amountField => inEditor(find.bySemanticsLabel('Сумма в месяц'));

  Future<void> enterAmount(String keys) async {
    await tester.tap(amountField);
    await tester.pumpAndSettle();
    expect(find.byType(ExpenseAmountSheet), findsOneWidget);
    for (final key in keys.split('')) {
      await tester.tap(
        find.descendant(
          of: find.byType(ExpenseAmountSheet),
          matching: find.bySemanticsLabel(key == '<' ? 'Стереть' : key),
        ),
      );
      await tester.pump();
    }
    await tester.tap(
      find.descendant(
        of: find.byType(ExpenseAmountSheet),
        matching: find.text('Готово'),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder row(String label) => inEditor(
    find.bySemanticsLabel(RegExp('^${RegExp.escape(label)}(, |\$)')),
  );

  String rowLabel(String label) => tester.getSemantics(row(label)).label;

  Future<void> pickCategory(String name) async {
    await tester.tap(row('Категория'));
    await tester.pumpAndSettle();
    final tile = find.descendant(
      of: find.byType(AllCategoriesSheet),
      matching: find.widgetWithText(CategoryTile, name),
    );
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: tile, matching: find.byType(InkWell)));
    await tester.pumpAndSettle();
    expect(find.byType(AllCategoriesSheet), findsNothing);
  }

  Future<void> openDaySheet() async {
    await tester.tap(row('День списания'));
    await tester.pumpAndSettle();
    expect(find.byType(RecurringDaySheet), findsOneWidget);
  }

  Finder dayCell(int day) => find.descendant(
    of: find.byType(RecurringDaySheet),
    matching: find.bySemanticsLabel(RegExp('^$day-е число')),
  );

  Future<void> pickDay(int day) async {
    await openDaySheet();
    await tester.ensureVisible(dayCell(day));
    await tester.pumpAndSettle();
    await tester.tap(dayCell(day));
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(RecurringDaySheet),
        matching: find.text('Готово'),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder get saveButton =>
      inEditor(find.widgetWithText(AppButton, 'Сохранить'));

  Finder get deleteButton =>
      inEditor(find.widgetWithText(AppButton, 'Удалить регулярную трату'));

  Future<void> tapButton(Finder button) async {
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  Future<void> pumpUntil(Finder finder) async {
    for (var i = 0; i < 250 && finder.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
  }

  Future<void> save() => tapButton(saveButton);

  Future<List<RecurringRule>> rules() =>
      read(() => budget.recurring.watchByBudget(budget.id).first);

  Future<RecurringRule?> ruleWithDeleted(String id) =>
      read(() => budget.recurring.watchByIdWithDeleted(id).first);

  Future<List<Expense>> expensesOf(String ruleId) => read(() async {
    final db = shell.db;
    final rows =
        await (db.select(db.expenses)
              ..where((e) => e.recurringId.equals(ruleId))
              ..orderBy([(e) => OrderingTerm.asc(e.spentOn)]))
            .get();
    return [for (final r in rows) expenseFromRow(r)];
  });

  Iterable<LogRecord> logs([Level level = Level.ALL]) => shell.records.where(
    (r) => r.loggerName == 'recurring' && r.level >= level,
  );

  Iterable<String> messages([Level level = Level.ALL]) =>
      logs(level).map((r) => r.message);
}

const String gymTitle = 'Спортзал «Территория»';

Future<RecurringRunResult> seedClockRun(AppDatabase db, DateTime now) =>
    RecurringService.forDatabase(
      db,
      clock: Clock(now: () => now),
    ).run(RecurringRunReason.background);
