import 'money.dart';

/// Автомат ввода суммы с цифровой клавиатуры (00-spec §7.1).
///
/// Хранит набранный текст: цифры и не больше одной запятой (`1250`,
/// `149,9`, `0,`). Правила:
/// - не больше 2 знаков после запятой;
/// - без ведущих нулей: после одиночного `0` цифра заменяет его (`0` → `5`);
/// - `,` на пустом поле даёт `0,`;
/// - не больше 10 000 000,00 ₽.
///
/// Каждое нажатие возвращает новое состояние или `null`, если нажатие
/// не принято (интерфейс может «встряхнуть» сумму).
final class KeypadInput {
  const KeypadInput._(this.text);

  /// Пустой ввод.
  static const KeypadInput empty = KeypadInput._('');

  /// Ввод, заполненный суммой [amount] (правка траты): 14 990 коп. → `149,90`,
  /// 64 000 коп. → `640`. Ноль — пустой ввод.
  factory KeypadInput.fromMoney(Money amount) {
    final kopecks = amount.kopecks;
    RangeError.checkValueInInterval(kopecks, 0, maxExpenseKopecks, 'amount');
    if (kopecks == 0) return empty;
    final rubles = kopecks ~/ 100;
    final cents = kopecks % 100;
    return KeypadInput._(
      cents == 0 ? '$rubles' : '$rubles,${cents.toString().padLeft(2, '0')}',
    );
  }

  /// Набранный текст без форматирования.
  final String text;

  bool get isEmpty => text.isEmpty;

  bool get _hasComma => text.contains(',');

  /// Набранная сумма (пустой ввод и `0,` — ноль).
  Money get amount {
    if (text.isEmpty) return Money.zero;
    final parts = text.split(',');
    final rubles = parts[0].isEmpty ? 0 : int.parse(parts[0]);
    final fraction = parts.length > 1 ? parts[1].padRight(2, '0') : '00';
    return Money(rubles * 100 + int.parse(fraction));
  }

  /// Можно ли сохранить: сумма больше нуля (не больше максимума — по
  /// построению).
  bool get canSave => amount.kopecks >= minExpenseKopecks;

  /// Текст для экрана: целая часть с группами (`1 250`), дробная — как
  /// набрана (`149,9`, `0,`). Пустой ввод — пустая строка.
  String get display {
    if (text.isEmpty) return '';
    final parts = text.split(',');
    final whole = groupDigits(int.parse(parts[0]));
    return _hasComma ? '$whole,${parts[1]}' : whole;
  }

  /// Нажатие цифры [digit] (0–9).
  KeypadInput? digit(int digit) {
    RangeError.checkValueInInterval(digit, 0, 9, 'digit');
    final String next;
    if (text == '0') {
      if (digit == 0) return null;
      next = '$digit';
    } else {
      if (_hasComma && text.length - text.indexOf(',') - 1 >= 2) return null;
      next = '$text$digit';
    }
    final candidate = KeypadInput._(next);
    if (candidate.amount.kopecks > maxExpenseKopecks) return null;
    return candidate;
  }

  /// Нажатие запятой.
  KeypadInput? comma() {
    if (_hasComma) return null;
    return KeypadInput._(text.isEmpty ? '0,' : '$text,');
  }

  /// Нажатие «стереть»: убирает последний символ.
  KeypadInput? backspace() {
    if (text.isEmpty) return null;
    return KeypadInput._(text.substring(0, text.length - 1));
  }

  @override
  bool operator ==(Object other) => other is KeypadInput && other.text == text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'KeypadInput($text)';
}
