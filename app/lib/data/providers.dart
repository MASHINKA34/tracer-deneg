import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../core/clock.dart';
import 'current_user.dart';
import 'db/app_database.dart';
import 'queries/month_queries.dart';
import 'queries/search_queries.dart';
import 'queries/stats_queries.dart';
import 'queries/today_queries.dart';
import 'repositories/budgets_repository.dart';
import 'repositories/categories_repository.dart';
import 'repositories/expenses_repository.dart';
import 'repositories/members_repository.dart';
import 'repositories/outbox_queue.dart';
import 'repositories/prefs_repository.dart';
import 'repositories/recurring_repository.dart';

final _log = Logger('budgets');

typedef BudgetMonth = ({String budgetId, YearMonth month});

typedef BudgetDay = ({String budgetId, LocalDate day});

typedef BudgetPeriod = ({String budgetId, LocalDate from, LocalDate to});

typedef BudgetYear = ({String budgetId, int year});

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

final currentUserProvider = Provider<CurrentUser>(
  (ref) => LocalPrefsCurrentUser(ref.watch(prefsRepositoryProvider)),
  name: 'currentUser',
);

final outboxQueueProvider = Provider<OutboxQueue>(
  (ref) => DriftOutboxQueue(
    ref.watch(appDatabaseProvider),
    now: ref.watch(clockProvider).now,
  ),
  name: 'outboxQueue',
);

final expensesRepositoryProvider = Provider<ExpensesRepository>(
  (ref) => DriftExpensesRepository(
    ref.watch(appDatabaseProvider),
    currentUser: ref.watch(currentUserProvider),
    outbox: ref.watch(outboxQueueProvider),
    now: ref.watch(clockProvider).now,
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

final expenseProvider = StreamProvider.autoDispose.family<Expense?, String>(
  (ref, id) => ref.watch(expensesRepositoryProvider).watchById(id),
  name: 'expense',
  retry: _noRetry,
);

final budgetProvider = StreamProvider.autoDispose.family<Budget?, String>(
  (ref, budgetId) => ref.watch(budgetsRepositoryProvider).watchById(budgetId),
  name: 'budget',
  retry: _noRetry,
);

final selectedBudgetIdProvider = StreamProvider<String?>(
  (ref) => ref
      .watch(budgetsRepositoryProvider)
      .watchAll()
      .map(_personalBudgetId)
      .distinct()
      .map(_logSelected),
  name: 'selectedBudgetId',
  retry: _noRetry,
);

String? _personalBudgetId(List<Budget> budgets) {
  for (final budget in budgets) {
    if (budget.kind == BudgetKind.personal) return budget.id;
  }
  return null;
}

String? _logSelected(String? budgetId) {
  if (budgetId == null) {
    _log.info('selected budget: none, no personal budget in database yet');
  } else {
    _log.info('selected budget budgetId=$budgetId reason=personal');
  }
  return budgetId;
}
