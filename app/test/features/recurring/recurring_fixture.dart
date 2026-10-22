import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/data/current_user.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/recurring_service.dart';
import 'package:milionchik/data/repositories/categories_repository.dart';
import 'package:milionchik/data/repositories/expenses_repository.dart';
import 'package:milionchik/data/repositories/outbox_queue.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:milionchik/data/repositories/recurring_repository.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';

typedef MockupRule = ({String title, String category, int rubles, int day});

const List<MockupRule> mockupRules = [
  (title: 'Музыка', category: 'Музыка', rubles: 199, day: 24),
  (title: 'Онлайн-кино', category: 'Кино', rubles: 299, day: 28),
  (title: 'Домашний интернет', category: 'Интернет', rubles: 650, day: 3),
  (title: 'Мобильная связь', category: 'Связь', rubles: 450, day: 7),
  (title: 'Спортзал «Территория»', category: 'Спорт', rubles: 2900, day: 12),
];

final YearMonth october = YearMonth(2026, 10);

final class RecurringBudget {
  RecurringBudget(this.db, this.id, this.categoryIds, {required this.clock});

  final AppDatabase db;
  final String id;
  final Map<String, String> categoryIds;
  final Clock clock;
  final Map<String, RecurringRule> rules = {};

  late final _user = LocalPrefsCurrentUser(DriftPrefsRepository(db));
  late final _outbox = DriftOutboxQueue(db, now: clock.now);

  late final RecurringRepository recurring = DriftRecurringRepository(
    db,
    currentUser: _user,
    outbox: _outbox,
    now: clock.now,
  );

  late final ExpensesRepository expenses = DriftExpensesRepository(
    db,
    currentUser: _user,
    outbox: _outbox,
    now: clock.now,
  );

  Future<RecurringRule> rule(
    String title, {
    String category = 'Связь',
    int rubles = 100,
    int kopecks = 0,
    int day = 1,
    YearMonth? from,
  }) async {
    final created = await recurring.create(
      budgetId: id,
      categoryId: categoryIds[category]!,
      title: title,
      amount: Money.rubles(rubles, kopecks),
      dayOfMonth: day,
      startMonth: from ?? october,
    );
    rules[title] = created;
    return created;
  }

  Future<RecurringRunResult> generate() => RecurringService.forDatabase(
    db,
    clock: clock,
  ).run(RecurringRunReason.startup);
}

Future<RecurringBudget> seedRecurringBudget(
  AppDatabase db, {
  DateTime? now,
}) async {
  final clock = Clock(now: () => now ?? testNow);
  final user = LocalPrefsCurrentUser(DriftPrefsRepository(db));
  final outbox = DriftOutboxQueue(db, now: clock.now);
  final budget = await testBudgets(db).createLocalPersonal();
  final categories = DriftCategoriesRepository(
    db,
    currentUser: user,
    outbox: outbox,
    now: clock.now,
  );
  for (final (name, emoji, color) in const [
    ('Музыка', '🎵', CategoryColor.pink),
    ('Кино', '🎬', CategoryColor.purple),
    ('Интернет', '🌐', CategoryColor.teal),
  ]) {
    await categories.create(
      budgetId: budget.id,
      name: name,
      emoji: emoji,
      color: color,
    );
  }
  final all = await categories.watchByBudget(budget.id).first;
  return RecurringBudget(db, budget.id, {
    for (final c in all) c.name: c.id,
  }, clock: clock);
}

Future<RecurringBudget> seedRecurringMockup(
  AppDatabase db, {
  DateTime? now,
}) async {
  final budget = await seedRecurringBudget(db, now: now);
  for (final r in mockupRules) {
    await budget.rule(
      r.title,
      category: r.category,
      rubles: r.rubles,
      day: r.day,
    );
  }
  await budget.generate();
  return budget;
}

Future<T> writeWhileShown<T>(
  WidgetTester tester,
  Future<T> Function() body,
) async {
  late T result;
  Object? error;
  var done = false;
  await tester.runAsync(() async {
    unawaited(
      body().then(
        (value) {
          result = value;
          done = true;
        },
        onError: (Object e) {
          error = e;
          done = true;
        },
      ),
    );
  });
  for (var i = 0; i < 100 && !done; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(done, isTrue, reason: 'database work did not finish');
  if (error != null) throw error!;
  await tester.pumpAndSettle();
  return result;
}
