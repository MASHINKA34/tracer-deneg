import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:shared/shared.dart';
import 'package:shelf/shelf.dart';

import '../auth/auth_middleware.dart';
import '../sync/pull_service.dart';
import '../sync/push_service.dart';
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

Handler pushHandler(PushService push) => (Request request) async {
  final userId = authContextOf(request).userId;
  final Object? body;
  try {
    body = jsonDecode(await request.readAsString());
  } on FormatException catch (e) {
    return _pushBadRequest(
      userId,
      'body is not JSON: ${e.message}',
      'Неверный запрос: тело должно быть JSON',
    );
  }
  final SyncPushRequest parsed;
  try {
    parsed = SyncPushRequest.fromJson(body);
  } on FormatException catch (e) {
    return _pushBadRequest(
      userId,
      truncateBody(e.message, maxBytes: 200),
      'Неверный запрос: нужны batchId и changes '
      '[{entity, op, id, data, updatedAt}]',
    );
  }
  if (!isValidBatchId(parsed.batchId)) {
    return _pushBadRequest(
      userId,
      'batchId is not 1-64 chars of [A-Za-z0-9._-] '
          '(length ${parsed.batchId.length})',
      'Неверный запрос: batchId — от 1 до 64 символов '
          'из латинских букв, цифр, «.», «_» и «-»',
      changes: parsed.changes.length,
    );
  }
  if (parsed.changes.length > maxPushBatchSize) {
    return _pushBadRequest(
      userId,
      'too many changes, limit $maxPushBatchSize',
      'Слишком много изменений в одной пачке: не больше $maxPushBatchSize',
      batchId: parsed.batchId,
      changes: parsed.changes.length,
    );
  }
  final result = await push.push(userId: userId, request: parsed);
  return jsonResponse(
    200,
    result.response.toJson(),
  ).change(headers: {'cache-control': 'no-store'});
};

Response _pushBadRequest(
  String userId,
  String problem,
  String message, {
  String? batchId,
  int? changes,
}) {
  _log.warning(
    'push rejected reason=${ApiErrorCode.badRequest.code} userId=$userId '
    '${formatContext({'problem': problem, 'batchId': batchId, 'changes': changes})}',
  );
  return errorResponse(400, ApiErrorCode.badRequest.code, message);
}
