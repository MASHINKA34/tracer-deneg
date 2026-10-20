import 'local_date.dart';

/// День и месяц без года — дата рождения (`birthdayMonth/Day`).
///
/// 29 февраля допустимо; в невисокосный год оно отмечается 28 февраля.
final class MonthDay implements Comparable<MonthDay> {
  MonthDay(this.month, this.day) {
    RangeError.checkValueInInterval(month, 1, 12, 'month');
    // 2000 — високосный: в феврале допускаем 29.
    RangeError.checkValueInInterval(day, 1, daysInMonth(2000, month), 'day');
  }

  /// Пара из JSON/БД: оба `null` — даты нет; один `null` или
  /// несуществующий день — [FormatException].
  static MonthDay? fromParts(int? month, int? day) {
    if (month == null && day == null) return null;
    if (month == null || day == null) {
      throw FormatException('Birthday needs both month and day: $month/$day');
    }
    try {
      return MonthDay(month, day);
    } on RangeError catch (e) {
      throw FormatException('Invalid birthday $month/$day: ${e.message}');
    }
  }

  final int month;
  final int day;

  /// Дата в году [year]: 29.02 в невисокосный год — 28.02.
  LocalDate inYear(int year) {
    if (month == 2 && day == 29 && !isLeapYear(year)) {
      return LocalDate(year, 2, 28);
    }
    return LocalDate(year, month, day);
  }

  /// Ближайшая такая дата не раньше [date] (сама [date], если совпадает).
  LocalDate nextOnOrAfter(LocalDate date) {
    final thisYear = inYear(date.year);
    return thisYear >= date ? thisYear : inYear(date.year + 1);
  }

  @override
  int compareTo(MonthDay other) => month != other.month
      ? month.compareTo(other.month)
      : day.compareTo(other.day);

  @override
  bool operator ==(Object other) =>
      other is MonthDay && other.month == month && other.day == day;

  @override
  int get hashCode => Object.hash(month, day);

  @override
  String toString() =>
      'MonthDay(${day.toString().padLeft(2, '0')}.'
      '${month.toString().padLeft(2, '0')})';
}
