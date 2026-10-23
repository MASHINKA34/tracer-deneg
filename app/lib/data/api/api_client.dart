import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:logging/logging.dart';
import 'package:shared/logging.dart';

import 'api_config.dart';
import 'api_exception.dart';
import 'auth_interceptor.dart';
import 'api_log_interceptor.dart';
import 'request_id_interceptor.dart';
import 'token_store.dart';

final _log = Logger('api');

final class ApiResponse {
  const ApiResponse({
    required this.statusCode,
    required this.data,
    required this.requestId,
  });

  final int statusCode;
  final Object? data;
  final String requestId;
}

final class ApiHealth {
  const ApiHealth({
    required this.status,
    required this.version,
    required this.db,
    required this.requestId,
  });

  final String status;
  final String version;
  final String db;
  final String requestId;
}

class ApiClient {
  ApiClient({
    required this.config,
    required TokenStore tokens,
    HttpClientAdapter? adapter,
    String Function()? newRequestId,
  }) : _newRequestId = newRequestId ?? generateRequestId,
       _dio = Dio(
         BaseOptions(
           baseUrl: config.baseUrlText,
           connectTimeout: apiConnectTimeout,
           receiveTimeout: apiReceiveTimeout,
           responseType: ResponseType.plain,
           headers: {Headers.acceptHeader: Headers.jsonContentType},
         ),
       ) {
    if (adapter != null) _dio.httpClientAdapter = adapter;
    _dio.interceptors.addAll([
      RequestIdInterceptor(generate: _newRequestId),
      const ApiLogInterceptor(),
      AuthInterceptor(
        tokens: tokens,
        dio: _dio,
        newRequestId: _newRequestId,
        onSessionExpired: _reportSessionExpired,
      ),
    ]);
    _log.info(
      'api client ready baseUrl=${config.baseUrlText} '
      'source=${config.fromDefine ? 'API_URL' : 'debug-default'} '
      'connectTimeout=${apiConnectTimeout.inSeconds}s '
      'receiveTimeout=${apiReceiveTimeout.inSeconds}s',
    );
  }

  final ApiConfig config;
  final Dio _dio;
  final String Function() _newRequestId;
  final StreamController<SessionExpired> _sessionExpired =
      StreamController<SessionExpired>.broadcast();

  Stream<SessionExpired> get sessionExpired => _sessionExpired.stream;

  void _reportSessionExpired(SessionExpired event) {
    _log.info(
      'session expired event reason=${event.reason.name} '
      'on ${event.method} ${event.path} rid=${event.requestId} '
      'listeners=${_sessionExpired.hasListener}',
    );
    _sessionExpired.add(event);
  }

  Future<ApiResponse> get(
    String path, {
    Map<String, Object?>? query,
    bool auth = true,
  }) => send('GET', path, query: query, auth: auth);

  Future<ApiResponse> post(String path, {Object? body, bool auth = true}) =>
      send('POST', path, body: body, auth: auth);

  Future<ApiResponse> patch(String path, {Object? body, bool auth = true}) =>
      send('PATCH', path, body: body, auth: auth);

  Future<ApiResponse> delete(String path, {Object? body, bool auth = true}) =>
      send('DELETE', path, body: body, auth: auth);

  Future<ApiResponse> send(
    String method,
    String path, {
    Object? body,
    Map<String, Object?>? query,
    bool auth = true,
  }) async {
    final rid = _newRequestId();
    final Response<String> response;
    try {
      response = await _dio.request<String>(
        path,
        data: body,
        queryParameters: query,
        options: Options(
          method: method,
          extra: {apiRequestIdKey: rid, apiAuthKey: auth},
        ),
      );
    } on DioException catch (e) {
      final mapped = apiExceptionFromDio(e);
      _log.fine(
        '$method $path ${e.type.name} → ${mapped.runtimeType}: '
        '${mapped.details} rid=$rid',
      );
      Error.throwWithStackTrace(mapped, e.stackTrace);
    }
    return ApiResponse(
      statusCode: response.statusCode ?? 0,
      data: _decode(response, rid),
      requestId: rid,
    );
  }

  Future<ApiHealth> health() async {
    final response = await get('/health', auth: false);
    final json = response.data;
    if (json is! Map<String, Object?> || json['status'] is! String) {
      _log.warning(
        'GET /health answered without status object → bad response '
        'rid=${response.requestId}',
      );
      throw ApiBadResponse(
        method: 'GET',
        path: '${config.baseUrl.path}/health',
        requestId: response.requestId,
        statusCode: response.statusCode,
        reason: 'health: expected {status, version, db}',
      );
    }
    return ApiHealth(
      status: json['status']! as String,
      version: '${json['version']}',
      db: '${json['db']}',
      requestId: response.requestId,
    );
  }

  Object? _decode(Response<String> response, String rid) {
    final text = response.data;
    if (text == null || text.isEmpty) return null;
    try {
      return jsonDecode(text);
    } on FormatException catch (e) {
      final options = response.requestOptions;
      _log.warning(
        '${options.method} ${options.uri.path} ${response.statusCode} body is '
        'not JSON → bad response: ${e.message} rid=$rid',
      );
      throw ApiBadResponse(
        method: options.method,
        path: options.uri.path,
        requestId: rid,
        statusCode: response.statusCode,
        reason: 'body is not JSON',
      );
    }
  }

  void close() {
    _log.fine('api client closed baseUrl=${config.baseUrlText}');
    _dio.close(force: true);
    unawaited(_sessionExpired.close());
  }
}
