import '../time/local_date.dart';
import '../time/year_month.dart';

/// Положение дня относительно сегодняшнего.
enum DayKind { past, today, future }

/// Прошедший / сегодня / будущий день [date] при «сегодня» = [today].
DayKind dayKind(LocalDate date, LocalDate today) {
  final order = date.compareTo(today);
  if (order < 0) return DayKind.past;
  if (order == 0) return DayKind.today;
  return DayKind.future;
}

/// Сетка месяца для карточки: недели с понедельника, по 7 ячеек;
/// `null` — пустая ячейка до 1-го числа и после последнего. 4–6 недель.
List<List<LocalDate?>> monthGrid(YearMonth month) {
  final leading = month.firstDay.weekday - 1;
  final cells = <LocalDate?>[
    ...List<LocalDate?>.filled(leading, null),
    for (var day = 1; day <= month.daysInMonth; day++) month.dayOf(day),
  ];
  while (cells.length % 7 != 0) {
    cells.add(null);
  }
  return [
    for (var i = 0; i < cells.length; i += 7)
      List<LocalDate?>.unmodifiable(cells.sublist(i, i + 7)),
  ];
}

/// Будущий ли месяц (его нельзя открыть: траты вносим по факту).
bool isFutureMonth(YearMonth month, LocalDate today) =>
    month > YearMonth.of(today);

/// Можно ли открыть [month] (не будущий).
bool canOpenMonth(YearMonth month, LocalDate today) =>
    !isFutureMonth(month, today);

/// Активна ли стрелка › на [shown]: следующий месяц не будущий.
bool canGoToNextMonth(YearMonth shown, LocalDate today) =>
    canOpenMonth(shown.next, today);

/// Сколько дней месяца уже прошло: текущий — включая сегодня, прошлые —
/// все дни, будущие — 0. Делитель для «В среднем … / день».
int elapsedDays(YearMonth month, LocalDate today) {
  final current = YearMonth.of(today);
  if (month < current) return month.daysInMonth;
  if (month == current) return today.day;
  return 0;
}

int elapsedMonths(int year, LocalDate today) {
  if (year < today.year) return 12;
  if (year == today.year) return today.month;
  return 0;
}
