import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:shared/shared.dart';
import 'package:shelf/shelf.dart';

import '../account/account_service.dart';
import '../auth/auth_middleware.dart';
import '../auth/auth_service.dart';
import '../limits/request_limits.dart';
import '../limits/sliding_window.dart';
import 'json.dart';

final _log = Logger('account');

const Set<String> _profileFields = {
  'displayName',
  'birthdayMonth',
  'birthdayDay',
  'holidaysEnabled',
  'holidaysDisabled',
};

Handler meHandler(AccountService account) => (Request request) async {
  final context = authContextOf(request);
  try {
    final user = await account.me(context.userId);
    return _noStore(jsonResponse(200, user.toJson()));
  } on AuthFailure catch (e) {
    return _failure(e);
  }
};

Handler updateMeHandler(AccountService account) => (Request request) async {
  const operation = 'profile update';
  final userId = authContextOf(request).userId;
  final body = await _readBody(request, operation, userId);
  if (body.error != null) return body.error!;
  final fields = body.fields!;

  final unknown = fields.keys.where((k) => !_profileFields.contains(k)).toList()
    ..sort();
  if (unknown.isNotEmpty) {
    final names = truncateBody(unknown.join(','), maxBytes: 200);
    _log.warning(
      '$operation rejected reason=${ApiErrorCode.badRequest.code} '
      'userId=$userId problem=unknown_fields ${formatContext({'fields': names})}',
    );
    return errorResponse(
      400,
      ApiErrorCode.badRequest.code,
      'Неверный запрос: через /me нельзя менять поля ${unknown.join(', ')}',
    );
  }

  final wrongType = [
    if (fields.containsKey('displayName') && fields['displayName'] is! String)
      'displayName',
    if (!_isOptionalInt(fields['birthdayMonth'])) 'birthdayMonth',
    if (!_isOptionalInt(fields['birthdayDay'])) 'birthdayDay',
    if (fields.containsKey('holidaysEnabled') &&
        fields['holidaysEnabled'] is! bool)
      'holidaysEnabled',
    if (fields.containsKey('holidaysDisabled') &&
        !_isStringList(fields['holidaysDisabled']))
      'holidaysDisabled',
  ];
  if (wrongType.isNotEmpty) return _badFields(operation, userId, wrongType);

  final displayName = fields['displayName'] as String?;
  final hasMonth = fields.containsKey('birthdayMonth');
  final hasDay = fields.containsKey('birthdayDay');
  final month = fields['birthdayMonth'] as int?;
  final day = fields['birthdayDay'] as int?;
  final holidaysDisabled = (fields['holidaysDisabled'] as List<Object?>?)
      ?.cast<String>();

  final nameError = displayName == null
      ? null
      : validateDisplayName(displayName);
  if (nameError != null) {
    return _invalid(operation, userId, nameError, 'displayName');
  }
  if (hasMonth || hasDay) {
    final birthdayError = hasMonth && hasDay
        ? validateBirthday(month, day)
        : ValidationError.birthdayInvalid;
    if (birthdayError != null) {
      return _invalid(
        operation,
        userId,
        birthdayError,
        'birthday',
        detail: hasMonth && hasDay
            ? 'problem=no_such_day'
            : 'problem=month_and_day_required',
      );
    }
  }
  if (holidaysDisabled != null) {
    final holidaysError = validateHolidayKeys(holidaysDisabled);
    if (holidaysError != null) {
      final unknownKeys = holidaysDisabled
          .where((key) => HolidayKey.fromKey(key) == null)
          .toSet()
          .join(',');
      return _invalid(
        operation,
        userId,
        holidaysError,
        'holidaysDisabled',
        detail: formatContext({
          'unknownKeys': truncateBody(unknownKeys, maxBytes: 200),
        }),
      );
    }
  }

  try {
    final change = await account.updateProfile(
      userId,
      ProfileUpdate(
        displayName: displayName,
        birthday: hasMonth || hasDay ? MonthDay.fromParts(month, day) : keep,
        holidaysEnabled: fields['holidaysEnabled'] as bool?,
        holidaysDisabled: holidaysDisabled?.toSet(),
      ),
    );
    return _noStore(jsonResponse(200, change.user.toJson()));
  } on AuthFailure catch (e) {
    return _failure(e);
  }
};

Handler deleteAccountHandler(
  AccountService account,
  RequestLimits limits,
) => (Request request) async {
  const operation = 'account deletion';
  final context = authContextOf(request);
  final userId = context.userId;
  final body = await _readBody(request, operation, userId);
  if (body.error != null) return body.error!;
  final password = body.fields!['password'];
  if (password is! String || password.isEmpty) {
    return _badFields(operation, userId, ['password']);
  }

  final String key;
  try {
    key = normalizeLogin(await account.loginOf(userId));
  } on AuthFailure catch (e) {
    return _failure(e);
  }
  final masked = maskLogin(key);
  final failures = limits.loginFailures;
  final who = 'userId=$userId login=$masked';
  final wait = failures.blockedFor(key);
  if (wait != null) {
    final seconds = retryAfterSeconds(wait);
    _log.warning(
      '$operation blocked: login attempts limit hit $who '
      'failures=${failures.count(key)}/$loginFailureLimit '
      'window=${loginFailureWindow.inMinutes}m retryAfter=${seconds}s',
    );
    return tooManyFailures(seconds);
  }

  final attempt = failures.record(key);
  try {
    await account.deleteAccount(
      userId: userId,
      sessionId: context.sessionId,
      password: password,
    );
  } on AuthFailure catch (e) {
    if (e.reason != AuthFailureReason.badCredentials) {
      failures.forget(key, attempt);
      _log.fine('$operation attempt not counted: reason=${e.reason.code} $who');
      return _failure(e);
    }
    final count = failures.count(key);
    if (count >= loginFailureLimit) {
      _log.warning(
        '$operation attempts exhausted $who '
        'failures=$count/$loginFailureLimit '
        'window=${loginFailureWindow.inMinutes}m → next attempts blocked '
        'for ${retryAfterSeconds(failures.blockedFor(key)!)}s',
      );
    } else {
      _log.fine(
        '$operation failure recorded $who failures=$count/$loginFailureLimit',
      );
    }
    return _failure(e);
  } catch (e) {
    failures.forget(key, attempt);
    _log.fine('$operation attempt not counted: ${e.runtimeType} $who');
    rethrow;
  }
  final cleared = failures.reset(key) - 1;
  if (cleared > 0) {
    _log.fine('$operation ok → failures reset $who cleared=$cleared');
  }
  return Response(204);
};

class _Body {
  const _Body.ok(this.fields) : error = null;
  const _Body.failed(this.error) : fields = null;

  final Map<String, Object?>? fields;
  final Response? error;
}

Future<_Body> _readBody(
  Request request,
  String operation,
  String userId,
) async {
  final Object? decoded;
  try {
    decoded = jsonDecode(await request.readAsString());
  } on FormatException catch (e) {
    _log.warning(
      '$operation rejected reason=${ApiErrorCode.badRequest.code} '
      'userId=$userId problem="body is not JSON: ${e.message}"',
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
    _log.warning(
      '$operation rejected reason=${ApiErrorCode.badRequest.code} '
      'userId=$userId problem="body is ${decoded.runtimeType}, not an object"',
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

bool _isOptionalInt(Object? value) => value == null || value is int;

bool _isStringList(Object? value) =>
    value is List<Object?> && value.every((item) => item is String);

Response _badFields(String operation, String userId, List<String> fields) {
  _log.warning(
    '$operation rejected reason=${ApiErrorCode.badRequest.code} '
    'userId=$userId fields=${fields.join(',')}',
  );
  return errorResponse(
    400,
    ApiErrorCode.badRequest.code,
    'Неверный запрос: проверь поля ${fields.join(', ')}',
  );
}

Response _invalid(
  String operation,
  String userId,
  ValidationError error,
  String field, {
  String? detail,
}) {
  _log.warning(
    '$operation rejected reason=${error.code} userId=$userId field=$field'
    '${detail == null ? '' : ' $detail'}',
  );
  return errorResponse(400, error.code, _validationMessage(error));
}

Response _failure(
  AuthFailure failure, {
  String badCredentialsMessage = 'Неверный пароль',
}) => switch (failure.reason) {
  AuthFailureReason.badCredentials => errorResponse(
    401,
    ApiErrorCode.badCredentials.code,
    badCredentialsMessage,
  ),
  _ => errorResponse(
    401,
    ApiErrorCode.sessionExpired.code,
    'Сессия закончилась, войди снова',
  ),
};

Response _noStore(Response response) =>
    response.change(headers: {'cache-control': 'no-store'});

String _validationMessage(ValidationError error) => switch (error) {
  ValidationError.nameEmpty => 'Введи имя',
  ValidationError.nameTooLong =>
    'Имя слишком длинное: не больше $displayNameMaxLength символов',
  ValidationError.birthdayInvalid =>
    'Такой даты нет: укажи и день, и месяц существующей даты',
  ValidationError.holidayKeyUnknown => 'Неизвестный праздник в настройках',
  _ => 'Данные не прошли проверку',
};
