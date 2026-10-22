import 'package:drift/drift.dart' show Value;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:milionchik/core/router.dart';
import 'package:milionchik/data/current_user.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/repositories/categories_repository.dart';
import 'package:milionchik/data/repositories/expenses_repository.dart';
import 'package:milionchik/data/repositories/outbox_queue.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:milionchik/features/month/month_screen.dart';
import 'package:milionchik/features/search/search_screen.dart';
import 'package:milionchik/ui/components/expense_row.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';
import '../shell/shell_harness.dart';

final class SearchSeed {
  const SearchSeed(this.budgetId, this.categoryIds, this.expenseIds);

  final String budgetId;
  final Map<String, String> categoryIds;
  final Map<String, String> expenseIds;
}

typedef _Spend = (
  String key,
  String category,
  int rubles,
  LocalDate day,
  String comment,
  DateTime createdAt,
);

final List<_Spend> searchMockupSpends = [
  (
    'кофе 3.10',
    'Кафе',
    170,
    LocalDate(2026, 10, 3),
    'Кофе с собой',
    DateTime(2026, 10, 4, 10),
  ),
  (
    'такси',
    'Транспорт',
    300,
    LocalDate(2026, 9, 20),
    'Такси',
    DateTime(2026, 9, 20, 23),
  ),
  (
    'ёлка',
    'Подарки',
    1500,
    LocalDate(2025, 12, 28),
    'Ёлка на Новый год',
    DateTime(2025, 12, 28, 12),
  ),
  (
    'коммуналка',
    'Дом',
    6400,
    LocalDate(2026, 10, 5),
    'Коммуналка',
    DateTime(2026, 10, 5, 12),
  ),
  (
    'кино',
    'Развлечения',
    1640,
    LocalDate(2026, 10, 10),
    'Кино',
    DateTime(2026, 10, 10, 21),
  ),
  (
    'кофе 11.10',
    'Кафе',
    190,
    LocalDate(2026, 10, 11),
    'Кофе с собой',
    DateTime(2026, 10, 12, 10),
  ),
  (
    'зёрна',
    'Продукты',
    560,
    LocalDate(2026, 10, 15),
    'Кофе в зёрнах · ВкусВилл',
    DateTime(2026, 10, 14, 20),
  ),
  (
    'круассан',
    'Кафе',
    340,
    LocalDate(2026, 10, 15),
    'Кофе и круассан',
    DateTime(2026, 10, 15, 8, 40),
  ),
  (
    'метро',
    'Транспорт',
    64,
    LocalDate(2026, 10, 17),
    'Метро',
    DateTime(2026, 10, 17, 8),
  ),
  (
    'пятёрочка',
    'Продукты',
    640,
    LocalDate(2026, 10, 18),
    'Пятёрочка',
    DateTime(2026, 10, 18, 19),
  ),
  (
    'кофе 19.10',
    'Кафе',
    210,
    LocalDate(2026, 10, 19),
    'Кофе с собой',
    DateTime(2026, 10, 19, 9, 15),
  ),
];

Future<SearchSeed> seedSearchMockup(AppDatabase db) async {
  final user = LocalPrefsCurrentUser(DriftPrefsRepository(db));
  final outbox = DriftOutboxQueue(db);
  final budget = await testBudgets(db).createLocalPersonal();
  final categories = await DriftCategoriesRepository(
    db,
    currentUser: user,
    outbox: outbox,
  ).watchByBudget(budget.id).first;
  final categoryIds = {for (final c in categories) c.name: c.id};
  final expenses = DriftExpensesRepository(
    db,
    currentUser: user,
    outbox: outbox,
  );
  final expenseIds = <String, String>{};
  for (final (key, category, rubles, day, comment, createdAt)
      in searchMockupSpends) {
    final expense = await expenses.create(
      budgetId: budget.id,
      categoryId: categoryIds[category]!,
      amount: Money.rubles(rubles),
      spentOn: day,
      comment: comment,
    );
    await (db.update(db.expenses)..where((e) => e.id.equals(expense.id))).write(
      ExpensesCompanion(createdAt: Value(createdAt.toUtc())),
    );
    expenseIds[key] = expense.id;
  }
  return SearchSeed(budget.id, categoryIds, expenseIds);
}

Future<void> settleSearch(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pumpAndSettle();
}

Future<ShellHarness> openSearch(
  WidgetTester tester, {
  String location = AppRoutes.search,
  Future<void> Function(AppDatabase db)? seed,
  Size size = const Size(360, 1600),
  AppDatabase? database,
}) async {
  final db = database ?? openTestDatabase();
  await tester.runAsync(() => (seed ?? seedSearchMockup)(db));
  final h = await ShellHarness.start(tester, db: db, size: size);
  final router = GoRouter.of(tester.element(find.byType(MonthScreen)));
  router.push<void>(location);
  await settleSearch(tester);
  expect(find.byType(SearchScreen), findsOneWidget);
  return h;
}

Future<void> typeQuery(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(EditableText), text);
  await tester.pump(searchDebounce);
  await settleSearch(tester);
}

Finder inSearch(Finder finder) =>
    find.descendant(of: find.byType(SearchScreen), matching: finder);

List<String> shownAmounts(WidgetTester tester) => [
  for (final row in tester.widgetList<ExpenseRow>(
    inSearch(find.byType(ExpenseRow)),
  ))
    row.amount.replaceAll(nbsp, ' '),
];

String? foundLine(WidgetTester tester) {
  final texts = [
    for (final text in tester.widgetList<Text>(inSearch(find.byType(Text))))
      if (text.data case final data? when data.startsWith('Найден'))
        data.replaceAll(nbsp, ' '),
  ];
  return texts.isEmpty ? null : texts.single;
}

Iterable<String> searchDebugLogs(ShellHarness h) =>
    h.records.where((r) => r.loggerName == 'search').map((r) => r.message);
