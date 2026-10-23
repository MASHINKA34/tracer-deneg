import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import 'api_log_interceptor.dart';
import 'request_id_interceptor.dart';

final _log = Logger('api');

sealed class ApiException implements Exception {
  const ApiException({
    required this.method,
    required this.path,
    required this.requestId,
  });

  final String method;
  final String path;
  final String? requestId;

  String get details;

  @override
  String toString() => '$runtimeType: $method $path $details rid=$requestId';
}

final class ApiErrorResponse extends ApiException {
  const ApiErrorResponse({
    required super.method,
    required super.path,
    required super.requestId,
    required this.statusCode,
    required this.error,
  });

  final int statusCode;
  final ApiError error;

  ApiErrorCode? get code => error.knownCode;

  @override
  String get details => '$statusCode code=${error.code}';
}

final class ApiServerFailure extends ApiException {
  const ApiServerFailure({
    required super.method,
    required super.path,
    required super.requestId,
    required this.statusCode,
    this.error,
  });

  final int statusCode;
  final ApiError? error;

  @override
  String get details =>
      '$statusCode${error == null ? '' : ' code=${error!.code}'}';
}

enum ApiNetworkProblem { connection, badCertificate, cancelled, unknown }

final class ApiNetworkFailure extends ApiException {
  const ApiNetworkFailure({
    required super.method,
    required super.path,
    required super.requestId,
    required this.problem,
    this.cause,
  });

  final ApiNetworkProblem problem;
  final Object? cause;

  @override
  String get details =>
      '${problem.name}'
      '${cause == null ? '' : ' cause=${describeCauseForLog(cause!)}'}';
}

enum ApiTimeoutPhase { connect, send, receive }

final class ApiTimeout extends ApiException {
  const ApiTimeout({
    required super.method,
    required super.path,
    required super.requestId,
    required this.phase,
    this.limit,
  });

  final ApiTimeoutPhase phase;
  final Duration? limit;

  @override
  String get details =>
      '${phase.name} timeout'
      '${limit == null ? '' : ' after ${limit!.inMilliseconds}ms'}';
}

final class ApiBadResponse extends ApiException {
  const ApiBadResponse({
    required super.method,
    required super.path,
    required super.requestId,
    required this.statusCode,
    required this.reason,
  });

  final int? statusCode;
  final String reason;

  @override
  String get details => '${statusCode ?? '-'} $reason';
}

enum SessionEndReason {
  refreshRejected,
  sessionRejected,
  noSession,
  endedEarlier,
}

final class ApiSessionExpired extends ApiException {
  const ApiSessionExpired({
    required super.method,
    required super.path,
    required super.requestId,
    required this.reason,
  });

  final SessionEndReason reason;

  @override
  String get details => 'session ended: ${reason.name}';
}

ApiException apiExceptionFromDio(DioException e) {
  final error = e.error;
  if (error is ApiException) return error;
  final options = e.requestOptions;
  final method = options.method;
  final path = options.uri.path;
  final rid = requestIdOfOptions(options);
  return switch (e.type) {
    DioExceptionType.connectionTimeout => ApiTimeout(
      method: method,
      path: path,
      requestId: rid,
      phase: ApiTimeoutPhase.connect,
      limit: options.connectTimeout,
    ),
    DioExceptionType.sendTimeout => ApiTimeout(
      method: method,
      path: path,
      requestId: rid,
      phase: ApiTimeoutPhase.send,
      limit: options.sendTimeout,
    ),
    DioExceptionType.receiveTimeout ||
    DioExceptionType.transformTimeout => ApiTimeout(
      method: method,
      path: path,
      requestId: rid,
      phase: ApiTimeoutPhase.receive,
      limit: options.receiveTimeout,
    ),
    DioExceptionType.badCertificate => ApiNetworkFailure(
      method: method,
      path: path,
      requestId: rid,
      problem: ApiNetworkProblem.badCertificate,
      cause: error,
    ),
    DioExceptionType.connectionError => ApiNetworkFailure(
      method: method,
      path: path,
      requestId: rid,
      problem: ApiNetworkProblem.connection,
      cause: error,
    ),
    DioExceptionType.cancel => ApiNetworkFailure(
      method: method,
      path: path,
      requestId: rid,
      problem: ApiNetworkProblem.cancelled,
    ),
    DioExceptionType.unknown => ApiNetworkFailure(
      method: method,
      path: path,
      requestId: rid,
      problem: error is IOException
          ? ApiNetworkProblem.connection
          : ApiNetworkProblem.unknown,
      cause: error,
    ),
    DioExceptionType.badResponse => _fromResponse(
      method,
      path,
      rid,
      e.response,
    ),
  };
}

ApiException _fromResponse(
  String method,
  String path,
  String? rid,
  Response<dynamic>? response,
) {
  final status = response?.statusCode;
  if (status == null) {
    return ApiBadResponse(
      method: method,
      path: path,
      requestId: rid,
      statusCode: null,
      reason: 'no status code',
    );
  }
  final parsed = _parseError(response?.data);
  if (status >= 500) {
    return ApiServerFailure(
      method: method,
      path: path,
      requestId: rid,
      statusCode: status,
      error: parsed.error,
    );
  }
  final error = parsed.error;
  if (error == null) {
    _log.warning(
      '$method $path $status has no error envelope → bad response: '
      '${parsed.problem} rid=$rid',
    );
    return ApiBadResponse(
      method: method,
      path: path,
      requestId: rid,
      statusCode: status,
      reason: 'no error envelope: ${parsed.problem}',
    );
  }
  return ApiErrorResponse(
    method: method,
    path: path,
    requestId: rid,
    statusCode: status,
    error: error,
  );
}

({ApiError? error, String? problem}) _parseError(Object? data) {
  try {
    final json = data is String ? jsonDecode(data) : data;
    return (error: ApiError.fromJson(json), problem: null);
  } on FormatException catch (e) {
    _log.fine('error body not parsed as ApiError: ${e.message}');
    return (error: null, problem: e.message);
  }
}
