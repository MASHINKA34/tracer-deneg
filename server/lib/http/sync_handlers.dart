import 'package:logging/logging.dart';
import 'package:shared/shared.dart';
import 'package:shelf/shelf.dart';

import '../auth/auth_middleware.dart';
import '../sync/pull_service.dart';
import 'json.dart';

final _log = Logger('sync');

Handler pullHandler(PullService pull) => (Request request) async {
  final userId = authContextOf(request).userId;
  final parameters = request.url.queryParameters;
  final SyncPullQuery query;
  try {
    query = SyncPullQuery.fromQueryParameters(parameters);
  } on FormatException catch (e) {
    String? raw(String key) {
      final value = parameters[key];
      return value == null ? null : truncateBody(value, maxBytes: 64);
    }

    _log.warning(
      'pull rejected reason=${ApiErrorCode.badRequest.code} userId=$userId '
      '${formatContext({'problem': e.message, 'cursor': raw('cursor'), 'limit': raw('limit')})}',
    );
    return errorResponse(
      400,
      ApiErrorCode.badRequest.code,
      'Неверный запрос: cursor — целое число от 0, '
      'limit — от 1 до $pullPageSize',
    );
  }
  final response = await pull.pull(userId: userId, query: query);
  return jsonResponse(
    200,
    response.toJson(),
  ).change(headers: {'cache-control': 'no-store'});
};
