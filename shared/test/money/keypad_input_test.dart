import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _ = ' ';

/// Нажимает клавиши строки: цифры, `,` и `<` (стереть). Непринятое нажатие
/// оставляет состояние как было.
KeypadInput type(String keys, [KeypadInput start = KeypadInput.empty]) {
  var input = start;
  for (final key in keys.split('')) {
    final next = switch (key) {
      ',' => input.comma(),
      '<' => input.backspace(),
      _ => input.digit(int.parse(key)),
    };
    input = next ?? input;
  }
  return input;
}

void main() {
  group('KeypadInput', () {
    test('пустой ввод', () {
      const input = KeypadInput.empty;
      expect(input.isEmpty, isTrue);
      expect(input.amount, Money.zero);
      expect(input.display, '');
      expect(input.canSave, isFalse);
    });

    test('«1 250» и «149,9» на экране', () {
      final whole = type('1250');
      expect(whole.display, '1${_}250');
      expect(whole.amount, const Money.rubles(1250));

      final fraction = type('149,9');
      expect(fraction.display, '149,9');
      expect(fraction.amount, const Money(14990));
      expect(fraction.canSave, isTrue);
    });

    test('«,» на пустом поле даёт «0,»', () {
      final input = KeypadInput.empty.comma()!;
      expect(input.text, '0,');
      expect(input.display, '0,');
      expect(input.amount, Money.zero);
      expect(input.canSave, isFalse);
      expect(type('0,01').canSave, isTrue);
    });

    test('без ведущих нулей: «0» + «5» → «5», «0» + «0» не принимается', () {
      final zero = KeypadInput.empty.digit(0)!;
      expect(zero.text, '0');
      expect(zero.canSave, isFalse);
      expect(zero.digit(5)!.text, '5');
      expect(zero.digit(0), isNull);
      expect(type('0,05').amount, const Money(5));
    });

    test('не больше одной запятой и 2 знаков после неё', () {
      final input = type('12,34');
      expect(input.digit(5), isNull);
      expect(input.comma(), isNull);
      expect(type('12,3').comma(), isNull);
    });

    test('максимум 10 000 000,00 ₽', () {
      final max = type('10000000');
      expect(max.amount.kopecks, maxExpenseKopecks);
      expect(max.digit(0), isNull);
      final withComma = max.comma()!;
      expect(withComma.digit(0)!.text, '10000000,0');
      expect(withComma.digit(1), isNull);
      expect(type('9999999').digit(9), isNull);
    });

    test('«стереть» убирает последний символ', () {
      expect(KeypadInput.empty.backspace(), isNull);
      expect(type('0,<').text, '0');
      expect(type('149,9<').text, '149,');
      expect(type('149,9<<<<<').isEmpty, isTrue);
    });

    test('цифра вне 0–9 — ошибка', () {
      expect(() => KeypadInput.empty.digit(10), throwsRangeError);
      expect(() => KeypadInput.empty.digit(-1), throwsRangeError);
    });

    test('заполнение суммой траты при правке', () {
      expect(KeypadInput.fromMoney(const Money(14990)).text, '149,90');
      expect(KeypadInput.fromMoney(const Money.rubles(640)).text, '640');
      expect(KeypadInput.fromMoney(const Money(5)).text, '0,05');
      expect(KeypadInput.fromMoney(Money.zero), KeypadInput.empty);
      expect(
        KeypadInput.fromMoney(const Money(14990)).backspace()!.text,
        '149,9',
      );
      expect(() => KeypadInput.fromMoney(const Money(-1)), throwsRangeError);
      expect(
        () => KeypadInput.fromMoney(const Money(maxExpenseKopecks + 1)),
        throwsRangeError,
      );
    });

    test('равенство и текст', () {
      expect(type('12'), type('12'));
      expect(type('12').hashCode, type('12').hashCode);
      expect(type('12').toString(), 'KeypadInput(12)');
    });
  });
}
