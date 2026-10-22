import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:shared/shared.dart';
import 'package:shelf/shelf.dart';

import '../auth/auth_service.dart';
import 'json.dart';

final _log = Logger('auth');

const int maxDeviceNameLength = 100;

Handler registerHandler(AuthService auth) => (Request request) async {
  final body = await _readBody(request, 'register');
  if (body.error != null) return body.error!;
  final fields = body.fields!;
  final login = _string(fields, 'login');
  final displayName = _string(fields, 'displayName');
  final password = _string(fields, 'password');
  final deviceName = _deviceName(fields);
  final missing = [
    if (login == null) 'login',
    if (displayName == null) 'displayName',
    if (password == null) 'password',
    if (deviceName == null) 'deviceName',
  ];
  if (missing.isNotEmpty) return _badFields('register', missing);

  final invalid =
      validateLogin(login!) ??
      validateDisplayName(displayName!) ??
      validatePassword(password!);
  if (invalid != null) {
    _log.info(
      'register rejected reason=${invalid.code} login=${maskLogin(normalizeLogin(login))}',
    );
    return errorResponse(400, invalid.code, _validationMessage(invalid));
  }

  try {
    final registration = await auth.register(
      login: login,
      displayName: displayName!,
      password: password!,
      deviceName: deviceName!,
    );
    final session = registration.session;
    return _noStore(
      jsonResponse(201, {
        'user': session.user.toJson(),
        'accessToken': session.accessToken,
        'refreshToken': session.refreshToken,
        'recoveryCode': registration.recoveryCode,
      }),
    );
  } on AuthFailure catch (e) {
    return _failure(e);
  }
};

Handler loginHandler(AuthService auth) => (Request request) async {
  final body = await _readBody(request, 'login');
  if (body.error != null) return body.error!;
  final fields = body.fields!;
  final login = _string(fields, 'login');
  final password = _string(fields, 'password');
  final deviceName = _deviceName(fields);
  final missing = [
    if (login == null) 'login',
    if (password == null) 'password',
    if (deviceName == null) 'deviceName',
  ];
  if (missing.isNotEmpty) return _badFields('login', missing);

  try {
    final session = await auth.login(
      login: login!,
      password: password!,
      deviceName: deviceName!,
    );
    return _noStore(
      jsonResponse(200, {
        'user': session.user.toJson(),
        'accessToken': session.accessToken,
        'refreshToken': session.refreshToken,
      }),
    );
  } on AuthFailure catch (e) {
    return _failure(e);
  }
};

class _Body {
  const _Body.ok(this.fields) : error = null;
  const _Body.failed(this.error) : fields = null;

  final Map<String, Object?>? fields;
  final Response? error;
}

Future<_Body> _readBody(Request request, String operation) async {
  final Object? decoded;
  try {
    decoded = jsonDecode(await request.readAsString());
  } on FormatException catch (e) {
    _log.info(
      '$operation rejected reason=${ApiErrorCode.badRequest.code} '
      'problem="body is not JSON: ${e.message}"',
    );
    return _Body.failed(
      errorResponse(
        400,
        ApiErrorCode.badRequest.code,
        'Неверный запрос: тело должно быть JSON',
      ),
    );
  }
  if (decoded is! Map<String, Object?>) {
    _log.info(
      '$operation rejected reason=${ApiErrorCode.badRequest.code} '
      'problem="body is ${decoded.runtimeType}, not an object"',
    );
    return _Body.failed(
      errorResponse(
        400,
        ApiErrorCode.badRequest.code,
        'Неверный запрос: тело должно быть JSON-объектом',
      ),
    );
  }
  return _Body.ok(decoded);
}

String? _string(Map<String, Object?> fields, String name) {
  final value = fields[name];
  return value is String ? value : null;
}

String? _deviceName(Map<String, Object?> fields) {
  final value = _string(fields, 'deviceName');
  if (value == null) return null;
  final trimmed = normalizeText(value);
  if (trimmed.isEmpty || textLength(trimmed) > maxDeviceNameLength) {
    return null;
  }
  return trimmed;
}

Response _badFields(String operation, List<String> fields) {
  _log.info(
    '$operation rejected reason=${ApiErrorCode.badRequest.code} '
    'fields=${fields.join(',')}',
  );
  return errorResponse(
    400,
    ApiErrorCode.badRequest.code,
    'Неверный запрос: проверь поля ${fields.join(', ')}',
  );
}

Response _failure(AuthFailure failure) => switch (failure.reason) {
  AuthFailureReason.loginTaken => errorResponse(
    409,
    ApiErrorCode.loginTaken.code,
    'Такой логин уже занят',
  ),
  AuthFailureReason.badCredentials => errorResponse(
    401,
    ApiErrorCode.badCredentials.code,
    'Неверный логин или пароль',
  ),
};

Response _noStore(Response response) =>
    response.change(headers: {'cache-control': 'no-store'});

String _validationMessage(ValidationError error) => switch (error) {
  ValidationError.loginEmpty => 'Введи логин',
  ValidationError.loginInvalidChars =>
    'В логине можно только латинские буквы, цифры, точку и подчёркивание',
  ValidationError.loginTooShort =>
    'Логин слишком короткий: нужно от $loginMinLength символов',
  ValidationError.loginTooLong =>
    'Логин слишком длинный: не больше $loginMaxLength символов',
  ValidationError.passwordEmpty => 'Введи пароль',
  ValidationError.passwordTooShort =>
    'Пароль слишком короткий: нужно от $passwordMinLength символов',
  ValidationError.passwordTooLong =>
    'Пароль слишком длинный: не больше $passwordMaxLength символов',
  ValidationError.nameEmpty => 'Введи имя',
  ValidationError.nameTooLong =>
    'Имя слишком длинное: не больше $displayNameMaxLength символов',
  _ => 'Данные не прошли проверку',
};
