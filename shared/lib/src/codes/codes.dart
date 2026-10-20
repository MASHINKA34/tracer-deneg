import 'dart:math';

/// Алфавит Crockford Base32: без I, L, O, U — их не спутать с 1 и 0.
const String crockfordAlphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/// Длина кода восстановления без дефисов.
const int recoveryCodeLength = 12;

/// Длина кода приглашения после `MLN-`.
const int inviteCodeLength = 4;

/// Префикс кода приглашения.
const String inviteCodePrefix = 'MLN';

final RegExp _separators = RegExp(r'[\s\-]');

/// Символы ввода как в Crockford: регистр не важен, O → 0, I и L → 1.
/// Символ не из алфавита (в том числе U) — `null`.
String? _decodeCrockford(String text) {
  final buffer = StringBuffer();
  for (final char in text.toUpperCase().split('')) {
    final mapped = switch (char) {
      'O' => '0',
      'I' || 'L' => '1',
      _ => char,
    };
    if (!crockfordAlphabet.contains(mapped)) return null;
    buffer.write(mapped);
  }
  return buffer.toString();
}

String _randomCode(Random random, int length) {
  final buffer = StringBuffer();
  for (var i = 0; i < length; i++) {
    buffer.write(crockfordAlphabet[random.nextInt(crockfordAlphabet.length)]);
  }
  return buffer.toString();
}

/// Новый код восстановления `XXXX-XXXX-XXXX` (12 символов Crockford Base32,
/// 60 бит). [random] на сервере — `Random.secure()`.
String generateRecoveryCode(Random random) =>
    formatRecoveryCode(_randomCode(random, recoveryCodeLength));

/// Код восстановления из ввода пользователя в каноническом виде — 12 символов
/// без дефисов (его хеширует сервер). Регистр, дефисы и пробелы не важны,
/// O → 0, I/L → 1. Неверный код — `null`.
String? normalizeRecoveryCode(String input) {
  final decoded = _decodeCrockford(input.replaceAll(_separators, ''));
  if (decoded == null || decoded.length != recoveryCodeLength) return null;
  return decoded;
}

/// Показ кода группами: `ABCD-EFGH-JKMN`. [code] — 12 символов в любом
/// принимаемом виде; неверный — [FormatException].
String formatRecoveryCode(String code) {
  final normalized = normalizeRecoveryCode(code);
  if (normalized == null) {
    throw const FormatException('Invalid recovery code');
  }
  return '${normalized.substring(0, 4)}-${normalized.substring(4, 8)}-'
      '${normalized.substring(8)}';
}

/// Новый код приглашения `MLN-XXXX`.
String generateInviteCode(Random random) =>
    '$inviteCodePrefix-${_randomCode(random, inviteCodeLength)}';

/// Код приглашения из ввода в каноническом виде `MLN-XXXX` (его хеширует
/// сервер). Префикс `MLN` можно не вводить, регистр, дефисы и пробелы
/// не важны, O → 0, I/L → 1. Неверный код — `null`.
String? normalizeInviteCode(String input) {
  var compact = input.replaceAll(_separators, '').toUpperCase();
  if (compact.length == inviteCodePrefix.length + inviteCodeLength &&
      compact.startsWith(inviteCodePrefix)) {
    compact = compact.substring(inviteCodePrefix.length);
  }
  final decoded = _decodeCrockford(compact);
  if (decoded == null || decoded.length != inviteCodeLength) return null;
  return '$inviteCodePrefix-$decoded';
}
