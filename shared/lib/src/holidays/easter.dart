import '../time/local_date.dart';

/// Православная Пасха в году [year] (по григорианскому календарю).
///
/// Алгоритм Миуса для юлианского календаря и перевод в григорианский:
/// разница календарей в марте–мае года `y` равна `y~/100 − y~/400 − 2`
/// (13 дней для 1900–2099). Годы до 1583 (до григорианского календаря) —
/// [RangeError].
LocalDate orthodoxEaster(int year) {
  RangeError.checkValueInInterval(year, 1583, 9999, 'year');
  final a = year % 4;
  final b = year % 7;
  final c = year % 19;
  final d = (19 * c + 15) % 30;
  final e = (2 * a + 4 * b - d + 34) % 7;
  final month = (d + e + 114) ~/ 31;
  final day = (d + e + 114) % 31 + 1;
  final shift = year ~/ 100 - year ~/ 400 - 2;
  // Юлианская дата как григорианская + разница календарей.
  return LocalDate(year, month, 1).addDays(day - 1 + shift);
}

/// Прощёное воскресенье — последний день Масленицы: Пасха − 49 дней.
LocalDate forgivenessSunday(int year) => orthodoxEaster(year).addDays(-49);
