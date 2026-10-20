import 'package:characters/characters.dart';

import '../holidays/holidays.dart';
import '../money/money.dart';
import '../time/local_date.dart';

/// Ошибки валидации — коды, а не тексты (тексты — в ARB приложения, коды —
/// и в ответах API). Одинаковые правила на клиенте и сервере (00-spec §9).
enum ValidationError {
  loginEmpty('login_empty'),
  loginInvalidChars('login_invalid_chars'),
  loginTooShort('login_too_short'),
  loginTooLong('login_too_long'),
  passwordEmpty('password_empty'),
  passwordTooShort('password_too_short'),
  passwordTooLong('password_too_long'),
  nameEmpty('name_empty'),
  nameTooLong('name_too_long'),
  categoryNameEmpty('category_name_empty'),
  categoryNameTooLong('category_name_too_long'),
  budgetNameEmpty('budget_name_empty'),
  budgetNameTooLong('budget_name_too_long'),
  recurringTitleEmpty('recurring_title_empty'),
  recurringTitleTooLong('recurring_title_too_long'),
  commentTooLong('comment_too_long'),
  amountEmpty('amount_empty'),
  amountNegative('amount_negative'),
  amountTooLarge('amount_too_large'),
  dayOfMonthInvalid('day_of_month_invalid'),
  emojiEmpty('emoji_empty'),
  emojiInvalid('emoji_invalid'),
  birthdayInvalid('birthday_invalid'),
  holidayKeyUnknown('holiday_key_unknown');

  const ValidationError(this.code);

  /// Код для API и ARB: `login_too_short`.
  final String code;

  /// Ошибка по коду или `null`.
  static ValidationError? fromCode(String code) {
    for (final value in values) {
      if (value.code == code) return value;
    }
    return null;
  }
}

const int loginMinLength = 3;
const int loginMaxLength = 32;
const int passwordMinLength = 6;
const int passwordMaxLength = 128;
const int displayNameMaxLength = 40;
const int categoryNameMaxLength = 24;
const int budgetNameMaxLength = 30;
const int recurringTitleMaxLength = 40;
const int commentMaxLength = 100;

final RegExp _loginChars = RegExp(r'^[a-z0-9_.]+$');
final RegExp _emojiSymbol = RegExp(r'[\p{So}⃣]', unicode: true);

/// Длина текста в видимых символах (графемах) — как счётчик `maxLength`
/// в поле Flutter: 👨‍👩‍👧 — один символ.
int textLength(String text) => text.characters.length;

/// Текст поля перед проверкой и сохранением: без пробелов по краям.
/// Пароль так не обрабатывается никогда.
String normalizeText(String text) => text.trim();

/// Логин для проверки и хранения: без пробелов по краям, в нижнем регистре.
String normalizeLogin(String login) => login.trim().toLowerCase();

/// Логин: 3–32 символа `[a-z0-9_.]` после [normalizeLogin] (заглавные
/// допустимы — станут строчными).
ValidationError? validateLogin(String login) {
  final value = normalizeLogin(login);
  if (value.isEmpty) return ValidationError.loginEmpty;
  if (!_loginChars.hasMatch(value)) return ValidationError.loginInvalidChars;
  if (value.length < loginMinLength) return ValidationError.loginTooShort;
  if (value.length > loginMaxLength) return ValidationError.loginTooLong;
  return null;
}

/// Пароль: 6–128 символов как есть (пробелы не обрезаются).
ValidationError? validatePassword(String password) {
  final length = textLength(password);
  if (length == 0) return ValidationError.passwordEmpty;
  if (length < passwordMinLength) return ValidationError.passwordTooShort;
  if (length > passwordMaxLength) return ValidationError.passwordTooLong;
  return null;
}

ValidationError? _validateRequired(
  String text,
  int maxLength,
  ValidationError empty,
  ValidationError tooLong,
) {
  final length = textLength(normalizeText(text));
  if (length == 0) return empty;
  if (length > maxLength) return tooLong;
  return null;
}

/// Имя пользователя: 1–40 символов.
ValidationError? validateDisplayName(String name) => _validateRequired(
  name,
  displayNameMaxLength,
  ValidationError.nameEmpty,
  ValidationError.nameTooLong,
);

/// Название категории: 1–24 символа.
ValidationError? validateCategoryName(String name) => _validateRequired(
  name,
  categoryNameMaxLength,
  ValidationError.categoryNameEmpty,
  ValidationError.categoryNameTooLong,
);

/// Название бюджета: 1–30 символов.
ValidationError? validateBudgetName(String name) => _validateRequired(
  name,
  budgetNameMaxLength,
  ValidationError.budgetNameEmpty,
  ValidationError.budgetNameTooLong,
);

/// Название регулярной траты: 1–40 символов.
ValidationError? validateRecurringTitle(String title) => _validateRequired(
  title,
  recurringTitleMaxLength,
  ValidationError.recurringTitleEmpty,
  ValidationError.recurringTitleTooLong,
);

/// Комментарий: 0–100 символов.
ValidationError? validateComment(String comment) =>
    textLength(normalizeText(comment)) > commentMaxLength
    ? ValidationError.commentTooLong
    : null;

/// Сумма траты или регулярной: 0,01–10 000 000,00 ₽.
ValidationError? validateAmount(Money amount) {
  if (amount.kopecks == 0) return ValidationError.amountEmpty;
  if (amount.kopecks < 0) return ValidationError.amountNegative;
  if (amount.kopecks > maxExpenseKopecks) return ValidationError.amountTooLarge;
  return null;
}

/// День месяца регулярной траты: 1–31.
ValidationError? validateDayOfMonth(int day) =>
    day < 1 || day > 31 ? ValidationError.dayOfMonthInvalid : null;

/// Эмодзи категории или бюджета: ровно один видимый символ, и это значок
/// (символ Unicode категории So или keycap), а не буква, цифра или пробел.
/// Полностью «это именно эмодзи» без таблиц Unicode не проверить: проходят
/// и редкие значки вроде «©».
ValidationError? validateEmoji(String emoji) {
  final value = normalizeText(emoji);
  if (value.isEmpty) return ValidationError.emojiEmpty;
  if (textLength(value) != 1 || !_emojiSymbol.hasMatch(value)) {
    return ValidationError.emojiInvalid;
  }
  return null;
}

/// Дата рождения: оба поля `null` (нет даты) или существующий день
/// (29 февраля допустимо).
ValidationError? validateBirthday(int? month, int? day) {
  if (month == null && day == null) return null;
  if (month == null || day == null) return ValidationError.birthdayInvalid;
  if (month < 1 || month > 12) return ValidationError.birthdayInvalid;
  if (day < 1 || day > daysInMonth(2000, month)) {
    return ValidationError.birthdayInvalid;
  }
  return null;
}

/// Ключи выключенных праздников: только известные (`newyear`, …).
ValidationError? validateHolidayKeys(Iterable<String> keys) {
  for (final key in keys) {
    if (HolidayKey.fromKey(key) == null) {
      return ValidationError.holidayKeyUnknown;
    }
  }
  return null;
}
