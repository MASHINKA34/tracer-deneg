/// Неразрывный пробел U+00A0: разделитель групп разрядов и пробел перед ₽.
const String nbsp = ' ';

/// Знак рубля.
const String rubleSign = '₽';

/// Знак «минус» U+2212 для отрицательных сумм (разница со средним и т.п.).
const String minusSign = '−';

/// Минимальная сумма траты: 0,01 ₽.
const int minExpenseKopecks = 1;

/// Максимальная сумма траты: 10 000 000,00 ₽.
const int maxExpenseKopecks = 1000000000;

/// Сумма в копейках (00-spec §7.1). Всё хранится и считается в копейках,
/// округление до рубля — только при показе итогов.
final class Money implements Comparable<Money> {
  const Money(this.kopecks);

  /// Рубли и копейки: `Money.rubles(149, 90)` = 149,90 ₽.
  const Money.rubles(int rubles, [int kopecks = 0])
    : kopecks = rubles * 100 + kopecks;

  static const Money zero = Money(0);

  /// Сумма всех [values].
  static Money sum(Iterable<Money> values) =>
      Money(values.fold(0, (total, m) => total + m.kopecks));

  final int kopecks;

  bool get isZero => kopecks == 0;
  bool get isNegative => kopecks < 0;
  bool get isPositive => kopecks > 0;

  /// Модуль суммы.
  Money get abs => Money(kopecks.abs());

  /// Целые рубли без округления (149,90 → 149).
  int get wholeRubles => kopecks ~/ 100;

  /// Копейки 0–99 (149,90 → 90).
  int get kopecksPart => kopecks.abs() % 100;

  /// Рубли с округлением «половина вверх» (по модулю: −0,50 → −1).
  int get roundedRubles {
    final rubles = (kopecks.abs() + 50) ~/ 100;
    return kopecks < 0 ? -rubles : rubles;
  }

  Money operator +(Money other) => Money(kopecks + other.kopecks);
  Money operator -(Money other) => Money(kopecks - other.kopecks);
  Money operator -() => Money(-kopecks);

  bool operator <(Money other) => kopecks < other.kopecks;
  bool operator <=(Money other) => kopecks <= other.kopecks;
  bool operator >(Money other) => kopecks > other.kopecks;
  bool operator >=(Money other) => kopecks >= other.kopecks;

  @override
  int compareTo(Money other) => kopecks.compareTo(other.kopecks);

  @override
  bool operator ==(Object other) => other is Money && other.kopecks == kopecks;

  @override
  int get hashCode => kopecks.hashCode;

  /// Формат в списках и полях: `640 ₽`, `1 280 ₽`, `149,90 ₽` — копейки
  /// только если не ноль.
  String format() {
    final sign = kopecks < 0 ? minusSign : '';
    final rubles = groupDigits(kopecks.abs() ~/ 100);
    final cents = kopecksPart;
    final fraction = cents == 0 ? '' : ',${cents.toString().padLeft(2, '0')}';
    return '$sign$rubles$fraction$nbsp$rubleSign';
  }

  /// Формат итогов (месяц, день, категории, средние): до рубля, половина
  /// вверх — `18 300 ₽`.
  String formatTotal() => '${groupDigits(roundedRubles)}$nbsp$rubleSign';

  /// Формат ячейки календаря: без ₽, до рубля; от 10 000 — `12,4к`
  /// (одна цифра после запятой с округлением, `,0` убирается: `12к`),
  /// от 1 000 000 — так же с `м`: `1,3м`.
  String formatCell() {
    final rubles = roundedRubles;
    final sign = rubles < 0 ? minusSign : '';
    final value = rubles.abs();
    if (value < 10000) return '$sign${groupDigits(value)}';
    final tenthsOfThousands = (value + 50) ~/ 100;
    if (tenthsOfThousands < 10000) {
      return '$sign${_tenths(tenthsOfThousands)}к';
    }
    final tenthsOfMillions = (value + 50000) ~/ 100000;
    return '$sign${_tenths(tenthsOfMillions)}м';
  }

  /// Для JSON: число копеек.
  int toJson() => kopecks;

  @override
  String toString() => 'Money($kopecks)';
}

/// Целое с группами разрядов через неразрывный пробел: `12 500`.
/// Отрицательное — со знаком U+2212.
String groupDigits(int value) {
  if (value < 0) return '$minusSign${groupDigits(-value)}';
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(nbsp);
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// Десятые доли как «12,4» / «12»: 124 → «12,4», 120 → «12».
String _tenths(int tenths) {
  final whole = groupDigits(tenths ~/ 10);
  final rest = tenths % 10;
  return rest == 0 ? whole : '$whole,$rest';
}
