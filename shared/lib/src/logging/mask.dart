import 'dart:convert';

/// Сколько байт тела запроса/ответа попадает в лог (на уровне debug).
const int logBodyLimitBytes = 2048;

/// Логин для лога: первые 2 символа и `***` (`anna` → `an***`).
/// Короче 3 символов — только `***`, чтобы не раскрыть логин целиком.
String maskLogin(String? login) {
  if (login == null) return '<none>';
  if (login.isEmpty) return '<empty>';
  final runes = login.runes.toList();
  if (runes.length < 3) return '***';
  return '${String.fromCharCodes(runes.take(2))}***';
}

/// Код приглашения для лога — всегда `MLN-****`, сам код не пишем.
String maskInviteCode(String? code) {
  if (code == null) return '<none>';
  if (code.isEmpty) return '<empty>';
  return 'MLN-****';
}

/// Код восстановления для лога — всегда `****-****-****`, сам код не пишем.
String maskRecoveryCode(String? code) {
  if (code == null) return '<none>';
  if (code.isEmpty) return '<empty>';
  return '****-****-****';
}

/// Токен или секрет для лога: только длина, `***(43)`.
String maskToken(String? token) {
  if (token == null) return '<none>';
  if (token.isEmpty) return '<empty>';
  return '***(${token.length})';
}

/// Обрезает тело до [maxBytes] байт UTF-8 (по границе символа) и дописывает
/// полный размер: `{"a":…[truncated, total 15360 bytes]`.
String truncateBody(String body, {int maxBytes = logBodyLimitBytes}) {
  final total = utf8.encode(body).length;
  if (total <= maxBytes) return body;

  var used = 0;
  final kept = StringBuffer();
  for (final rune in body.runes) {
    final size = rune < 0x80
        ? 1
        : rune < 0x800
        ? 2
        : rune < 0x10000
        ? 3
        : 4;
    if (used + size > maxBytes) break;
    used += size;
    kept.writeCharCode(rune);
  }
  return '$kept…[truncated, total $total bytes]';
}
