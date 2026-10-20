import 'year_month.dart';

const int _msPerDay = 24 * 60 * 60 * 1000;
final RegExp _isoDate = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// Високосный ли год (григорианский календарь).
bool isLeapYear(int year) =>
    (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;

/// Число дней в месяце [month] (1–12) года [year].
int daysInMonth(int year, int month) {
  RangeError.checkValueInInterval(month, 1, 12, 'month');
  return switch (month) {
    2 => isLeapYear(year) ? 29 : 28,
    4 || 6 || 9 || 11 => 30,
    _ => 31,
  };
}

/// Календарная дата без времени и часового пояса (`spentOn`, дни календаря).
///
/// Сравнение и арифметика — по дням, без перехода на летнее время:
/// внутри используется UTC.
final class LocalDate implements Comparable<LocalDate> {
  /// Дата; бросает [RangeError], если такого дня нет (31 апреля, 29.02.2026).
  LocalDate(this.year, this.month, this.day) {
    RangeError.checkValueInInterval(year, 1, 9999, 'year');
    RangeError.checkValueInInterval(month, 1, 12, 'month');
    RangeError.checkValueInInterval(day, 1, daysInMonth(year, month), 'day');
  }

  /// Дата из локальных полей [dateTime] (год, месяц, день как на часах).
  factory LocalDate.fromDateTime(DateTime dateTime) =>
      LocalDate(dateTime.year, dateTime.month, dateTime.day);

  factory LocalDate._fromUtc(DateTime utc) =>
      LocalDate(utc.year, utc.month, utc.day);

  /// Разбор строки `YYYY-MM-DD`; иначе [FormatException].
  factory LocalDate.parse(String text) {
    final match = _isoDate.firstMatch(text);
    if (match == null) {
      throw FormatException('Expected date YYYY-MM-DD', text);
    }
    try {
      return LocalDate(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
      );
    } on RangeError catch (e) {
      throw FormatException('Invalid date: ${e.message}', text);
    }
  }

  /// Как [LocalDate.parse], но `null` вместо ошибки.
  static LocalDate? tryParse(String text) {
    try {
      return LocalDate.parse(text);
    } on FormatException {
      return null;
    }
  }

  final int year;
  final int month;
  final int day;

  DateTime get _utc => DateTime.utc(year, month, day);

  /// Месяц этой даты.
  YearMonth get yearMonth => YearMonth(year, month);

  /// День недели: 1 — понедельник … 7 — воскресенье.
  int get weekday => _utc.weekday;

  /// Дата через [days] дней (отрицательное — назад).
  LocalDate addDays(int days) =>
      LocalDate._fromUtc(DateTime.utc(year, month, day + days));

  /// Сколько дней от этой даты до [other] (`other − this`, может быть < 0).
  int daysUntil(LocalDate other) =>
      (other._utc.millisecondsSinceEpoch - _utc.millisecondsSinceEpoch) ~/
      _msPerDay;

  bool isBefore(LocalDate other) => compareTo(other) < 0;
  bool isAfter(LocalDate other) => compareTo(other) > 0;

  bool operator <(LocalDate other) => compareTo(other) < 0;
  bool operator <=(LocalDate other) => compareTo(other) <= 0;
  bool operator >(LocalDate other) => compareTo(other) > 0;
  bool operator >=(LocalDate other) => compareTo(other) >= 0;

  @override
  int compareTo(LocalDate other) {
    if (year != other.year) return year.compareTo(other.year);
    if (month != other.month) return month.compareTo(other.month);
    return day.compareTo(other.day);
  }

  @override
  bool operator ==(Object other) =>
      other is LocalDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  /// `YYYY-MM-DD` — формат дат в JSON и БД.
  String toJson() => toString();

  @override
  String toString() =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';
}
