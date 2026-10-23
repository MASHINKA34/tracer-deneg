import 'package:milionchik/data/current_user.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/repositories/expenses_repository.dart';
import 'package:milionchik/data/repositories/outbox_queue.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';
import 'profile_fixture.dart';

const String unsyncedComment = 'kommentariy-oscar-papa-lima';

Future<List<Expense>> addUnsyncedExpenses(AppDatabase db, int count) async {
  final expenses = DriftExpensesRepository(
    db,
    currentUser: const SessionCurrentUser(profileUserId),
    outbox: DriftOutboxQueue(db, now: () => testNow),
    now: () => testNow,
  );
  return [
    for (var i = 0; i < count; i++)
      await expenses.create(
        budgetId: profilePersonalId,
        categoryId: 'cat-personal-$i',
        amount: Money.rubles(640 + i),
        spentOn: LocalDate(2026, 10, 19),
        comment: unsyncedComment,
      ),
  ];
}

Future<int> rowsIn(AppDatabase db, String table) async {
  final row = await db
      .customSelect('SELECT COUNT(*) AS c FROM "$table"')
      .getSingle();
  return row.read<int>('c');
}
