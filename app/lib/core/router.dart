import 'package:go_router/go_router.dart';

import '../features/month/month_stub_screen.dart';
import 'logging/navigation_logger.dart';

/// Маршруты приложения. Пока один экран — заглушка «Милиончик»
/// (главная появится на этапе 05).
GoRouter buildRouter() => GoRouter(
  initialLocation: '/',
  observers: [NavigationLogger()],
  routes: [
    GoRoute(
      path: '/',
      name: 'month',
      builder: (context, state) => const MonthStubScreen(),
    ),
  ],
);
