import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:logging/logging.dart';
import 'package:shared/logging.dart';

import 'api_config.dart';
import 'api_log_interceptor.dart';
import 'request_id_interceptor.dart';

final _log = Logger('api');

const String apiAuthKey = 'milionchik.auth';

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
    final response = await _dio.request<String>(
      path,
      data: body,
      queryParameters: query,
      options: Options(
        method: method,
        extra: {apiRequestIdKey: rid, apiAuthKey: auth},
      ),
    );
    return ApiResponse(
      statusCode: response.statusCode ?? 0,
      data: _decode(response),
      requestId: rid,
    );
  }

  Future<ApiHealth> health() async {
    final response = await get('/health', auth: false);
    final json = response.data;
    if (json is! Map<String, Object?>) {
      throw FormatException(
        'health: expected JSON object, got ${json.runtimeType}',
      );
    }
    return ApiHealth(
      status: '${json['status']}',
      version: '${json['version']}',
      db: '${json['db']}',
      requestId: response.requestId,
    );
  }

  Object? _decode(Response<String> response) {
    final text = response.data;
    if (text == null || text.isEmpty) return null;
    return jsonDecode(text);
  }

  void close() {
    _log.fine('api client closed baseUrl=${config.baseUrlText}');
    _dio.close(force: true);
  }
}
