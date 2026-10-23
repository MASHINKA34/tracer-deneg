import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import 'api_exception.dart';
import 'api_log_interceptor.dart';
import 'request_id_interceptor.dart';
import 'token_store.dart';

final _log = Logger('api');

const String apiAuthKey = 'milionchik.auth';

const String apiRetriedKey = 'milionchik.retried';

const String refreshPath = '/auth/refresh';

final class SessionExpired {
  const SessionExpired({
    required this.reason,
    required this.method,
    required this.path,
    required this.requestId,
  });

  final SessionEndReason reason;
  final String method;
  final String path;
  final String? requestId;

  @override
  String toString() =>
      'SessionExpired(${reason.name} on $method $path rid=$requestId)';
}

sealed class _RefreshOutcome {
  const _RefreshOutcome();
}

final class _Refreshed extends _RefreshOutcome {
  const _Refreshed();
}

final class _Ended extends _RefreshOutcome {
  const _Ended(this.reason);

  final SessionEndReason reason;
}

final class _Failed extends _RefreshOutcome {
  const _Failed(this.error);

  final DioException error;
}

class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this._tokens,
    required this._dio,
    required this._newRequestId,
    required this._onSessionExpired,
  });

  final TokenStore _tokens;
  final Dio _dio;
  final String Function() _newRequestId;
  final void Function(SessionExpired event) _onSessionExpired;

  Future<_RefreshOutcome>? _refreshing;
  String? _endedRefreshToken;

  static bool needsAuth(RequestOptions options) =>
      options.extra[apiAuthKey] != false;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (!needsAuth(options)) {
      handler.next(options);
      return;
    }
    final method = options.method;
    final path = options.uri.path;
    final rid = requestIdOfOptions(options);
    try {
      final pending = _refreshing;
      if (pending != null) {
        _log.fine(
          '$method $path waits for session refresh in progress rid=$rid',
        );
        await pending;
      }
      final tokens = await _tokens.readTokens();
      if (tokens == null) {
        _log.info(
          '$method $path not sent: no session tokens → sign-in needed rid=$rid',
        );
        handler.reject(_sessionError(options, SessionEndReason.noSession));
        return;
      }
      if (tokens.refreshToken == _endedRefreshToken) {
        _log.info(
          '$method $path not sent: session already ended → re-login '
          'rid=$rid',
        );
        handler.reject(_sessionError(options, SessionEndReason.endedEarlier));
        return;
      }
      options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
      handler.next(options);
    } catch (e, st) {
      _log.warning(
        '$method $path not sent: token store read failed: '
        '${describeError(e)} rid=$rid',
        e,
        st,
      );
      handler.reject(
        DioException(requestOptions: options, error: e, stackTrace: st),
      );
    }
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    final response = err.response;
    if (response?.statusCode != 401 || !needsAuth(options)) {
      handler.next(err);
      return;
    }
    final method = options.method;
    final path = options.uri.path;
    final rid = requestIdOfOptions(options);
    final code = errorCodeOf(response?.data);

    if (code == ApiErrorCode.badCredentials.code) {
      _log.info(
        '$method $path 401 bad_credentials → wrong password, not a token '
        'problem, no refresh rid=$rid',
      );
      handler.next(err);
      return;
    }

    if (code == ApiErrorCode.sessionExpired.code) {
      _log.info(
        '$method $path 401 session_expired → session ended on server, '
        're-login rid=$rid',
      );
      await _sessionEnded(options, SessionEndReason.sessionRejected);
      handler.reject(_sessionError(options, SessionEndReason.sessionRejected));
      return;
    }

    if (options.extra[apiRetriedKey] == true) {
      _log.warning(
        '$method $path still 401 ${code ?? 'without code'} after session '
        'refresh → giving up, one retry only rid=$rid',
      );
      handler.next(err);
      return;
    }

    _log.info(
      'access token rejected: $method $path 401 ${code ?? 'without code'} '
      '→ refreshing session rid=$rid',
    );
    final outcome = await _refreshOnce(options);
    switch (outcome) {
      case _Refreshed():
        await _retry(options, handler);
      case _Ended(:final reason):
        handler.reject(_sessionError(options, reason));
      case _Failed(:final error):
        handler.reject(
          DioException(
            requestOptions: options,
            response: error.response,
            type: error.type,
            error: error.error,
            stackTrace: error.stackTrace,
            message: error.message,
          ),
        );
    }
  }

  Future<void> _retry(
    RequestOptions options,
    ErrorInterceptorHandler handler,
  ) async {
    options.extra[apiRetriedKey] = true;
    options.extra[apiAttemptKey] = 2;
    _log.info(
      'retrying ${options.method} ${options.uri.path} with refreshed token '
      'rid=${requestIdOfOptions(options)}',
    );
    try {
      final response = await _dio.fetch<dynamic>(options);
      handler.resolve(response);
    } on DioException catch (e) {
      _log.fine(
        'retry of ${options.method} ${options.uri.path} failed '
        '(${e.type.name}, logged above) rid=${requestIdOfOptions(options)}',
      );
      handler.next(e);
    }
  }

  Future<_RefreshOutcome> _refreshOnce(RequestOptions options) async {
    final rid = requestIdOfOptions(options);
    final sent = _bearerOf(options);
    var pending = _refreshing;
    if (pending == null) {
      final AuthTokens? current;
      try {
        current = await _tokens.readTokens();
      } catch (e, st) {
        _log.warning(
          'session refresh skipped: token store read failed: '
          '${describeError(e)} rid=$rid',
          e,
          st,
        );
        return _Failed(
          DioException(requestOptions: options, error: e, stackTrace: st),
        );
      }
      pending = _refreshing;
      if (pending == null) {
        if (current == null) {
          _log.info('session refresh impossible: no tokens → sign-in rid=$rid');
          return const _Ended(SessionEndReason.noSession);
        }
        if (current.refreshToken == _endedRefreshToken) {
          _log.info('session refresh skipped: session already ended rid=$rid');
          return const _Ended(SessionEndReason.endedEarlier);
        }
        if (sent != null && sent != current.accessToken) {
          _log.info(
            'access token already refreshed by another request → retry '
            'without refresh rid=$rid',
          );
          return const _Refreshed();
        }
        final started = _refresh(current, options);
        _refreshing = started;
        try {
          return await started;
        } finally {
          if (identical(_refreshing, started)) _refreshing = null;
        }
      }
    }
    _log.info('session refresh already in progress → waiting rid=$rid');
    return pending;
  }

  Future<_RefreshOutcome> _refresh(
    AuthTokens current,
    RequestOptions trigger,
  ) async {
    final rid = _newRequestId();
    final triggerRid = requestIdOfOptions(trigger);
    final sw = Stopwatch()..start();
    _log.info('refreshing session rid=$rid trigger=$triggerRid');
    final Response<String> response;
    try {
      response = await _dio.post<String>(
        refreshPath,
        data: {'refreshToken': current.refreshToken},
        options: Options(extra: {apiAuthKey: false, apiRequestIdKey: rid}),
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401) {
        _log.info(
          'refresh token expired → re-login (401 '
          '${errorCodeOf(e.response?.data) ?? 'without code'}) '
          'in ${sw.elapsedMilliseconds}ms rid=$rid trigger=$triggerRid',
        );
        _markEnded(
          current.refreshToken,
          SessionExpired(
            reason: SessionEndReason.refreshRejected,
            method: trigger.method,
            path: trigger.uri.path,
            requestId: rid,
          ),
        );
        return const _Ended(SessionEndReason.refreshRejected);
      }
      _log.warning(
        'session refresh failed in ${sw.elapsedMilliseconds}ms: '
        '${status == null ? describeDioFailure(e) : 'status $status'} '
        '→ session kept, request fails rid=$rid trigger=$triggerRid',
      );
      return _Failed(e);
    }

    final AuthTokens fresh;
    try {
      fresh = _parseTokens(response.data);
    } on FormatException catch (e, st) {
      _log.warning(
        'session refresh answered ${response.statusCode} without token pair '
        '(${e.message}) → session kept, request fails rid=$rid',
      );
      return _Failed(
        DioException(
          requestOptions: response.requestOptions,
          error: ApiBadResponse(
            method: 'POST',
            path: response.requestOptions.uri.path,
            requestId: rid,
            statusCode: response.statusCode,
            reason: 'refresh: expected {accessToken, refreshToken}',
          ),
          stackTrace: st,
        ),
      );
    }

    try {
      await _tokens.saveTokens(fresh);
    } catch (e, st) {
      _log.severe(
        'session refreshed but new tokens not saved: ${describeError(e)} '
        '→ request fails rid=$rid',
        e,
        st,
      );
      return _Failed(
        DioException(
          requestOptions: response.requestOptions,
          error: e,
          stackTrace: st,
        ),
      );
    }
    _log.info(
      'session refreshed in ${sw.elapsedMilliseconds}ms → retrying '
      'rid=$rid trigger=$triggerRid',
    );
    return const _Refreshed();
  }

  Future<void> _sessionEnded(
    RequestOptions options,
    SessionEndReason reason,
  ) async {
    String? refreshToken;
    try {
      refreshToken = (await _tokens.readTokens())?.refreshToken;
    } catch (e, st) {
      _log.warning(
        'token store read failed while ending session: ${describeError(e)} '
        '→ reporting session end anyway',
        e,
        st,
      );
    }
    _markEnded(
      refreshToken,
      SessionExpired(
        reason: reason,
        method: options.method,
        path: options.uri.path,
        requestId: requestIdOfOptions(options),
      ),
    );
  }

  void _markEnded(String? refreshToken, SessionExpired event) {
    if (refreshToken != null && refreshToken == _endedRefreshToken) {
      _log.fine('session end already reported, skipping $event');
      return;
    }
    _endedRefreshToken = refreshToken;
    _onSessionExpired(event);
  }

  DioException _sessionError(RequestOptions options, SessionEndReason reason) =>
      DioException(
        requestOptions: options,
        error: ApiSessionExpired(
          method: options.method,
          path: options.uri.path,
          requestId: requestIdOfOptions(options),
          reason: reason,
        ),
      );
}

String? _bearerOf(RequestOptions options) {
  final header = options.headers['Authorization'];
  if (header is! String || !header.startsWith('Bearer ')) return null;
  return header.substring('Bearer '.length);
}

AuthTokens _parseTokens(String? body) {
  if (body == null || body.isEmpty) {
    throw const FormatException('empty body');
  }
  final json = jsonDecode(body);
  final reader = JsonReader.of(json, 'refresh');
  return AuthTokens(
    accessToken: reader.string('accessToken'),
    refreshToken: reader.string('refreshToken'),
  );
}
