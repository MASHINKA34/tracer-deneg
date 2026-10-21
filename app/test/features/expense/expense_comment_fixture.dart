import 'package:milionchik/data/current_user.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/repositories/categories_repository.dart';
import 'package:milionchik/data/repositories/expenses_repository.dart';
import 'package:milionchik/data/repositories/outbox_queue.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';

const List<String> mockupRecentComments = [
  'Пятёрочка',
  'Метро',
  'Обед',
  'Кофе с собой',
];

Future<String> seedComments(
  AppDatabase db,
  List<String> newestFirst, {
  String? budgetId,
}) async {
  final user = LocalPrefsCurrentUser(DriftPrefsRepository(db));
  final outbox = DriftOutboxQueue(db);
  final id = budgetId ?? (await testBudgets(db).createLocalPersonal()).id;
  final categories = await DriftCategoriesRepository(
    db,
    currentUser: user,
    outbox: outbox,
  ).watchByBudget(id).first;
  final oldest = newestFirst.reversed.toList();
  for (final (i, comment) in oldest.indexed) {
    final at = DateTime(2026, 10, 19, 19).add(Duration(minutes: i));
    await DriftExpensesRepository(
      db,
      currentUser: user,
      outbox: outbox,
      now: () => at,
    ).create(
      budgetId: id,
      categoryId: categories.first.id,
      amount: const Money.rubles(100),
      spentOn: LocalDate(2026, 10, 19),
      comment: comment,
    );
  }
  return id;
}
