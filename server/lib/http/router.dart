import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../account/account_service.dart';
import '../auth/auth_middleware.dart';
import '../auth/auth_service.dart';
import '../budgets/budget_service.dart';
import '../client_errors/client_error_store.dart';
import '../db/database.dart';
import '../limits/request_limits.dart';
import '../sync/pull_service.dart';
import '../sync/push_service.dart';
import '../sync/sync_notifier.dart';
import '../web/delete_account_page.dart';
import '../web/privacy_page.dart';
import '../web/web_page.dart';
import '../ws/ws_handler.dart';
import '../ws/ws_hub.dart';
import '../ws/ws_protocol.dart';
import 'account_handlers.dart';
import 'auth_handlers.dart';
import 'budget_handlers.dart';
import 'client_error_handlers.dart';
import 'health.dart';
import 'json.dart';
import 'middleware.dart';
import 'sync_handlers.dart';

/// Обработчик всех запросов: id запроса → лог запроса → перехват ошибок →
/// маршруты `/api/v1/…` и веб-страницы.
Handler buildHandler({
  required Database db,
  required AuthService auth,
  required String inviteCodeSecret,
  RequestLimits? limits,
  SyncNotifier notifier = const NoopSyncNotifier(),
  WsHub? ws,
  PrivacySettings privacy = const PrivacySettings(),
  DateTime Function() now = DateTime.now,
}) {
  final requestLimits = limits ?? RequestLimits();
  final requireAuth = authMiddleware(auth);
  final account = AccountService(db: db, hasher: auth.hasher);
  final pull = PullService(db: db);
  final push = PushService(db: db, notifier: notifier);
  final budgets = BudgetService(
    db: db,
    inviteCodeSecret: inviteCodeSecret,
    now: now,
    notifier: notifier,
  );
  final clientErrors = ClientErrorStore(db);
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
          .addHandler(deleteAccountHandler(account, requestLimits)),
    )
    ..get(
      '/api/v1/sync/pull',
      const Pipeline().addMiddleware(requireAuth).addHandler(pullHandler(pull)),
    )
    ..post(
      '/api/v1/sync/push',
      const Pipeline().addMiddleware(requireAuth).addHandler(pushHandler(push)),
    )
    ..post(
      '/api/v1/budgets',
      const Pipeline()
          .addMiddleware(requireAuth)
          .addHandler(createBudgetHandler(budgets)),
    )
    ..delete(
      '/api/v1/budgets/<id>',
      const Pipeline()
          .addMiddleware(requireAuth)
          .addHandler(deleteBudgetHandler(budgets)),
    )
    ..post(
      '/api/v1/budgets/<id>/invites',
      const Pipeline()
          .addMiddleware(requireAuth)
          .addHandler(createInviteHandler(budgets)),
    )
    ..post(
      '/api/v1/budgets/<id>/leave',
      const Pipeline()
          .addMiddleware(requireAuth)
          .addHandler(leaveBudgetHandler(budgets)),
    )
    ..delete(
      '/api/v1/budgets/<id>/members/<userId>',
      const Pipeline()
          .addMiddleware(requireAuth)
          .addHandler(removeMemberHandler(budgets)),
    )
    ..post(
      '/api/v1/invites/join',
      const Pipeline()
          .addMiddleware(requireAuth)
          .addMiddleware(requestLimits.inviteJoinAttempts())
          .addHandler(joinBudgetHandler(budgets)),
    )
    ..post(
      '/api/v1/client-errors',
      const Pipeline()
          .addMiddleware(optionalAuthMiddleware(auth))
          .addHandler(clientErrorsHandler(clientErrors)),
    )
    ..get(
      privacyPath,
      const Pipeline()
          .addMiddleware(webErrorPages())
          .addHandler(privacyPageHandler(privacy)),
    )
    ..get(
      deleteAccountPath,
      const Pipeline()
          .addMiddleware(webErrorPages())
          .addHandler(deleteAccountFormHandler(privacy)),
    )
    ..post(
      deleteAccountPath,
      const Pipeline()
          .addMiddleware(webErrorPages())
          .addHandler(
            deleteAccountSubmitHandler(
              account: account,
              limits: requestLimits,
              privacy: privacy,
            ),
          ),
    );
  if (ws != null) {
    router.get(
      wsPath,
      const Pipeline().addMiddleware(requireAuth).addHandler(wsHandler(ws)),
    );
  }

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
