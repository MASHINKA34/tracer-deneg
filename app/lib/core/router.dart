import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart' show LocalDate;

import '../features/expense/new_expense_screen.dart';
import '../features/month/month_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/shell/expense_stub_screen.dart';
import '../features/shell/search_stub_screen.dart';
import '../features/shell/tab_stub_screen.dart';
import '../ui/catalog/catalog_screen.dart';
import 'app_frame.dart';
import 'logging/navigation_logger.dart';

final _log = Logger('nav');

abstract final class AppRoutes {
  static const String month = '/month';
  static const String stats = '/stats';
  static const String recurring = '/recurring';
  static const String profile = '/profile';
  static const String newExpense = '/expense/new';
  static const String expense = '/expense/:id';
  static const String search = '/search';
  static const String catalog = '/catalog';

  static const String newExpenseName = 'newExpense';
  static const String searchName = 'search';
  static const String expenseName = 'expense';

  static const String dateParameter = 'date';

  static String newExpenseOn(LocalDate date) => Uri(
    path: newExpense,
    queryParameters: {dateParameter: '$date'},
  ).toString();

  static String expenseOf(String id) => '/expense/${Uri.encodeComponent(id)}';
}

const Duration newExpenseTransition = Duration(milliseconds: 300);

/// Маршруты приложения. Пока заглушка «Милиончик» (главная появится на
/// этапе 05) и — только в debug-сборке — каталог компонентов `/catalog`
/// (долгий тап по логотипу на заглушке).
GoRouter buildRouter({String initialLocation = AppRoutes.month}) {
  final rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');
  return GoRouter(
    navigatorKey: rootKey,
    initialLocation: initialLocation,
    observers: [NavigationLogger()],
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
                builder: (context, state) =>
                    TabStubScreen(title: (l10n) => l10n.statsTitle),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.recurring,
                name: 'recurring',
                builder: (context, state) =>
                    TabStubScreen(title: (l10n) => l10n.recurringTitle),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.profile,
                name: 'profile',
                builder: (context, state) =>
                    TabStubScreen(title: (l10n) => l10n.profileTitle),
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
          child: ExpenseStubScreen(expenseId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: AppRoutes.search,
        name: AppRoutes.searchName,
        parentNavigatorKey: rootKey,
        builder: (context, state) => const AppFrame(child: SearchStubScreen()),
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
