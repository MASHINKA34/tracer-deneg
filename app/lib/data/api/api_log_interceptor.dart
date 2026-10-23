import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:logging/logging.dart';
import 'package:shared/logging.dart';

import 'api_log_body.dart';
import 'request_id_interceptor.dart';

final _log = Logger('api');

const String apiStopwatchKey = 'milionchik.stopwatch';

const String apiAttemptKey = 'milionchik.attempt';

class ApiLogInterceptor extends Interceptor {
  const ApiLogInterceptor();

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[apiStopwatchKey] = Stopwatch()..start();
    if (_log.isLoggable(Level.FINE)) {
      final body = requestBodyForLog(options.data);
      _log.fine(
        '→ ${options.method} ${options.uri.path} ${_tail(options)}'
        '${body == null ? '' : ' body=$body'}',
      );
    }
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    final options = response.requestOptions;
    _log.info(
      '${options.method} ${options.uri.path} ${response.statusCode} '
      'in ${_elapsedMs(options)}ms size=${responseSize(response)} '
      '${_tail(options)}',
    );
    _logResponseBody(response);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final options = err.requestOptions;
    final response = err.response;
    final ms = _elapsedMs(options);
    if (response != null) {
      final status = response.statusCode ?? 0;
      final code = errorCodeOf(response.data);
      _log.log(
        status >= 500 ? Level.WARNING : Level.INFO,
        '${options.method} ${options.uri.path} $status in ${ms}ms '
        'size=${responseSize(response)} ${_tail(options)}'
        '${code == null ? '' : ' code=$code'}',
      );
      _logResponseBody(response);
    } else if (err.type == DioExceptionType.cancel) {
      _log.info(
        '${options.method} ${options.uri.path} cancelled after ${ms}ms '
        '${_tail(options)}',
      );
    } else {
      _log.warning(
        '${options.method} ${options.uri.path} failed in ${ms}ms: '
        '${describeDioFailure(err)} ${_tail(options)}',
        null,
        err.stackTrace,
      );
    }
    handler.next(err);
  }

  void _logResponseBody(Response<dynamic> response) {
    if (!_log.isLoggable(Level.FINE)) return;
    final body = responseBodyForLog(response.data);
    if (body == null) return;
    final options = response.requestOptions;
    _log.fine(
      '← ${options.method} ${options.uri.path} ${response.statusCode} '
      '${_tail(options)} body=$body',
    );
  }
}

String _tail(RequestOptions options) {
  final attempt = options.extra[apiAttemptKey];
  final rid = options.extra[apiRequestIdKey];
  return 'rid=$rid${attempt is int && attempt > 1 ? ' attempt=$attempt' : ''}';
}

int _elapsedMs(RequestOptions options) {
  final stopwatch = options.extra[apiStopwatchKey];
  return stopwatch is Stopwatch ? stopwatch.elapsedMilliseconds : -1;
}

int responseSize(Response<dynamic> response) {
  final header = int.tryParse(
    response.headers.value(Headers.contentLengthHeader) ?? '',
  );
  if (header != null) return header;
  final data = response.data;
  if (data == null) return 0;
  if (data is String) return utf8.encode(data).length;
  if (data is List<int>) return data.length;
  return utf8.encode(jsonEncode(data)).length;
}

String? errorCodeOf(Object? data) {
  Object? json = data;
  if (data is String) {
    if (data.isEmpty) return null;
    try {
      json = jsonDecode(data);
    } on FormatException catch (e) {
      _log.fine('error body is not JSON (${e.message}) → no error code');
      return null;
    }
  }
  if (json is! Map) return null;
  final error = json['error'];
  if (error is! Map) return null;
  final code = error['code'];
  return code is String ? code : null;
}

String describeDioFailure(DioException err) {
  final kind = switch (err.type) {
    DioExceptionType.connectionTimeout =>
      'connect timeout after ${_seconds(err.requestOptions.connectTimeout)}',
    DioExceptionType.sendTimeout =>
      'send timeout after ${_seconds(err.requestOptions.sendTimeout)}',
    DioExceptionType.receiveTimeout =>
      'receive timeout after ${_seconds(err.requestOptions.receiveTimeout)}',
    DioExceptionType.transformTimeout => 'transform timeout',
    DioExceptionType.badCertificate => 'bad certificate',
    DioExceptionType.connectionError => 'connection error',
    DioExceptionType.cancel => 'cancelled',
    DioExceptionType.badResponse => 'bad response',
    DioExceptionType.unknown => 'unknown error',
  };
  final cause = err.error;
  if (cause == null) return kind;
  return '$kind cause=${describeCauseForLog(cause)}';
}

String describeCauseForLog(Object cause) {
  if (cause is HttpException) {
    final details = cause.uri == null ? '' : ' path=${cause.uri!.path}';
    return 'HttpException: ${cause.message}$details';
  }
  return describeError(cause);
}

String _seconds(Duration? duration) {
  if (duration == null) return '?';
  final ms = duration.inMilliseconds;
  return ms % 1000 == 0 ? '${ms ~/ 1000}s' : '${ms}ms';
}
