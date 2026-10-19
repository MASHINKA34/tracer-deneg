import 'dart:io';

import 'package:logging/logging.dart';
import 'package:shared/logging.dart';
import 'package:shelf/shelf.dart';

import 'json.dart';

final _log = Logger('http');

/// Заголовок с id запроса (00-spec §9).
const requestIdHeader = 'X-Request-Id';

/// Ключ id запроса в `Request.context`.
const requestIdContextKey = 'milionchik.rid';

/// Берёт `X-Request-Id` из запроса (если он допустимый) или генерирует новый,
/// выполняет обработчик в зоне с этим id (все логи запроса получают `rid=…`)
/// и возвращает id в заголовке ответа.
Middleware requestIdMiddleware() =>
    (inner) => (request) {
      final incoming = request.headers[requestIdHeader];
      final valid = isValidRequestId(incoming);
      final rid = valid ? incoming! : generateRequestId();
      return runWithRequestId(rid, () async {
        if (incoming != null && !valid) {
          _log.fine(
            'invalid $requestIdHeader replaced (length=${incoming.length})',
          );
        }
        final response = await inner(
          request.change(context: {requestIdContextKey: rid}),
        );
        return response.change(headers: {requestIdHeader: rid});
      });
    };

/// Лог каждого запроса: на debug — что пришло и от кого, на info — итог
/// одной строкой: метод, путь (без query — там могут быть секреты), статус,
/// время, размер ответа, IP. 5xx — на уровне warn.
Middleware accessLogMiddleware() =>
    (inner) => (request) async {
      final sw = Stopwatch()..start();
      final method = request.method;
      final path = request.requestedUri.path;
      final ip = _remoteIp(request);
      _log.fine(
        'request $method $path '
        '${formatContext({'ip': ip, 'ua': request.headers['user-agent']})}',
      );
      try {
        final response = await inner(request);
        final status = response.statusCode;
        _log.log(
          status >= 500 ? Level.WARNING : Level.INFO,
          '$method $path $status in ${sw.elapsedMilliseconds}ms '
          'size=${response.contentLength ?? '?'} ip=$ip',
        );
        return response;
      } catch (e, st) {
        // Сюда доходят только HijackException и ошибки, которые не поймал
        // errorMiddleware; пишем и пробрасываем дальше в shelf.
        _log.warning(
          '$method $path aborted in ${sw.elapsedMilliseconds}ms ip=$ip: '
          '${describeError(e)}',
          e,
          st,
        );
        rethrow;
      }
    };

/// Любое необработанное исключение → лог с полным стеком и ответ 500
/// с `rid`, по которому ошибку найдут в логе.
Middleware errorMiddleware() =>
    (inner) => (request) async {
      try {
        return await inner(request);
      } on HijackException {
        rethrow;
      } catch (e, st) {
        final rid = currentRequestId();
        _log.severe(
          'unhandled error in ${request.method} ${request.requestedUri.path}: '
          '${describeError(e)}',
          e,
          st,
        );
        return errorResponse(
          500,
          'internal',
          'Внутренняя ошибка сервера',
          rid: rid,
        );
      }
    };

String _remoteIp(Request request) {
  final info = request.context['shelf.io.connection_info'];
  return info is HttpConnectionInfo ? info.remoteAddress.address : '-';
}
