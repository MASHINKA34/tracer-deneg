import 'json.dart';

/// Коды ошибок API (00-spec §9). Кроме них сервер отдаёт коды валидации
/// (`login_too_short`, … — см. `ValidationError`).
enum ApiErrorCode {
  /// Логин занят (регистрация).
  loginTaken('login_taken'),

  /// Неверный логин, пароль или код восстановления.
  badCredentials('bad_credentials'),

  /// Лимит попыток (429, заголовок `Retry-After`).
  tooManyAttempts('too_many_attempts'),

  /// Код приглашения не найден или истёк.
  inviteNotFound('invite_not_found'),

  /// Запрос не разобран: не JSON, нет поля, неверный тип.
  badRequest('bad_request'),

  /// Данные не прошли проверку (без отдельного кода валидации).
  validationFailed('validation_failed'),

  /// Нет или просрочен access-токен — клиент обновляет его и повторяет.
  unauthorized('unauthorized'),

  /// Сессия отозвана или истекла — нужен вход заново.
  sessionExpired('session_expired'),

  /// Не найдено (в том числе чужой бюджет — не раскрываем существование).
  notFound('not_found'),

  /// Действие только для создателя бюджета.
  forbidden('forbidden'),

  conflict('conflict'),

  /// Тело запроса больше 1 МБ.
  payloadTooLarge('payload_too_large'),

  /// Внутренняя ошибка сервера (в ответе есть rid).
  internalError('internal_error');

  const ApiErrorCode(this.code);

  /// Значение `code` в JSON.
  final String code;

  /// Код по строке или `null` для неизвестного (новый код сервера).
  static ApiErrorCode? fromCode(String code) {
    for (final value in values) {
      if (value.code == code) return value;
    }
    return null;
  }
}

/// Ошибка API: `{"error": {"code": "login_taken", "message": "…"}}`.
/// [message] — по-русски для показа, если у клиента нет своего текста.
final class ApiError {
  const ApiError({required this.code, required this.message});

  /// Ошибка с известным кодом.
  ApiError.of(ApiErrorCode code, this.message) : code = code.code;

  /// Разбор тела ответа с ошибкой (обёртка `error` обязательна).
  factory ApiError.fromJson(Object? json) {
    final envelope = JsonReader.of(json, 'ApiError');
    final r = JsonReader.of(envelope.json['error'], 'ApiError.error');
    return ApiError(code: r.string('code'), message: r.string('message'));
  }

  final String code;
  final String message;

  /// Известный код или `null`.
  ApiErrorCode? get knownCode => ApiErrorCode.fromCode(code);

  Map<String, Object?> toJson() => {
    'error': {'code': code, 'message': message},
  };

  @override
  bool operator ==(Object other) =>
      other is ApiError && other.code == code && other.message == message;

  @override
  int get hashCode => Object.hash(code, message);

  @override
  String toString() => 'ApiError($code: $message)';
}
