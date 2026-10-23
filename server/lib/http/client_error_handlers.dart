import 'dart:convert';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:shared/shared.dart';
import 'package:shelf/shelf.dart';

import '../auth/auth_middleware.dart';
import '../client_errors/client_error_fields.dart';
import '../client_errors/client_error_store.dart';
import 'json.dart';

final _log = Logger('client-errors');

Handler clientErrorsHandler(ClientErrorStore store) => (Request request) async {
  final sw = Stopwatch()..start();
  final bytes = await _readBytes(request);
  final Object? body;
  try {
    body = jsonDecode(utf8.decode(bytes));
  } on FormatException catch (e) {
    return _rejected(
      'body is not UTF-8 JSON: ${e.message}',
      bytes.length,
      sw,
      'Неверный отчёт: тело должно быть JSON',
    );
  }
  final ClientErrorReport report;
  try {
    report = ClientErrorReport.fromJson(body);
  } on FormatException catch (e) {
    return _rejected(
      e.message,
      bytes.length,
      sw,
      'Неверный отчёт: нужны kind (crash, error или user_report), '
      'appVersion и message',
    );
  }
  final sdk = report.androidSdk;
  if (sdk != null && (sdk < 0 || sdk > maxClientErrorAndroidSdk)) {
    return _rejected(
      'ClientErrorReport.androidSdk: out of range '
          '0..$maxClientErrorAndroidSdk',
      bytes.length,
      sw,
      'Неверный отчёт: androidSdk вне допустимого диапазона',
    );
  }

  final caller = optionalAuthContextOf(request);
  final prepared = prepareClientError(report);
  final stored = await store.insert(prepared, userId: caller?.userId);
  final context = {
    'id': stored.id,
    'kind': prepared.kind.code,
    'appVersion': logSafe(prepared.appVersion),
    'androidSdk': prepared.androidSdk ?? 'none',
    'userId': caller?.userId ?? 'none',
    'auth': caller == null ? (authSkipReasonOf(request) ?? 'none') : 'ok',
    'size': bytes.length,
    'messageBytes': prepared.messageBytes,
    'messageHash': textFingerprint(prepared.message),
    'stackBytes': prepared.stackBytes ?? 0,
    'logsBytes': prepared.logsBytes ?? 0,
    'truncated': prepared.truncated.isEmpty
        ? null
        : prepared.truncated.join(','),
    'nulReplaced': prepared.nulReplaced == 0 ? null : prepared.nulReplaced,
  };
  _log.warning(
    'client error received ${formatContext(context)} '
    'in ${sw.elapsedMilliseconds}ms',
  );
  return jsonResponse(202, {'id': stored.id});
};

Response _rejected(String problem, int size, Stopwatch sw, String message) {
  final safeProblem = logSafe(
    problem.replaceAll(RegExp(r'"[^"]*"'), '"…"'),
    maxBytes: 200,
  );
  _log.warning(
    'client error rejected reason=${ApiErrorCode.badRequest.code} '
    '${formatContext({'problem': safeProblem, 'size': size})} '
    'in ${sw.elapsedMilliseconds}ms',
  );
  return errorResponse(400, ApiErrorCode.badRequest.code, message);
}

Future<List<int>> _readBytes(Request request) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in request.read()) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}
