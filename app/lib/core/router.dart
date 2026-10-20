import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../features/month/month_stub_screen.dart';
import '../ui/catalog/catalog_screen.dart';
import 'logging/navigation_logger.dart';

/// Маршруты приложения. Пока заглушка «Милиончик» (главная появится на
/// этапе 05) и — только в debug-сборке — каталог компонентов `/catalog`
/// (долгий тап по логотипу на заглушке).
GoRouter buildRouter() => GoRouter(
  initialLocation: '/',
  observers: [NavigationLogger()],
  routes: [
    GoRoute(
      path: '/',
      name: 'month',
      builder: (context, state) => const MonthStubScreen(),
    ),
    if (kDebugMode)
      GoRoute(
        path: '/catalog',
        name: 'catalog',
        builder: (context, state) => const CatalogScreen(),
      ),
  ],
);
