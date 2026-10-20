import 'package:shared/shared.dart';
import 'package:test/test.dart';

/// Семья — один видимый символ из 5 кодовых точек.
const family = '👨‍👩‍👧';

void main() {
  group('ValidationError', () {
    test('коды уникальны и в snake_case', () {
      final codes = ValidationError.values.map((e) => e.code).toList();
      expect(codes.toSet(), hasLength(codes.length));
      for (final code in codes) {
        expect(code, matches(RegExp(r'^[a-z]+(_[a-z]+)*$')));
      }
      expect(
        ValidationError.fromCode('login_too_short'),
        ValidationError.loginTooShort,
      );
      expect(ValidationError.fromCode('nope'), isNull);
    });
  });

  group('textLength', () {
    test('видимые символы, а не кодовые точки', () {
      expect(family.runes.length, 5);
      expect(textLength(family), 1);
      expect(textLength('🏋️'), 1);
      expect(textLength('Аня'), 3);
    });
  });

  group('логин', () {
    test('3–32 символа [a-z0-9_.]', () {
      expect(validateLogin('abc'), isNull);
      expect(validateLogin('a.b_c9'), isNull);
      expect(validateLogin('a' * 32), isNull);
      expect(validateLogin('ab'), ValidationError.loginTooShort);
      expect(validateLogin('a' * 33), ValidationError.loginTooLong);
    });

    test('пусто и недопустимые символы', () {
      expect(validateLogin(''), ValidationError.loginEmpty);
      expect(validateLogin('   '), ValidationError.loginEmpty);
      expect(validateLogin('ан'), ValidationError.loginInvalidChars);
      expect(validateLogin('anna smith'), ValidationError.loginInvalidChars);
      expect(validateLogin('anna-1'), ValidationError.loginInvalidChars);
    });

    test('заглавные и пробелы по краям — молча', () {
      expect(validateLogin('  Anna '), isNull);
      expect(normalizeLogin('  Anna.K '), 'anna.k');
    });
  });

  group('пароль', () {
    test('6–128 символов, не обрезается', () {
      expect(validatePassword(''), ValidationError.passwordEmpty);
      expect(validatePassword('12345'), ValidationError.passwordTooShort);
      expect(validatePassword('123456'), isNull);
      expect(validatePassword('  1234'), isNull);
      expect(validatePassword('x' * 128), isNull);
      expect(validatePassword('x' * 129), ValidationError.passwordTooLong);
      expect(validatePassword(family * 6), isNull);
      expect(validatePassword(family * 5), ValidationError.passwordTooShort);
    });
  });

  group('тексты с лимитами', () {
    test('имя: 1–40', () {
      expect(validateDisplayName(''), ValidationError.nameEmpty);
      expect(validateDisplayName('   '), ValidationError.nameEmpty);
      expect(validateDisplayName(' Аня '), isNull);
      expect(validateDisplayName('я' * 40), isNull);
      expect(validateDisplayName('я' * 41), ValidationError.nameTooLong);
      expect(validateDisplayName(family * 40), isNull);
      expect(validateDisplayName(family * 41), ValidationError.nameTooLong);
      expect(validateDisplayName(' ${'я' * 40} '), isNull);
    });

    test('категория: 1–24', () {
      expect(validateCategoryName(''), ValidationError.categoryNameEmpty);
      expect(validateCategoryName('к' * 24), isNull);
      expect(
        validateCategoryName('к' * 25),
        ValidationError.categoryNameTooLong,
      );
    });

    test('бюджет: 1–30', () {
      expect(validateBudgetName(' '), ValidationError.budgetNameEmpty);
      expect(validateBudgetName('б' * 30), isNull);
      expect(validateBudgetName('б' * 31), ValidationError.budgetNameTooLong);
    });

    test('регулярная: 1–40', () {
      expect(validateRecurringTitle(''), ValidationError.recurringTitleEmpty);
      expect(validateRecurringTitle('р' * 40), isNull);
      expect(
        validateRecurringTitle('р' * 41),
        ValidationError.recurringTitleTooLong,
      );
    });

    test('комментарий: 0–100', () {
      expect(validateComment(''), isNull);
      expect(validateComment('   '), isNull);
      expect(validateComment('к' * 100), isNull);
      expect(validateComment('к' * 101), ValidationError.commentTooLong);
      expect(validateComment('${'к' * 100}   '), isNull);
    });

    test('normalizeText обрезает пробелы по краям', () {
      expect(normalizeText('  Кофе с собой \n'), 'Кофе с собой');
    });
  });

  group('сумма и день', () {
    test('сумма 0,01–10 000 000,00 ₽', () {
      expect(validateAmount(Money.zero), ValidationError.amountEmpty);
      expect(validateAmount(const Money(-1)), ValidationError.amountNegative);
      expect(validateAmount(const Money(1)), isNull);
      expect(validateAmount(const Money(maxExpenseKopecks)), isNull);
      expect(
        validateAmount(const Money(maxExpenseKopecks + 1)),
        ValidationError.amountTooLarge,
      );
    });

    test('день месяца 1–31', () {
      expect(validateDayOfMonth(0), ValidationError.dayOfMonthInvalid);
      expect(validateDayOfMonth(1), isNull);
      expect(validateDayOfMonth(31), isNull);
      expect(validateDayOfMonth(32), ValidationError.dayOfMonthInvalid);
    });
  });

  group('эмодзи', () {
    test('ровно один значок', () {
      for (final emoji in ['🛒', '☕', '🏋️', family, '1️⃣', '🇷🇺', ' 🏠 ']) {
        expect(validateEmoji(emoji), isNull, reason: emoji);
      }
    });

    test('пусто, буквы, цифры, несколько символов', () {
      expect(validateEmoji(''), ValidationError.emojiEmpty);
      expect(validateEmoji('  '), ValidationError.emojiEmpty);
      for (final text in ['a', 'Я', '1', '₽', '+', '🛒🛒', 'ab']) {
        expect(validateEmoji(text), ValidationError.emojiInvalid, reason: text);
      }
    });
  });

  group('день рождения и праздники', () {
    test('оба поля или ни одного, существующий день', () {
      expect(validateBirthday(null, null), isNull);
      expect(validateBirthday(2, 29), isNull);
      expect(validateBirthday(12, 31), isNull);
      expect(validateBirthday(2, 30), ValidationError.birthdayInvalid);
      expect(validateBirthday(4, 31), ValidationError.birthdayInvalid);
      expect(validateBirthday(13, 1), ValidationError.birthdayInvalid);
      expect(validateBirthday(0, 5), ValidationError.birthdayInvalid);
      expect(validateBirthday(1, 0), ValidationError.birthdayInvalid);
      expect(validateBirthday(1, null), ValidationError.birthdayInvalid);
      expect(validateBirthday(null, 1), ValidationError.birthdayInvalid);
    });

    test('ключи праздников — только известные', () {
      expect(validateHolidayKeys([]), isNull);
      expect(validateHolidayKeys(['newyear', 'birthday']), isNull);
      expect(
        validateHolidayKeys(['newyear', 'xmas']),
        ValidationError.holidayKeyUnknown,
      );
    });
  });
}
