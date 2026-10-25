import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../core/clock.dart';
import 'budget_selection.dart';
import 'current_user.dart';
import 'db/app_database.dart';
import 'db/redact_db_error.dart';
import 'queries/budget_queries.dart';
import 'queries/category_queries.dart';
import 'queries/month_queries.dart';
import 'queries/recurring_queries.dart';
import 'queries/reminder_queries.dart';
import 'queries/search_queries.dart';
import 'queries/stats_queries.dart';
import 'queries/sync_state_queries.dart';
import 'queries/today_queries.dart';
import 'repositories/account_data_cleaner.dart';
import 'repositories/budgets_repository.dart';
import 'repositories/categories_repository.dart';
import 'repositories/expenses_repository.dart';
import 'repositories/members_repository.dart';
import 'repositories/outbox_queue.dart';
import 'repositories/prefs_repository.dart';
import 'repositories/recurring_repository.dart';
import 'session/session_providers.dart';

final _log = Logger('budgets');

final _sessionLog = Logger('session');

typedef BudgetMonth = ({String budgetId, YearMonth month});

typedef BudgetDay = ({String budgetId, LocalDate day});

typedef BudgetPeriod = ({String budgetId, LocalDate from, LocalDate to});

typedef BudgetYear = ({String budgetId, int year});

typedef BudgetRecent = ({String budgetId, int limit});

Duration? _noRetry(int retryCount, Object error) => null;

final appDatabaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError(
    'appDatabaseProvider has no database: override it with the one opened '
    'at startup (main.dart) or with AppDatabase.memory() in tests',
  ),
  name: 'appDatabase',
);

final prefsRepositoryProvider = Provider<PrefsRepository>(
  (ref) => DriftPrefsRepository(ref.watch(appDatabaseProvider)),
  name: 'prefsRepository',
);

final accountDataCleanerProvider = Provider<AccountDataCleaner>(
  (ref) => DriftAccountDataCleaner(ref.watch(appDatabaseProvider)),
  name: 'accountDataCleaner',
);

final currentUserProvider = Provider<CurrentUser>((ref) {
  final sessionUserId = ref.watch(sessionProvider.select((s) => s.userId));
  if (sessionUserId != null) {
    _sessionLog.info('current user from session userId=$sessionUserId');
    return SessionCurrentUser(sessionUserId);
  }
  _sessionLog.fine('current user: no session → local user id');
  return LocalPrefsCurrentUser(ref.watch(prefsRepositoryProvider));
}, name: 'currentUser');

final outboxQueueProvider = Provider<OutboxQueue>(
  (ref) => DriftOutboxQueue(
    ref.watch(appDatabaseProvider),
    now: ref.watch(clockProvider).now,
  ),
  name: 'outboxQueue',
);

final todayExpenseEventsProvider = Provider<TodayExpenseEvents>((ref) {
  final events = TodayExpenseEvents();
  ref.onDispose(events.close);
  return events;
}, name: 'todayExpenseEvents');

final expensesRepositoryProvider = Provider<ExpensesRepository>(
  (ref) => DriftExpensesRepository(
    ref.watch(appDatabaseProvider),
    currentUser: ref.watch(currentUserProvider),
    outbox: ref.watch(outboxQueueProvider),
    now: ref.watch(clockProvider).now,
    onTodayExpense: ref.watch(todayExpenseEventsProvider).add,
  ),
  name: 'expensesRepository',
);

final categoriesRepositoryProvider = Provider<CategoriesRepository>(
  (ref) => DriftCategoriesRepository(
    ref.watch(appDatabaseProvider),
    currentUser: ref.watch(currentUserProvider),
    outbox: ref.watch(outboxQueueProvider),
    now: ref.watch(clockProvider).now,
  ),
  name: 'categoriesRepository',
);

final recurringRepositoryProvider = Provider<RecurringRepository>(
  (ref) => DriftRecurringRepository(
    ref.watch(appDatabaseProvider),
    currentUser: ref.watch(currentUserProvider),
    outbox: ref.watch(outboxQueueProvider),
    now: ref.watch(clockProvider).now,
  ),
  name: 'recurringRepository',
);

final budgetsRepositoryProvider = Provider<BudgetsRepository>(
  (ref) => DriftBudgetsRepository(
    ref.watch(appDatabaseProvider),
    currentUser: ref.watch(currentUserProvider),
    outbox: ref.watch(outboxQueueProvider),
    now: ref.watch(clockProvider).now,
  ),
  name: 'budgetsRepository',
);

final membersRepositoryProvider = Provider<MembersRepository>(
  (ref) => DriftMembersRepository(ref.watch(appDatabaseProvider)),
  name: 'membersRepository',
);

final monthQueriesProvider = Provider<MonthQueries>(
  (ref) => DriftMonthQueries(ref.watch(appDatabaseProvider)),
  name: 'monthQueries',
);

final statsQueriesProvider = Provider<StatsQueries>(
  (ref) => DriftStatsQueries(ref.watch(appDatabaseProvider)),
  name: 'statsQueries',
);

final searchQueriesProvider = Provider<SearchQueries>(
  (ref) => DriftSearchQueries(ref.watch(appDatabaseProvider)),
  name: 'searchQueries',
);

final todayQueriesProvider = Provider<TodayQueries>(
  (ref) => DriftTodayQueries(ref.watch(appDatabaseProvider)),
  name: 'todayQueries',
);

final reminderQueriesProvider = Provider<ReminderQueries>(
  (ref) => DriftReminderQueries(ref.watch(appDatabaseProvider)),
  name: 'reminderQueries',
);

final categoryQueriesProvider = Provider<CategoryQueries>(
  (ref) => DriftCategoryQueries(ref.watch(appDatabaseProvider)),
  name: 'categoryQueries',
);

final recurringQueriesProvider = Provider<RecurringQueries>(
  (ref) => DriftRecurringQueries(ref.watch(appDatabaseProvider)),
  name: 'recurringQueries',
);

final budgetQueriesProvider = Provider<BudgetQueries>(
  (ref) => DriftBudgetQueries(ref.watch(appDatabaseProvider)),
  name: 'budgetQueries',
);

final syncStateQueriesProvider = Provider<SyncStateQueries>(
  (ref) => DriftSyncStateQueries(ref.watch(appDatabaseProvider)),
  name: 'syncStateQueries',
);

final lastSyncAtProvider = StreamProvider.autoDispose<DateTime?>(
  (ref) => ref.watch(syncStateQueriesProvider).watchLastSyncAt(),
  name: 'lastSyncAt',
  retry: _noRetry,
);

final dayTotalsProvider = StreamProvider.autoDispose
    .family<Map<int, Money>, BudgetMonth>(
      (ref, arg) => ref
          .watch(monthQueriesProvider)
          .watchDayTotals(arg.budgetId, arg.month),
      name: 'dayTotals',
      retry: _noRetry,
    );

final monthTotalProvider = StreamProvider.autoDispose
    .family<Money, BudgetMonth>(
      (ref, arg) => ref
          .watch(monthQueriesProvider)
          .watchMonthTotal(arg.budgetId, arg.month),
      name: 'monthTotal',
      retry: _noRetry,
    );

final dayExpensesProvider = StreamProvider.autoDispose
    .family<List<Expense>, BudgetDay>(
      (ref, arg) => ref
          .watch(monthQueriesProvider)
          .watchDayExpenses(arg.budgetId, arg.day),
      name: 'dayExpenses',
      retry: _noRetry,
    );

final recentExpensesProvider = StreamProvider.autoDispose
    .family<List<Expense>, BudgetRecent>(
      (ref, arg) => ref
          .watch(budgetQueriesProvider)
          .watchRecentExpenses(arg.budgetId, limit: arg.limit),
      name: 'recentExpenses',
      retry: _noRetry,
    );

final todayExpensesProvider = StreamProvider.autoDispose
    .family<TodayExpenses, BudgetDay>(
      (ref, arg) =>
          ref.watch(todayQueriesProvider).watchToday(arg.budgetId, arg.day),
      name: 'todayExpenses',
      retry: _noRetry,
    );

final categoryTotalsProvider = StreamProvider.autoDispose
    .family<List<CategoryTotal>, BudgetPeriod>(
      (ref, arg) => ref
          .watch(statsQueriesProvider)
          .watchCategoryTotals(arg.budgetId, from: arg.from, to: arg.to),
      name: 'categoryTotals',
      retry: _noRetry,
    );

final yearMonthTotalsProvider = StreamProvider.autoDispose
    .family<List<Money>, BudgetYear>(
      (ref, arg) => ref
          .watch(statsQueriesProvider)
          .watchMonthTotals(arg.budgetId, arg.year),
      name: 'yearMonthTotals',
      retry: _noRetry,
    );

final searchProvider = StreamProvider.autoDispose
    .family<SearchResult, SearchFilters>(
      (ref, filters) => ref.watch(searchQueriesProvider).watchSearch(filters),
      name: 'search',
      retry: _noRetry,
    );

final recentCommentsProvider = StreamProvider.autoDispose
    .family<List<String>, String>(
      (ref, budgetId) =>
          ref.watch(searchQueriesProvider).watchRecentComments(budgetId),
      name: 'recentComments',
      retry: _noRetry,
    );

final categoriesProvider = StreamProvider.autoDispose
    .family<List<Category>, String>(
      (ref, budgetId) =>
          ref.watch(categoriesRepositoryProvider).watchByBudget(budgetId),
      name: 'categories',
      retry: _noRetry,
    );

final categoryProvider = StreamProvider.autoDispose.family<Category?, String>(
  (ref, id) => ref.watch(categoriesRepositoryProvider).watchById(id),
  name: 'category',
  retry: _noRetry,
);

final categoryExpenseCountsProvider = StreamProvider.autoDispose
    .family<Map<String, int>, String>(
      (ref, budgetId) =>
          ref.watch(categoryQueriesProvider).watchExpenseCounts(budgetId),
      name: 'categoryExpenseCounts',
      retry: _noRetry,
    );

final expenseProvider = StreamProvider.autoDispose.family<Expense?, String>(
  (ref, id) => ref.watch(expensesRepositoryProvider).watchById(id),
  name: 'expense',
  retry: _noRetry,
);

final recurringRuleWithDeletedProvider = StreamProvider.autoDispose
    .family<RecurringRule?, String>(
      (ref, id) =>
          ref.watch(recurringRepositoryProvider).watchByIdWithDeleted(id),
      name: 'recurringRuleWithDeleted',
      retry: _noRetry,
    );

final recurringRulesProvider = StreamProvider.autoDispose
    .family<List<RecurringRule>, String>(
      (ref, budgetId) =>
          ref.watch(recurringRepositoryProvider).watchByBudget(budgetId),
      name: 'recurringRules',
      retry: _noRetry,
    );

final recurringChargesProvider = StreamProvider.autoDispose
    .family<Map<String, Expense>, BudgetMonth>(
      (ref, arg) => ref
          .watch(recurringQueriesProvider)
          .watchMonthCharges(arg.budgetId, arg.month),
      name: 'recurringCharges',
      retry: _noRetry,
    );

final budgetProvider = StreamProvider.autoDispose.family<Budget?, String>(
  (ref, budgetId) => ref.watch(budgetsRepositoryProvider).watchById(budgetId),
  name: 'budget',
  retry: _noRetry,
);

final budgetMembersProvider = StreamProvider.autoDispose
    .family<List<BudgetMember>, String>(
      (ref, budgetId) =>
          ref.watch(membersRepositoryProvider).watchByBudget(budgetId),
      name: 'budgetMembers',
      retry: _noRetry,
    );

final memberProfilesProvider =
    StreamProvider.autoDispose<Map<String, MemberProfile>>(
      (ref) => ref
          .watch(membersRepositoryProvider)
          .watchProfiles()
          .map((profiles) => {for (final p in profiles) p.userId: p}),
      name: 'memberProfiles',
      retry: _noRetry,
    );

final budgetSelectionProvider = AsyncNotifierProvider<BudgetSelection, String?>(
  BudgetSelection.new,
  name: 'budgetSelection',
  retry: _noRetry,
);

final class BudgetSelection extends AsyncNotifier<String?> {
  @override
  Future<String?> build() async {
    final userId = ref.watch(sessionProvider.select((s) => s.userId));
    final prefs = ref.watch(prefsRepositoryProvider);
    final sw = Stopwatch()..start();
    try {
      return await prefs.getString(PrefKeys.selectedBudgetId);
    } catch (e, st) {
      final error = redactDbError(e);
      _log.warning(
        'stored choice read failed for userId=${userId ?? '-'} after '
        '${sw.elapsedMilliseconds}ms → personal budget is shown: '
        '${describeError(error)}',
        error,
        st,
      );
      return null;
    }
  }

  Future<void> select(
    String budgetId, {
    required String? from,
    required String by,
  }) async {
    final sw = Stopwatch()..start();
    try {
      await ref
          .read(prefsRepositoryProvider)
          .setString(PrefKeys.selectedBudgetId, budgetId);
    } catch (e, st) {
      final error = redactDbError(e);
      _log.severe(
        'selected budget change failed budgetId=$budgetId '
        'from=${from ?? '-'} by=$by after ${sw.elapsedMilliseconds}ms, '
        'the previous budget stays open: ${describeError(error)}',
        error,
        st,
      );
      rethrow;
    }
    if (ref.mounted) state = AsyncData(budgetId);
    _log.info(
      'selected budget changed budgetId=$budgetId from=${from ?? '-'} '
      'by=$by in ${sw.elapsedMilliseconds}ms',
    );
  }

  Future<void> forgetGone(String budgetId) async {
    if (state.value != budgetId) return;
    state = const AsyncData(null);
    try {
      await ref.read(prefsRepositoryProvider).remove(PrefKeys.selectedBudgetId);
      _log.fine('stored choice budgetId=$budgetId cleared: the budget is gone');
    } catch (e, st) {
      final error = redactDbError(e);
      _log.warning(
        'stored choice budgetId=$budgetId not cleared: '
        '${describeError(error)} → personal budget is shown, the stale '
        'choice is ignored again after restart',
        error,
        st,
      );
    }
  }
}

final selectedBudgetIdProvider = StreamProvider<String?>(
  (ref) {
    final ownerId = ref.watch(sessionProvider.select((s) => s.userId));
    final stored = StreamController<String?>();
    ref.onDispose(stored.close);
    ref.listen<AsyncValue<String?>>(budgetSelectionProvider, (_, next) {
      if (next.hasValue) stored.add(next.value);
    }, fireImmediately: true);
    return combineLatest(
          stored.stream,
          ref.watch(budgetsRepositoryProvider).watchAll(),
          (stored, budgets) => _selectedChoice(budgets, ownerId, stored),
        )
        .map((choice) {
          final gone = choice.gone;
          if (gone != null) {
            unawaited(
              ref.read(budgetSelectionProvider.notifier).forgetGone(gone),
            );
          }
          return choice;
        })
        .distinct((a, b) => a.budgetId == b.budgetId && a.hidden == b.hidden)
        .map((choice) => _logSelected(choice, ownerId));
  },
  name: 'selectedBudgetId',
  retry: _noRetry,
);

bool isBudgetVisibleTo(Budget budget, String? ownerId) =>
    budget.kind != BudgetKind.personal ||
    ownerId == null ||
    budget.ownerId == ownerId;

List<Budget> visibleBudgets(List<Budget> budgets, String? ownerId) => [
  for (final budget in budgets)
    if (isBudgetVisibleTo(budget, ownerId)) budget,
];

typedef _SelectedChoice = ({
  String? budgetId,
  int hidden,
  BudgetKind? chosenKind,
  String? gone,
});

_SelectedChoice _selectedChoice(
  List<Budget> budgets,
  String? ownerId,
  String? stored,
) {
  String? personal;
  var hidden = 0;
  Budget? chosen;
  for (final budget in budgets) {
    final visible = isBudgetVisibleTo(budget, ownerId);
    if (stored != null && budget.id == stored && visible) chosen = budget;
    if (budget.kind != BudgetKind.personal) continue;
    if (!visible) {
      hidden++;
    } else {
      personal ??= budget.id;
    }
  }
  if (chosen != null) {
    return (
      budgetId: chosen.id,
      hidden: hidden,
      chosenKind: chosen.kind,
      gone: null,
    );
  }
  return (
    budgetId: personal,
    hidden: hidden,
    chosenKind: null,
    gone: stored != null && budgets.isNotEmpty ? stored : null,
  );
}

String? _logSelected(_SelectedChoice choice, String? ownerId) {
  final budgetId = choice.budgetId;
  final hidden = choice.hidden == 0
      ? ''
      : ' hiddenPersonal=${choice.hidden} (personal budgets of another owner, '
            'e.g. made on this phone before sign-in: kept in the database, '
            'not shown)';
  final owner = ownerId == null ? '' : ' ownerId=$ownerId';
  final chosenKind = choice.chosenKind;
  final gone = choice.gone;
  if (chosenKind != null) {
    _log.info(
      'selected budget budgetId=$budgetId reason=chosen '
      'kind=${chosenKind.name}$owner$hidden',
    );
  } else if (gone != null) {
    _log.info(
      'selected budget ${budgetId == null ? 'none' : 'budgetId=$budgetId'} '
      'reason=personal$owner: chosen budgetId=$gone is gone (removed or not '
      'visible to this user) → stored choice cleared$hidden',
    );
  } else if (ownerId == null) {
    if (budgetId == null) {
      _log.info('selected budget: none, no personal budget in database yet');
    } else {
      _log.info('selected budget budgetId=$budgetId reason=personal');
    }
  } else if (budgetId == null) {
    _log.info(
      'selected budget: none, no personal budget of userId=$ownerId yet '
      '(comes with the first pull)$hidden',
    );
  } else {
    _log.info(
      'selected budget budgetId=$budgetId reason=personal '
      'ownerId=$ownerId$hidden',
    );
  }
  return budgetId;
}
