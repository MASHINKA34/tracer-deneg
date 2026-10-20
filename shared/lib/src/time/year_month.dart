import 'local_date.dart';
import 'local_date.dart' as dates show daysInMonth;

final RegExp _isoMonth = RegExp(r'^(\d{4})-(\d{2})$');

/// Месяц года: `2026-10`. Им задаются экраны месяца, регулярные траты
/// (`recurringMonth`, `startMonth`) и периоды экспорта.
final class YearMonth implements Comparable<YearMonth> {
  YearMonth(this.year, this.month) {
    RangeError.checkValueInInterval(year, 1, 9999, 'year');
    RangeError.checkValueInInterval(month, 1, 12, 'month');
  }

  /// Месяц, в который попадает [date].
  factory YearMonth.of(LocalDate date) => YearMonth(date.year, date.month);

  /// Разбор строки `YYYY-MM`; иначе [FormatException].
  factory YearMonth.parse(String text) {
    final match = _isoMonth.firstMatch(text);
    if (match == null) {
      throw FormatException('Expected month YYYY-MM', text);
    }
    try {
      return YearMonth(int.parse(match.group(1)!), int.parse(match.group(2)!));
    } on RangeError catch (e) {
      throw FormatException('Invalid month: ${e.message}', text);
    }
  }

  /// Как [YearMonth.parse], но `null` вместо ошибки.
  static YearMonth? tryParse(String text) {
    try {
      return YearMonth.parse(text);
    } on FormatException {
      return null;
    }
  }

  final int year;
  final int month;

  int get _index => year * 12 + (month - 1);

  factory YearMonth._fromIndex(int index) =>
      YearMonth(index ~/ 12, index % 12 + 1);

  /// Число дней в месяце.
  int get daysInMonth => dates.daysInMonth(year, month);

  /// 1-е число.
  LocalDate get firstDay => LocalDate(year, month, 1);

  /// Последний день.
  LocalDate get lastDay => LocalDate(year, month, daysInMonth);

  /// День [day] этого месяца.
  LocalDate dayOf(int day) => LocalDate(year, month, day);

  /// Попадает ли [date] в этот месяц.
  bool contains(LocalDate date) => date.year == year && date.month == month;

  /// Месяц через [months] месяцев (отрицательное — назад).
  YearMonth addMonths(int months) => YearMonth._fromIndex(_index + months);

  /// Следующий месяц.
  YearMonth get next => addMonths(1);

  /// Предыдущий месяц.
  YearMonth get previous => addMonths(-1);

  /// Сколько месяцев от этого до [other] (`other − this`).
  int monthsUntil(YearMonth other) => other._index - _index;

  bool operator <(YearMonth other) => _index < other._index;
  bool operator <=(YearMonth other) => _index <= other._index;
  bool operator >(YearMonth other) => _index > other._index;
  bool operator >=(YearMonth other) => _index >= other._index;

  @override
  int compareTo(YearMonth other) => _index.compareTo(other._index);

  @override
  bool operator ==(Object other) =>
      other is YearMonth && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);

  /// `YYYY-MM` — формат месяца в JSON и БД.
  String toJson() => toString();

  @override
  String toString() =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';
}
