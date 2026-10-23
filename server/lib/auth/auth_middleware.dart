import 'package:logging/logging.dart';
import 'package:shared/shared.dart';
import 'package:shelf/shelf.dart';

import '../http/json.dart';
import 'auth_service.dart';

final _log = Logger('auth');

const authContextKey = 'milionchik.auth';

class AuthContext {
  const AuthContext({
    required this.userId,
    required this.sessionId,
    required this.expiresAt,
  });

  final String userId;
  final String sessionId;
  final DateTime expiresAt;
}

AuthContext authContextOf(Request request) {
  final value = request.context[authContextKey];
  if (value is AuthContext) return value;
  throw StateError(
    'no AuthContext for ${request.method} ${request.requestedUri.path}: '
    'route is not behind authMiddleware',
  );
}

final RegExp _bearer = RegExp(r'^Bearer +([^\s]+) *$', caseSensitive: false);

Middleware authMiddleware(AuthService auth) =>
    (inner) => (request) async {
      final sw = Stopwatch()..start();
      final header = request.headers['authorization'];
      final token = header == null ? null : _bearer.firstMatch(header)?[1];
      if (token == null) {
        return _reject(
          request,
          header == null ? 'missing_token' : 'malformed_header',
          sw,
        );
      }

      final check = await auth.authenticate(token);
      final rejection = check.rejection;
      if (rejection != null) {
        return _reject(
          request,
          rejection,
          sw,
          userId: check.userId,
          sessionId: check.sessionId,
        );
      }

      final context = AuthContext(
        userId: check.userId!,
        sessionId: check.sessionId!,
        expiresAt: check.expiresAt!,
      );
      _log.fine(
        'authorized ${request.method} ${request.requestedUri.path} '
        'userId=${context.userId} sessionId=${context.sessionId} '
        'in ${sw.elapsedMilliseconds}ms',
      );
      return inner(request.change(context: {authContextKey: context}));
    };

const authSkipContextKey = 'milionchik.auth.skip';

AuthContext? optionalAuthContextOf(Request request) {
  final value = request.context[authContextKey];
  return value is AuthContext ? value : null;
}

String? authSkipReasonOf(Request request) {
  final value = request.context[authSkipContextKey];
  return value is String ? value : null;
}

Middleware optionalAuthMiddleware(AuthService auth) =>
    (inner) => (request) async {
      final sw = Stopwatch()..start();
      final header = request.headers['authorization'];
      if (header == null) {
        _log.fine(
          'anonymous ${request.method} ${request.requestedUri.path}: '
          'no authorization header',
        );
        return inner(request.change(context: {authSkipContextKey: 'none'}));
      }
      final token = _bearer.firstMatch(header)?[1];
      final check = token == null ? null : await auth.authenticate(token);
      final rejection = check == null ? 'malformed_header' : check.rejection;
      if (rejection != null) {
        _log.info(
          'optional auth skipped ${request.method} '
          '${request.requestedUri.path} '
          '${formatContext({'reason': rejection, 'userId': check?.userId, 'sessionId': check?.sessionId})} '
          'in ${sw.elapsedMilliseconds}ms → continuing anonymously',
        );
        return inner(request.change(context: {authSkipContextKey: rejection}));
      }
      final context = AuthContext(
        userId: check!.userId!,
        sessionId: check.sessionId!,
        expiresAt: check.expiresAt!,
      );
      _log.fine(
        'authorized (optional) ${request.method} '
        '${request.requestedUri.path} userId=${context.userId} '
        'sessionId=${context.sessionId} in ${sw.elapsedMilliseconds}ms',
      );
      return inner(request.change(context: {authContextKey: context}));
    };

Response _reject(
  Request request,
  String reason,
  Stopwatch sw, {
  String? userId,
  String? sessionId,
}) {
  _log.info(
    'unauthorized ${request.method} ${request.requestedUri.path} '
    '${formatContext({'reason': reason, 'userId': userId, 'sessionId': sessionId})} '
    'in ${sw.elapsedMilliseconds}ms',
  );
  return errorResponse(
    401,
    ApiErrorCode.unauthorized.code,
    'Нужно войти в аккаунт',
  ).change(headers: {'www-authenticate': 'Bearer'});
}
