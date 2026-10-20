import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/current_user.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/repositories/budgets_repository.dart';
import 'package:milionchik/data/repositories/categories_repository.dart';
import 'package:milionchik/data/repositories/expenses_repository.dart';
import 'package:milionchik/data/repositories/members_repository.dart';
import 'package:milionchik/data/repositories/outbox_queue.dart';
import 'package:milionchik/data/repositories/recurring_repository.dart';
import 'package:shared/shared.dart';

const String meId = 'user-me';
const String serverUserId = 'user-server';

final class FixedCurrentUser implements CurrentUser {
  const FixedCurrentUser(this.id);

  final String id;

  @override
  Future<String> userId() async => id;
}

final class SeededBudget {
  const SeededBudget(this.budget, this.categories);

  final Budget budget;
  final List<Category> categories;

  String get id => budget.id;

  Category byName(String name) => categories.firstWhere((c) => c.name == name);

  Category get other => categories.firstWhere((c) => c.isSystem);
}

final class RepositoryHarness {
  RepositoryHarness() : db = AppDatabase.memory() {
    Logger.root.level = Level.ALL;
    _logs = Logger.root.onRecord.listen(records.add);
  }

  final AppDatabase db;
  final List<LogRecord> records = [];
  late final StreamSubscription<LogRecord> _logs;

  DateTime clock = DateTime.utc(2026, 10, 20, 9);

  DateTime now() => clock;

  void advance(Duration duration) => clock = clock.add(duration);

  final CurrentUser user = const FixedCurrentUser(meId);

  late final DriftOutboxQueue outbox = DriftOutboxQueue(db, now: now);

  late final DriftExpensesRepository expenses = DriftExpensesRepository(
    db,
    currentUser: user,
    outbox: outbox,
    now: now,
  );

  late final DriftCategoriesRepository categories = DriftCategoriesRepository(
    db,
    currentUser: user,
    outbox: outbox,
    now: now,
  );

  late final DriftRecurringRepository recurring = DriftRecurringRepository(
    db,
    currentUser: user,
    outbox: outbox,
    now: now,
  );

  late final DriftBudgetsRepository budgets = DriftBudgetsRepository(
    db,
    currentUser: user,
    outbox: outbox,
    now: now,
  );

  late final DriftMembersRepository members = DriftMembersRepository(db);

  int _ids = 0;

  String nextId(String prefix) => '$prefix-${++_ids}';

  Future<SeededBudget> seedBudget({
    String? id,
    BudgetKind kind = BudgetKind.personal,
  }) async {
    final budgetId = id ?? nextId('budget');
    final at = DateTime.utc(2026, 10, 1);
    final budget = Budget(
      id: budgetId,
      kind: kind,
      name: 'Личный',
      emoji: '💰',
      ownerId: meId,
      createdAt: at,
      updatedAt: at,
      updatedBy: serverUserId,
      seq: 1,
    );
    final categories = buildPresetCategories(
      budgetId: budgetId,
      updatedBy: serverUserId,
      now: at,
      newId: () => nextId('$budgetId-cat'),
    );
    await budgets.applyFromServer([budget]);
    await this.categories.applyFromServer(categories);
    return SeededBudget(budget, categories);
  }

  Future<List<OutboxEntry>> outboxRows() =>
      (db.select(db.outbox)..orderBy([(o) => OrderingTerm.asc(o.id)])).get();

  Future<Map<String, int>> rowCounts() async => {
    'budgets': await db.budgets.count().getSingle(),
    'categories': await db.categories.count().getSingle(),
    'expenses': await db.expenses.count().getSingle(),
    'recurring_rules': await db.recurringRules.count().getSingle(),
    'outbox': await db.outbox.count().getSingle(),
  };

  List<LogRecord> repoLogs([Level? level]) => [
    for (final r in records)
      if (r.loggerName == 'repo' && (level == null || r.level == level)) r,
  ];

  Future<void> dispose() async {
    await _logs.cancel();
    await db.close();
  }
}

Map<String, Object?> payloadOf(OutboxEntry entry) =>
    jsonDecode(entry.payload!) as Map<String, Object?>;

Future<T> firstOf<T>(Stream<T> stream) => stream.first;
