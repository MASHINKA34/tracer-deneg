import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/auth_middleware.dart';
import '../auth/auth_service.dart';
import '../db/database.dart';
import 'auth_handlers.dart';
import 'health.dart';
import 'json.dart';
import 'middleware.dart';

/// Обработчик всех запросов: id запроса → лог запроса → перехват ошибок →
/// маршруты `/api/v1/…`.
Handler buildHandler({required Database db, required AuthService auth}) {
  final requireAuth = authMiddleware(auth);
  final router = Router(notFoundHandler: _notFound)
    ..get('/api/v1/health', healthHandler(db))
    ..post('/api/v1/auth/register', registerHandler(auth))
    ..post('/api/v1/auth/login', loginHandler(auth))
    ..post('/api/v1/auth/refresh', refreshHandler(auth))
    ..post(
      '/api/v1/auth/logout',
      const Pipeline()
          .addMiddleware(requireAuth)
          .addHandler(logoutHandler(auth)),
    );

  return const Pipeline()
      .addMiddleware(requestIdMiddleware())
      .addMiddleware(accessLogMiddleware())
      .addMiddleware(errorMiddleware())
      .addHandler(router.call);
}

Response _notFound(Request request) =>
    errorResponse(404, 'not_found', 'Не найдено');
