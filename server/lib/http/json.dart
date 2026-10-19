import 'dart:convert';

import 'package:shelf/shelf.dart';

const _jsonHeaders = {'content-type': 'application/json; charset=utf-8'};

/// JSON-ответ с заданным статусом.
Response jsonResponse(int status, Object? body) =>
    Response(status, body: jsonEncode(body), headers: _jsonHeaders);

/// Ошибка по формату API (00-spec §9):
/// `{"error": {"code": "…", "message": "…", "rid": "…"}}`.
Response errorResponse(
  int status,
  String code,
  String message, {
  String? rid,
}) => jsonResponse(status, {
  'error': {'code': code, 'message': message, 'rid': ?rid},
});
