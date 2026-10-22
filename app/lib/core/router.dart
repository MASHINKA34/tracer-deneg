import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart' show LocalDate;

import '../features/categories/categories_screen.dart';
import '../features/categories/category_editor_screen.dart';
import '../features/expense/edit_expense_screen.dart';
import '../features/expense/new_expense_screen.dart';
import '../features/export/export_profile_entry.dart';
import '../features/export/export_screen.dart';
import '../features/month/month_screen.dart';
import '../features/recurring/recurring_editor_screen.dart';
import '../features/recurring/recurring_screen.dart';
import '../features/search/search_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/shell/tab_stub_screen.dart';
import '../features/stats/stats_screen.dart';
import '../ui/catalog/catalog_screen.dart';
import 'app_frame.dart';
import 'logging/navigation_logger.dart';

final _log = Logger('nav');

abstract final class AppRoutes {
  static const String month = '/month';
  static const String stats = '/stats';
  static const String recurring = '/recurring';
  static const String newRecurring = '/recurring/new';
  static const String recurringRule = '/recurring/:id';
  static const String profile = '/profile';
  static const String newExpense = '/expense/new';
  static const String expense = '/expense/:id';
  static const String search = '/search';
  static const String categories = '/categories';
  static const String newCategory = '/categories/new';
  static const String category = '/categories/:id';
  static const String export = '/export';
  static const String catalog = '/catalog';

  static const String newExpenseName = 'newExpense';
  static const String searchName = 'search';
  static const String expenseName = 'expense';
  static const String categoriesName = 'categories';
  static const String newCategoryName = 'newCategory';
  static const String categoryName = 'category';
  static const String exportName = 'export';
  static const String newRecurringName = 'newRecurring';
  static const String recurringRuleName = 'recurringRule';

  static const String deepLinkScheme = 'milionchik';
  static const String addDeepLinkHost = 'add';

  static const String dateParameter = 'date';

  static const String categoryParameter = 'category';
  static const String fromParameter = 'from';
  static const String toParameter = 'to';

  static String newExpenseOn(LocalDate date) => Uri(
    path: newExpense,
    queryParameters: {dateParameter: '$date'},
  ).toString();

  static String expenseOf(String id) => '/expense/${Uri.encodeComponent(id)}';

  static String categoryOf(String id) =>
      '/categories/${Uri.encodeComponent(id)}';

  static String recurringRuleOf(String id) =>
      '/recurring/${Uri.encodeComponent(id)}';

  static String searchFor({
    required String categoryId,
    required LocalDate from,
    required LocalDate to,
  }) => Uri(
    path: search,
    queryParameters: {
      categoryParameter: categoryId,
      fromParameter: '$from',
      toParameter: '$to',
    },
  ).toString();
}

final class SearchRouteFilter {
  const SearchRouteFilter({this.categoryId, this.from, this.to});

  factory SearchRouteFilter.fromQuery(Map<String, String> query) {
    final categoryId = query[AppRoutes.categoryParameter];
    LocalDate? date(String name) {
      final text = query[name];
      if (text == null) return null;
      final parsed = LocalDate.tryParse(text);
      if (parsed == null) {
        _log.warning(
          'search route: $name=${text.length > 10 ? '${text.substring(0, 10)}…' : text} '
          'is not a yyyy-MM-dd date, opening search without it',
        );
      }
      return parsed;
    }

    var from = date(AppRoutes.fromParameter);
    var to = date(AppRoutes.toParameter);
    if (from != null && to != null && from > to) {
      _log.warning(
        'search route: period $from..$to ends before it starts, '
        'opening search without period',
      );
      from = null;
      to = null;
    }
    return SearchRouteFilter(
      categoryId: categoryId == null || categoryId.isEmpty ? null : categoryId,
      from: from,
      to: to,
    );
  }

  final String? categoryId;
  final LocalDate? from;
  final LocalDate? to;

  bool get isEmpty => categoryId == null && from == null && to == null;

  @override
  bool operator ==(Object other) =>
      other is SearchRouteFilter &&
      other.categoryId == categoryId &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(categoryId, from, to);

  @override
  String toString() =>
      'category=${categoryId ?? '-'} period=${from ?? ''}..${to ?? ''}';
}

const Duration newExpenseTransition = Duration(milliseconds: 300);

bool isAddExpenseLink(Uri uri) =>
    uri.scheme == AppRoutes.deepLinkScheme &&
    uri.host == AppRoutes.addDeepLinkHost;

/// Маршруты приложения. Пока заглушка «Милиончик» (главная появится на
/// этапе 05) и — только в debug-сборке — каталог компонентов `/catalog`
/// (долгий тап по логотипу на заглушке).
GoRouter buildRouter({String initialLocation = AppRoutes.month}) {
  final rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');
  late final GoRouter router;
  return router = GoRouter(
    navigatorKey: rootKey,
    initialLocation: initialLocation,
    observers: [NavigationLogger()],
    redirect: (context, state) {
      if (!isAddExpenseLink(state.uri)) return null;
      final current = router.routerDelegate.currentConfiguration;
      _log.info(
        'deep link ${AppRoutes.deepLinkScheme}://${AppRoutes.addDeepLinkHost} '
        '→ ${AppRoutes.newExpense} over ${AppRoutes.month} '
        'from=${current.isEmpty ? 'cold start' : current.uri.path}',
      );
      SchedulerBinding.instance
        ..addPostFrameCallback((_) {
          _log.fine(
            'deep link add: ${AppRoutes.month} is shown, pushing '
            '${AppRoutes.newExpense}',
          );
          unawaited(router.push<void>(AppRoutes.newExpense));
        })
        ..ensureVisualUpdate();
      return AppRoutes.month;
    },
    onException: (context, state, router) {
      _log.warning(
        'no route for path=${state.uri.path} → opening ${AppRoutes.month}',
      );
      router.go(AppRoutes.month);
    },
    routes: [
      StatefulShellRoute.indexedStack(
        pageBuilder: (context, state, navigationShell) =>
            NoTransitionPage<void>(
              key: state.pageKey,
              name: 'shell',
              child: AppFrame(
                child: AppShell(navigationShell: navigationShell),
              ),
            ),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.month,
                name: 'month',
                builder: (context, state) => const MonthScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.stats,
                name: 'stats',
                builder: (context, state) => const StatsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.recurring,
                name: 'recurring',
                builder: (context, state) => const RecurringScreen(),
                routes: [
                  GoRoute(
                    path: 'new',
                    name: AppRoutes.newRecurringName,
                    parentNavigatorKey: rootKey,
                    builder: (context, state) =>
                        const AppFrame(child: RecurringEditorScreen()),
                  ),
                  GoRoute(
                    path: ':id',
                    name: AppRoutes.recurringRuleName,
                    parentNavigatorKey: rootKey,
                    builder: (context, state) => AppFrame(
                      child: RecurringEditorScreen(
                        ruleId: state.pathParameters['id'],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.profile,
                name: 'profile',
                builder: (context, state) => TabStubScreen(
                  title: (l10n) => l10n.profileTitle,
                  children: const [ExportProfileEntry()],
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.newExpense,
        name: AppRoutes.newExpenseName,
        parentNavigatorKey: rootKey,
        pageBuilder: (context, state) => CustomTransitionPage<void>(
          key: state.pageKey,
          name: state.name,
          fullscreenDialog: true,
          transitionDuration: newExpenseTransition,
          reverseTransitionDuration: newExpenseTransition,
          transitionsBuilder: slideUpTransition,
          child: AppFrame(
            child: NewExpenseScreen(
              date: state.uri.queryParameters[AppRoutes.dateParameter],
            ),
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.expense,
        name: AppRoutes.expenseName,
        parentNavigatorKey: rootKey,
        builder: (context, state) => AppFrame(
          child: EditExpenseScreen(expenseId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: AppRoutes.categories,
        name: AppRoutes.categoriesName,
        parentNavigatorKey: rootKey,
        builder: (context, state) => const AppFrame(child: CategoriesScreen()),
        routes: [
          GoRoute(
            path: 'new',
            name: AppRoutes.newCategoryName,
            parentNavigatorKey: rootKey,
            builder: (context, state) =>
                const AppFrame(child: CategoryEditorScreen()),
          ),
          GoRoute(
            path: ':id',
            name: AppRoutes.categoryName,
            parentNavigatorKey: rootKey,
            builder: (context, state) => AppFrame(
              child: CategoryEditorScreen(
                categoryId: state.pathParameters['id'],
              ),
            ),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.search,
        name: AppRoutes.searchName,
        parentNavigatorKey: rootKey,
        builder: (context, state) =>
            AppFrame(child: SearchScreen(query: state.uri.queryParameters)),
      ),
      GoRoute(
        path: AppRoutes.export,
        name: AppRoutes.exportName,
        parentNavigatorKey: rootKey,
        builder: (context, state) => const AppFrame(child: ExportScreen()),
      ),
      if (kDebugMode)
        GoRoute(
          path: AppRoutes.catalog,
          name: 'catalog',
          parentNavigatorKey: rootKey,
          builder: (context, state) => const CatalogScreen(),
        ),
    ],
  );
}

Widget slideUpTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  if (MediaQuery.disableAnimationsOf(context)) return child;
  return SlideTransition(
    position: animation.drive(
      Tween<Offset>(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
    ),
    child: child,
  );
}
