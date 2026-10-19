import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../db/database.dart';
import 'health.dart';
import 'json.dart';
import 'middleware.dart';

/// Обработчик всех запросов: id запроса → лог запроса → перехват ошибок →
/// маршруты `/api/v1/…`.
Handler buildHandler({required Database db}) {
  final router = Router(notFoundHandler: _notFound)
    ..get('/api/v1/health', healthHandler(db));

  return const Pipeline()
      .addMiddleware(requestIdMiddleware())
      .addMiddleware(accessLogMiddleware())
      .addMiddleware(errorMiddleware())
      .addHandler(router.call);
}

Response _notFound(Request request) =>
    errorResponse(404, 'not_found', 'Не найдено');
