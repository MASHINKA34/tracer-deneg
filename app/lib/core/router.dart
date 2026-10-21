import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import '../features/month/month_stub_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/shell/tab_stub_screen.dart';
import '../ui/catalog/catalog_screen.dart';
import 'logging/navigation_logger.dart';

final _log = Logger('nav');

abstract final class AppRoutes {
  static const String month = '/month';
  static const String stats = '/stats';
  static const String recurring = '/recurring';
  static const String profile = '/profile';
  static const String catalog = '/catalog';
}

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
              child: AppShell(navigationShell: navigationShell),
            ),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.month,
                name: 'month',
                builder: (context, state) => const MonthStubScreen(),
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
