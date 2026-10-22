import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../account/account_service.dart';
import '../auth/auth_middleware.dart';
import '../auth/auth_service.dart';
import '../db/database.dart';
import '../limits/request_limits.dart';
import 'account_handlers.dart';
import 'auth_handlers.dart';
import 'health.dart';
import 'json.dart';
import 'middleware.dart';

/// Обработчик всех запросов: id запроса → лог запроса → перехват ошибок →
/// маршруты `/api/v1/…`.
Handler buildHandler({
  required Database db,
  required AuthService auth,
  RequestLimits? limits,
}) {
  final requestLimits = limits ?? RequestLimits();
  final requireAuth = authMiddleware(auth);
  final account = AccountService(db: db, hasher: auth.hasher);
  final router = Router(notFoundHandler: _notFound)
    ..get('/api/v1/health', healthHandler(db))
    ..post('/api/v1/auth/register', registerHandler(auth))
    ..post(
      '/api/v1/auth/login',
      const Pipeline()
          .addMiddleware(requestLimits.loginAttempts('login'))
          .addHandler(loginHandler(auth)),
    )
    ..post('/api/v1/auth/refresh', refreshHandler(auth))
    ..post(
      '/api/v1/auth/recover',
      const Pipeline()
          .addMiddleware(requestLimits.loginAttempts('recover'))
          .addHandler(recoverHandler(auth)),
    )
    ..post(
      '/api/v1/auth/recovery-code',
      const Pipeline()
          .addMiddleware(requireAuth)
          .addHandler(recoveryCodeHandler(auth)),
    )
    ..post(
      '/api/v1/auth/logout',
      const Pipeline()
          .addMiddleware(requireAuth)
          .addHandler(logoutHandler(auth)),
    )
    ..get(
      '/api/v1/me',
      const Pipeline()
          .addMiddleware(requireAuth)
          .addHandler(meHandler(account)),
    )
    ..patch(
      '/api/v1/me',
      const Pipeline()
          .addMiddleware(requireAuth)
          .addHandler(updateMeHandler(account)),
    )
    ..delete(
      '/api/v1/account',
      const Pipeline()
          .addMiddleware(requireAuth)
          .addHandler(deleteAccountHandler(account)),
    );

  return const Pipeline()
      .addMiddleware(requestIdMiddleware())
      .addMiddleware(accessLogMiddleware())
      .addMiddleware(errorMiddleware())
      .addMiddleware(requestLimits.ipRateLimit())
      .addMiddleware(requestLimits.bodySizeLimit())
      .addHandler(router.call);
}

Response _notFound(Request request) =>
    errorResponse(404, 'not_found', 'Не найдено');
