import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/current_user.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/repositories/expenses_repository.dart';
import 'package:milionchik/data/repositories/outbox_queue.dart';
import 'package:milionchik/features/reminders/reminder_settings.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';
import '../auth/session_expired_fixture.dart' show testUnmounting;
import '../profile/profile_fixture.dart';
import 'reminder_fakes.dart';
import 'reminders_harness.dart';

const _on = ReminderSettings(enabled: true);

DriftExpensesRepository _repo(
  AppDatabase db,
  String userId, {
  TodayExpenseListener? onTodayExpense,
}) => DriftExpensesRepository(
  db,
  currentUser: SessionCurrentUser(userId),
  outbox: DriftOutboxQueue(db, now: () => testNow),
  now: () => testNow,
  onTodayExpense: onTodayExpense,
);

Future<Expense> _expenseBy(AppDatabase db, String userId, String budgetId) =>
    _repo(db, userId).create(
      budgetId: budgetId,
      categoryId: 'cat-food',
      amount: Money.rubles(300),
      spentOn: LocalDate(2026, 10, 19),
    );

RecurringRule _rent() => RecurringRule(
  id: 'rule-rent',
  budgetId: profilePersonalId,
  categoryId: 'cat-personal-home',
  title: 'Аренда',
  amount: Money.rubles(30000),
  dayOfMonth: 19,
  startMonth: YearMonth(2026, 10),
  createdAt: testNow,
  updatedAt: testNow,
  updatedBy: profileUserId,
);

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testUnmounting('трата сегодня в общем бюджете отменяет сегодняшнее '
      'напоминание, остальные 6 дней остаются; причина в info', (tester) async {
    final plugin = FakeReminderNotifications();
    final h = await startWithReminders(tester, plugin, settings: _on);
    expect(plugin.pendingDays, octoberDays(19, 25));

    final expense = (await tester.runAsync(
      () => h.container
          .read(expensesRepositoryProvider)
          .create(
            budgetId: profileFamilyId,
            categoryId: 'cat-family-food',
            amount: Money.rubles(640),
            spentOn: LocalDate(2026, 10, 19),
          ),
    ))!;
    await h.settle();

    expect(plugin.pendingDays, octoberDays(20, 25));
    expect(plugin.calls.last, 'cancel 20261019');
    expect(
      reminderLines(h, Level.INFO).last,
      matches(
        '^reminder for today 2026-10-19 cancelled id=20261019: expense saved '
        'for today: expense create id=${expense.id} '
        'budgetId=$profileFamilyId day=2026-10-19 in \\d+ms\$',
      ),
    );
  });

  testUnmounting('трата за вчера или перенос траты на вчера сегодняшнее не '
      'трогают; правка даты на сегодня - отменяет', (tester) async {
    final plugin = FakeReminderNotifications();
    final h = await startWithReminders(tester, plugin, settings: _on);
    final expenses = h.container.read(expensesRepositoryProvider);

    final yesterday = (await tester.runAsync(
      () => expenses.create(
        budgetId: profilePersonalId,
        categoryId: 'cat-personal-food',
        amount: Money.rubles(149),
        spentOn: LocalDate(2026, 10, 18),
      ),
    ))!;
    await h.settle();
    expect(plugin.pendingDays, octoberDays(19, 25));
    expect(plugin.calls.where((c) => c.startsWith('cancel ')), isEmpty);

    await tester.runAsync(
      () => expenses.update(yesterday.id, spentOn: LocalDate(2026, 10, 19)),
    );
    await h.settle();

    expect(plugin.pendingDays, octoberDays(20, 25));
    expect(
      reminderLines(h, Level.INFO).last,
      contains(
        'expense saved for today: expense update id=${yesterday.id} '
        'budgetId=$profilePersonalId day=2026-10-19',
      ),
    );
  });

  testUnmounting('напоминания выключены: трата сегодня плагин не трогает', (
    tester,
  ) async {
    final plugin = FakeReminderNotifications();
    final h = await startWithReminders(tester, plugin);

    await tester.runAsync(
      () => h.container
          .read(expensesRepositoryProvider)
          .create(
            budgetId: profilePersonalId,
            categoryId: 'cat-personal-food',
            amount: Money.rubles(149),
            spentOn: LocalDate(2026, 10, 19),
          ),
    );
    await h.settle();

    expect(plugin.calls, isEmpty);
    expect(
      reminderLines(h),
      contains(
        startsWith(
          'reminders off → nothing to cancel for today 2026-10-19 (expense '
          'saved for today: expense create id=',
        ),
      ),
    );
  });

  testUnmounting('при старте своя трата сегодня - сегодняшнего нет', (
    tester,
  ) async {
    final db = openTestDatabase();
    await tester.runAsync(() async {
      await ProfileFixture.mockup(db);
      await _expenseBy(db, profileUserId, profilePersonalId);
    });
    final plugin = FakeReminderNotifications();
    final h = await startWithReminders(
      tester,
      plugin,
      settings: _on,
      db: db,
      seed: false,
    );

    expect(plugin.pendingDays, octoberDays(20, 25));
    expect(
      reminderLines(h, Level.INFO).last,
      contains('today=2026-10-19 skipped: expense recorded today'),
    );
  });

  testUnmounting('трата другого участника и регулярная за сегодня не '
      'считаются - сегодняшнее на месте', (tester) async {
    final db = openTestDatabase();
    await tester.runAsync(() async {
      await ProfileFixture.mockup(db);
      await _expenseBy(db, 'user-server-dima', profileFamilyId);
      final rule = _rent();
      await _repo(db, profileUserId).createRecurring(
        rule,
        planRecurringExpenses(
          rule,
          LocalDate(2026, 10, 19),
          existingExpenseIds: const {},
        ).single,
      );
    });
    final plugin = FakeReminderNotifications();
    final h = await startWithReminders(
      tester,
      plugin,
      settings: _on,
      db: db,
      seed: false,
    );

    expect(plugin.pendingDays, octoberDays(19, 25));
    expect(
      reminderLines(h, Level.INFO).last,
      contains('today=2026-10-19 planned'),
    );
  });

  test('событие «трата сегодня» - только create/update с датой сегодня, '
      'регулярные и вчерашние - без события', () async {
    final db = openTestDatabase();
    final events = <TodayExpenseSaved>[];
    final repo = _repo(db, profileUserId, onTodayExpense: events.add);
    final rule = _rent();

    await repo.createRecurring(
      rule,
      planRecurringExpenses(
        rule,
        LocalDate(2026, 10, 19),
        existingExpenseIds: const {},
      ).single,
    );
    final old = await repo.create(
      budgetId: profilePersonalId,
      categoryId: 'cat-personal-food',
      amount: Money.rubles(149),
      spentOn: LocalDate(2026, 10, 17),
    );
    expect(events, isEmpty);

    final today = await repo.create(
      budgetId: profilePersonalId,
      categoryId: 'cat-personal-food',
      amount: Money.rubles(149),
      spentOn: LocalDate(2026, 10, 19),
    );
    await repo.update(old.id, comment: 'kofe');
    await repo.update(today.id, comment: 'chay');

    expect(events.map((e) => (e.action, e.expenseId, e.day)), [
      ('create', today.id, LocalDate(2026, 10, 19)),
      ('update', today.id, LocalDate(2026, 10, 19)),
    ]);
  });
}
