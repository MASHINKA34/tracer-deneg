import '../calendar/calendar.dart';
import '../money/money.dart';
import '../time/local_date.dart';
import '../time/year_month.dart';

/// Уровень подсветки дня по сумме трат (00-spec §7.3).
enum HeatLevel {
  /// 0 ₽ — без заливки, «—».
  zero,

  /// Больше 0 и меньше 500 ₽ — `heat-1`.
  low,

  /// От 500 до 1 500 ₽ включительно — `heat-2`.
  medium,

  /// Больше 1 500 ₽ — `heat-3`.
  high,
}

/// Нижняя граница «Средне»: 500 ₽.
const int heatMediumFromKopecks = 50000;

/// Верхняя граница «Средне»: 1 500 ₽ (включительно).
const int heatMediumToKopecks = 150000;

/// Уровень дня по точной сумме [daySum] в копейках.
HeatLevel heatLevel(Money daySum) {
  final kopecks = daySum.kopecks;
  if (kopecks <= 0) return HeatLevel.zero;
  if (kopecks < heatMediumFromKopecks) return HeatLevel.low;
  if (kopecks <= heatMediumToKopecks) return HeatLevel.medium;
  return HeatLevel.high;
}

/// Среднее в день: итог месяца / число прошедших дней (текущий месяц —
/// включая сегодня, прошлые — все дни), в копейках с округлением «половина
/// вверх». Нет трат или будущий месяц — `null` («—»).
Money? averagePerDay({
  required Money monthTotal,
  required YearMonth month,
  required LocalDate today,
}) {
  final days = elapsedDays(month, today);
  if (days == 0 || monthTotal.kopecks <= 0) return null;
  return Money((monthTotal.kopecks * 2 + days) ~/ (days * 2));
}

Money? averagePerMonth({
  required Money yearTotal,
  required int year,
  required LocalDate today,
}) {
  final months = elapsedMonths(year, today);
  if (months == 0 || yearTotal.kopecks <= 0) return null;
  return Money((yearTotal.kopecks * 2 + months) ~/ (months * 2));
}

/// Шторка дня: сумма дня минус среднее в день (больше нуля — «больше
/// среднего на …», меньше — «меньше среднего на …»).
Money differenceFromAverage({required Money daySum, required Money average}) =>
    daySum - average;

/// Отрезки дат для сравнения месяца с предыдущим (00-spec §2.1).
final class ComparisonPeriod {
  const ComparisonPeriod({
    required this.currentFrom,
    required this.currentTo,
    required this.previousFrom,
    required this.previousTo,
  });

  final LocalDate currentFrom;
  final LocalDate currentTo;
  final LocalDate previousFrom;
  final LocalDate previousTo;

  @override
  bool operator ==(Object other) =>
      other is ComparisonPeriod &&
      other.currentFrom == currentFrom &&
      other.currentTo == currentTo &&
      other.previousFrom == previousFrom &&
      other.previousTo == previousTo;

  @override
  int get hashCode =>
      Object.hash(currentFrom, currentTo, previousFrom, previousTo);

  @override
  String toString() =>
      'ComparisonPeriod($currentFrom..$currentTo vs '
      '$previousFrom..$previousTo)';
}

/// Отрезки для сравнения [month] с прошлым месяцем.
///
/// Текущий месяц — тот же отрезок дней: 1–19 октября против 1–19 сентября
/// (если в прошлом месяце дней меньше — до его конца). Прошедший месяц —
/// полный против полного. Будущий месяц — [ArgumentError].
ComparisonPeriod comparisonPeriod(YearMonth month, LocalDate today) {
  if (isFutureMonth(month, today)) {
    throw ArgumentError.value(month, 'month', 'is in the future of $today');
  }
  final previous = month.previous;
  if (month == YearMonth.of(today)) {
    final lastDay = today.day < previous.daysInMonth
        ? today.day
        : previous.daysInMonth;
    return ComparisonPeriod(
      currentFrom: month.firstDay,
      currentTo: today,
      previousFrom: previous.firstDay,
      previousTo: previous.dayOf(lastDay),
    );
  }
  return ComparisonPeriod(
    currentFrom: month.firstDay,
    currentTo: month.lastDay,
    previousFrom: previous.firstDay,
    previousTo: previous.lastDay,
  );
}

/// Итог сравнения месяцев.
final class MonthComparison {
  const MonthComparison({required this.difference, required this.percent});

  /// Текущий минус прошлый: больше нуля — потратили больше.
  final Money difference;

  /// Изменение в процентах к прошлому, целое (округление от нуля: −10,5 →
  /// −11).
  final int percent;

  bool get isMore => difference.isPositive;
  bool get isLess => difference.isNegative;

  @override
  bool operator ==(Object other) =>
      other is MonthComparison &&
      other.difference == difference &&
      other.percent == percent;

  @override
  int get hashCode => Object.hash(difference, percent);

  @override
  String toString() => 'MonthComparison($difference, $percent%)';
}

/// Сравнение итога [current] с итогом прошлого месяца [previous] за
/// отрезки из [comparisonPeriod]. Если за прошлый отрезок трат нет (0) —
/// `null`: строку сравнения не показываем.
MonthComparison? compareMonths({
  required Money current,
  required Money previous,
}) {
  if (previous.kopecks <= 0) return null;
  final difference = current - previous;
  final scaled = difference.kopecks.abs() * 100;
  final rounded = (scaled * 2 + previous.kopecks) ~/ (previous.kopecks * 2);
  return MonthComparison(
    difference: difference,
    percent: difference.isNegative ? -rounded : rounded,
  );
}
