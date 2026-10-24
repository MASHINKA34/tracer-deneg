import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/features/budgets/invite_code_input.dart';
import 'package:milionchik/features/budgets/join_budget_screen.dart';
import 'package:shared/shared.dart';

void main() {
  group('formatInviteCodeInput', () {
    for (final (input, shown) in const [
      ('', ''),
      ('   ', ''),
      ('m', 'M'),
      ('ml', 'ML'),
      ('mln', 'MLN'),
      ('MLN-', 'MLN'),
      ('mln -', 'MLN'),
      ('4', 'MLN-4'),
      ('48k2', 'MLN-48K2'),
      ('mln48k2', 'MLN-48K2'),
      ('MLN 48K2', 'MLN-48K2'),
      (' mln-48k2 ', 'MLN-48K2'),
      ('MLN-48K29', 'MLN-48K2'),
      ('48K2ZZ', 'MLN-48K2'),
      ('mln-o1il', 'MLN-0111'),
      ('MLN-4U8!K2', 'MLN-48K2'),
      ('MN', 'MLN-MN'),
      ('Вступай в «Семью»: MLN-48K2, код на 24 часа', 'MLN-48K2'),
      ('код 48k2', 'MLN-48K2'),
    ]) {
      test('«$input» → «$shown»', () {
        expect(formatInviteCodeInput(input), shown);
      });
    }

    test('полный код после автоформата принимает normalizeInviteCode', () {
      for (final input in const ['mln48k2', '48k2', 'MLN 48K2', 'mln-o1il']) {
        final shown = formatInviteCodeInput(input);
        expect(normalizeInviteCode(shown), shown, reason: input);
      }
    });

    test('сгенерированный сервером код не меняется', () {
      for (final code in const ['MLN-0000', 'MLN-ZZZZ', 'MLN-M1N2']) {
        expect(formatInviteCodeInput(code), code);
        expect(formatInviteCodeInput(code.toLowerCase()), code);
      }
    });
  });

  group('inviteCodeBodyLength и localJoinCodeError', () {
    for (final (text, chars, error) in const [
      ('', 0, JoinCodeError.empty),
      ('M', 0, JoinCodeError.empty),
      ('MLN', 0, JoinCodeError.empty),
      ('MLN-4', 1, JoinCodeError.incomplete),
      ('MLN-48K', 3, JoinCodeError.incomplete),
      ('MLN-48K2', 4, null),
    ]) {
      test('«$text»: символов $chars, ошибка ${error?.name}', () {
        expect(inviteCodeBodyLength(text), chars);
        expect(localJoinCodeError(text), error);
      });
    }
  });

  test('completeInviteCode: MLN-4 не код, хотя normalizeInviteCode читает '
      'MLN4 как четыре символа M1N4', () {
    expect(normalizeInviteCode('MLN-4'), 'MLN-M1N4');
    expect(completeInviteCode('MLN-4'), isNull);
    expect(completeInviteCode('MLN-48K'), isNull);
    expect(completeInviteCode('MLN'), isNull);
    expect(completeInviteCode(''), isNull);
    expect(completeInviteCode('MLN-48K2'), 'MLN-48K2');
    expect(completeInviteCode('MLN-M1N4'), 'MLN-M1N4');
  });

  group('InviteCodeFormatter', () {
    const formatter = InviteCodeFormatter();

    test('правка, которую автоформат не меняет, остаётся как есть вместе с '
        'курсором', () {
      const value = TextEditingValue(
        text: 'MLN-48K2',
        selection: TextSelection.collapsed(offset: 5),
      );
      expect(formatter.formatEditUpdate(TextEditingValue.empty, value), value);
    });

    test('изменённый текст - курсор в конце', () {
      final result = formatter.formatEditUpdate(
        const TextEditingValue(text: 'MLN-48K'),
        const TextEditingValue(
          text: 'MLN-48k2',
          selection: TextSelection.collapsed(offset: 8),
        ),
      );
      expect(result.text, 'MLN-48K2');
      expect(result.selection, const TextSelection.collapsed(offset: 8));
    });

    test('вставка сообщения целиком оставляет только код', () {
      final result = formatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(
          text: 'Код MLN-48K2 действует 24 часа',
          selection: TextSelection.collapsed(offset: 30),
        ),
      );
      expect(result.text, 'MLN-48K2');
      expect(result.selection, const TextSelection.collapsed(offset: 8));
    });
  });
}
