import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:shared/shared.dart';
import 'package:shelf/shelf.dart';

import '../http/json.dart';
import 'sliding_window.dart';
import 'trusted_proxies.dart';

final _log = Logger('limits');

const int loginFailureLimit = 5;
const Duration loginFailureWindow = Duration(minutes: 15);
const int authRequestsPerIpLimit = 30;
const int clientErrorRequestsPerIpLimit = 20;
const Duration ipRequestWindow = Duration(minutes: 1);
const int maxRequestBodyBytes = 1024 * 1024;

const String _authPath = 'api/v1/auth';
const String _clientErrorsPath = 'api/v1/client-errors';

class RequestBodyTooLarge implements Exception {
  RequestBodyTooLarge(this.limit, this.received);

  final int limit;
  final int received;

  @override
  String toString() =>
      'RequestBodyTooLarge: body is over $limit bytes (read $received)';
}

class RequestLimits {
  RequestLimits({
    this.trustedProxies = TrustedProxies.none,
    this.maxBodyBytes = maxRequestBodyBytes,
    DateTime Function()? now,
  }) : loginFailures = SlidingWindowLimiter(
         name: 'login-failures',
         limit: loginFailureLimit,
         window: loginFailureWindow,
         now: now,
       ),
       authRequests = SlidingWindowLimiter(
         name: 'auth-ip',
         limit: authRequestsPerIpLimit,
         window: ipRequestWindow,
         now: now,
       ),
       clientErrorRequests = SlidingWindowLimiter(
         name: 'client-errors-ip',
         limit: clientErrorRequestsPerIpLimit,
         window: ipRequestWindow,
         now: now,
       );

  final TrustedProxies trustedProxies;
  final int maxBodyBytes;
  final SlidingWindowLimiter loginFailures;
  final SlidingWindowLimiter authRequests;
  final SlidingWindowLimiter clientErrorRequests;

  Map<String, Object?> toLogContext() => {
    'loginFailures':
        '$loginFailureLimit/${loginFailureWindow.inMinutes}m per login',
    'auth': '$authRequestsPerIpLimit/${ipRequestWindow.inMinutes}m per IP',
    'clientErrors':
        '$clientErrorRequestsPerIpLimit/${ipRequestWindow.inMinutes}m per IP',
    'maxBodyBytes': maxBodyBytes,
    'trustedProxies': trustedProxies.describe(),
    'store': 'in-memory',
  };

  Middleware bodySizeLimit() =>
      (inner) => (request) async {
        final declared = request.contentLength;
        if (declared != null) {
          if (declared <= maxBodyBytes) return inner(request);
          request.read().listen(null).pause();
          _log.warning(
            'request body too large ${request.method} '
            '${request.requestedUri.path} ip=${clientIp(request, trustedProxies)} '
            'contentLength=$declared limit=$maxBodyBytes → 413 without reading',
          );
          return _payloadTooLarge(maxBodyBytes);
        }
        final body = _LimitedBody(request.read(), maxBodyBytes);
        try {
          final response = await inner(request.change(body: body.stream));
          body.discardUnread(
            onExceeded: (received) => _log.warning(
              'request body too large ${request.method} '
              '${request.requestedUri.path} '
              'ip=${clientIp(request, trustedProxies)} contentLength=none '
              'read=$received limit=$maxBodyBytes → body unread by handler '
              '(status=${response.statusCode}), discarding stopped, '
              'connection closed',
            ),
            onError: (error) => _log.fine(
              'unread request body discard failed ${request.method} '
              '${request.requestedUri.path}: ${describeError(error)}',
            ),
          );
          return response;
        } on RequestBodyTooLarge catch (e) {
          _log.warning(
            'request body too large ${request.method} '
            '${request.requestedUri.path} ip=${clientIp(request, trustedProxies)} '
            'contentLength=none read=${e.received} limit=$maxBodyBytes '
            '→ 413, rest of body not read',
          );
          return _payloadTooLarge(maxBodyBytes);
        }
      };

  Middleware ipRateLimit() =>
      (inner) => (request) {
        final limiter = _ipLimiterFor(request.url.path);
        if (limiter == null) return inner(request);
        final ip = clientIp(request, trustedProxies);
        final wait = limiter.blockedFor(ip);
        if (wait != null) {
          final seconds = retryAfterSeconds(wait);
          _log.warning(
            'ip rate limit hit limiter=${limiter.name} ip=$ip '
            '${request.method} ${request.requestedUri.path} '
            'limit=${limiter.limit}/${limiter.window.inSeconds}s '
            'retryAfter=${seconds}s',
          );
          return _tooMany(
            seconds,
            'Слишком много запросов. Попробуй через ${_waitText(seconds)}',
          );
        }
        limiter.record(ip);
        return inner(request);
      };

  Middleware loginAttempts(String operation) =>
      (inner) => (request) async {
        final bytes = await _collect(request.read());
        final forward = request.change(body: bytes);
        final login = _loginOf(bytes, operation);
        if (login == null) {
          _log.fine('$operation attempts not tracked: no login in body');
          return inner(forward);
        }
        final key = normalizeLogin(login);
        final invalid = validateLogin(key);
        if (invalid != null) {
          _log.fine(
            '$operation attempts not tracked: login format invalid '
            'reason=${invalid.code}',
          );
          return inner(forward);
        }
        final masked = maskLogin(key);

        final wait = loginFailures.blockedFor(key);
        if (wait != null) {
          final seconds = retryAfterSeconds(wait);
          _log.warning(
            'login attempts limit hit operation=$operation login=$masked '
            'failures=${loginFailures.count(key)}/$loginFailureLimit '
            'window=${loginFailureWindow.inMinutes}m retryAfter=${seconds}s',
          );
          return _tooMany(
            seconds,
            'Слишком много неудачных попыток. '
            'Попробуй через ${_waitText(seconds)}',
          );
        }

        final attempt = loginFailures.record(key);
        final Response response;
        try {
          response = await inner(forward);
        } catch (e) {
          loginFailures.forget(key, attempt);
          _log.fine(
            '$operation attempt not counted: handler threw '
            '${e.runtimeType} login=$masked',
          );
          rethrow;
        }

        if (response.statusCode == 200) {
          final cleared = loginFailures.reset(key) - 1;
          if (cleared > 0) {
            _log.fine(
              '$operation ok → failures reset login=$masked cleared=$cleared',
            );
          }
          return response;
        }
        if (response.statusCode != 401) {
          loginFailures.forget(key, attempt);
          _log.fine(
            '$operation attempt not counted: status=${response.statusCode} '
            'login=$masked',
          );
          return response;
        }

        final text = await response.readAsString();
        if (_errorCodeOf(text, operation) != ApiErrorCode.badCredentials.code) {
          loginFailures.forget(key, attempt);
          _log.fine(
            '$operation attempt not counted: 401 without bad_credentials '
            'login=$masked',
          );
          return response.change(body: text);
        }
        final failures = loginFailures.count(key);
        if (failures >= loginFailureLimit) {
          final seconds = retryAfterSeconds(loginFailures.blockedFor(key)!);
          _log.warning(
            'login attempts exhausted operation=$operation login=$masked '
            'failures=$failures/$loginFailureLimit '
            'window=${loginFailureWindow.inMinutes}m → next attempts blocked '
            'for ${seconds}s',
          );
        } else {
          _log.fine(
            '$operation failure recorded login=$masked '
            'failures=$failures/$loginFailureLimit',
          );
        }
        return response.change(body: text);
      };

  SlidingWindowLimiter? _ipLimiterFor(String path) {
    if (path == _authPath || path.startsWith('$_authPath/')) {
      return authRequests;
    }
    if (path == _clientErrorsPath || path.startsWith('$_clientErrorsPath/')) {
      return clientErrorRequests;
    }
    return null;
  }
}

Response _payloadTooLarge(int limit) => errorResponse(
  413,
  ApiErrorCode.payloadTooLarge.code,
  'Слишком большой запрос: не больше ${_sizeText(limit)}',
).change(headers: {'connection': 'close'});

String _sizeText(int bytes) => bytes % (1024 * 1024) == 0
    ? '${bytes ~/ (1024 * 1024)} МБ'
    : '${(bytes + 1023) ~/ 1024} КБ';

class _LimitedBody {
  _LimitedBody(this._source, this.limit) {
    _controller = StreamController<List<int>>(
      sync: true,
      onListen: _forward,
      onPause: () => _subscription?.pause(),
      onResume: () {
        if (!exceeded) _subscription?.resume();
      },
      onCancel: () {
        if (exceeded) return null;
        return _subscription?.cancel();
      },
    );
  }

  final Stream<List<int>> _source;
  final int limit;
  late final StreamController<List<int>> _controller;
  StreamSubscription<List<int>>? _subscription;
  int received = 0;
  bool exceeded = false;

  Stream<List<int>> get stream => _controller.stream;

  void _forward() {
    _subscription = _source.listen(
      (chunk) {
        if (_count(chunk)) {
          _controller.add(chunk);
          return;
        }
        _controller.addError(RequestBodyTooLarge(limit, received));
        unawaited(_controller.close());
      },
      onError: _controller.addError,
      onDone: _controller.close,
    );
  }

  void discardUnread({
    required void Function(int received) onExceeded,
    required void Function(Object error) onError,
  }) {
    if (_subscription != null) return;
    _subscription = _source.listen(
      (chunk) {
        if (!_count(chunk)) onExceeded(received);
      },
      onError: onError,
      cancelOnError: true,
    );
  }

  bool _count(List<int> chunk) {
    received += chunk.length;
    if (received <= limit) return true;
    exceeded = true;
    _subscription?.pause();
    return false;
  }
}

Response _tooMany(int seconds, String message) => errorResponse(
  429,
  ApiErrorCode.tooManyAttempts.code,
  message,
).change(headers: {'retry-after': '$seconds'});

String _waitText(int seconds) =>
    seconds < 60 ? '$seconds с' : '${(seconds + 59) ~/ 60} мин';

Future<List<int>> _collect(Stream<List<int>> stream) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}

String? _loginOf(List<int> bytes, String operation) {
  try {
    final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
    if (decoded is! Map<String, Object?>) return null;
    final login = decoded['login'];
    return login is String ? login : null;
  } on FormatException catch (e) {
    _log.fine(
      '$operation body is not JSON (${e.message}, ${bytes.length} bytes) '
      '→ left to the handler',
    );
    return null;
  }
}

String? _errorCodeOf(String text, String operation) {
  try {
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, Object?>) return null;
    final error = decoded['error'];
    if (error is! Map<String, Object?>) return null;
    final code = error['code'];
    return code is String ? code : null;
  } on FormatException catch (e) {
    _log.warning(
      '$operation 401 response is not JSON (${e.message}) '
      '→ attempt not counted',
    );
    return null;
  }
}
