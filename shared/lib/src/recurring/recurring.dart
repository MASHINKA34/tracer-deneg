import '../ids/ids.dart';
import '../models/recurring_rule.dart';
import '../time/local_date.dart';
import '../time/year_month.dart';

/// Пространство имён UUID v5 для трат регулярных правил. Сгенерировано
/// один раз для проекта; НЕ МЕНЯТЬ — иначе id трат разойдутся между
/// версиями и появятся дубли.
const String recurringExpenseNamespace = '2206da5e-c0c4-40f2-bcef-e63355091554';

/// День списания в месяце [month]: min(D, дней в месяце) — регулярная на 31-е
/// в феврале списывается 28-го или 29-го.
int chargeDay(int dayOfMonth, YearMonth month) {
  RangeError.checkValueInInterval(dayOfMonth, 1, 31, 'dayOfMonth');
  return dayOfMonth < month.daysInMonth ? dayOfMonth : month.daysInMonth;
}

/// Дата списания в месяце [month].
LocalDate chargeDate(int dayOfMonth, YearMonth month) =>
    month.dayOf(chargeDay(dayOfMonth, month));

/// Детерминированный id траты правила [ruleId] за месяц [month]:
/// UUID v5 от `"<ruleId>:<YYYY-MM>"`. На всех телефонах один и тот же —
/// генерация на нескольких устройствах не даёт дублей.
String recurringExpenseId(String ruleId, YearMonth month) =>
    uuidV5(recurringExpenseNamespace, '$ruleId:$month');

/// Месяцы, за которые трата уже должна существовать: от [startMonth] до
/// текущего; текущий — только если сегодня ≥ дня списания.
List<YearMonth> dueMonths({
  required YearMonth startMonth,
  required int dayOfMonth,
  required LocalDate today,
}) {
  final current = YearMonth.of(today);
  final result = <YearMonth>[];
  for (var month = startMonth; month <= current; month = month.next) {
    if (month == current && today.day < chargeDay(dayOfMonth, month)) break;
    result.add(month);
  }
  return result;
}

/// Месяц начала нового правила: если день списания в текущем месяце ещё не
/// прошёл (в том числе он сегодня) — текущий, иначе следующий.
YearMonth startMonthForNewRule(int dayOfMonth, LocalDate today) {
  final current = YearMonth.of(today);
  return today.day <= chargeDay(dayOfMonth, current) ? current : current.next;
}

/// Ближайшая дата списания строго после [today] (не раньше [startMonth]) —
/// для «Скоро: каждое 24-е · через 5 дней» и подсказки «Первая трата
/// появится 12 ноября».
LocalDate nextChargeDate({
  required YearMonth startMonth,
  required int dayOfMonth,
  required LocalDate today,
}) {
  final current = YearMonth.of(today);
  var month = startMonth > current ? startMonth : current;
  var date = chargeDate(dayOfMonth, month);
  if (date <= today) {
    month = month.next;
    date = chargeDate(dayOfMonth, month);
  }
  return date;
}

/// Трата, которую нужно создать по правилу.
final class PlannedRecurringExpense {
  const PlannedRecurringExpense({
    required this.id,
    required this.month,
    required this.spentOn,
  });

  /// Детерминированный id ([recurringExpenseId]).
  final String id;

  /// `recurringMonth`.
  final YearMonth month;

  /// Дата списания.
  final LocalDate spentOn;

  @override
  bool operator ==(Object other) =>
      other is PlannedRecurringExpense &&
      other.id == id &&
      other.month == month &&
      other.spentOn == spentOn;

  @override
  int get hashCode => Object.hash(id, month, spentOn);

  @override
  String toString() => 'PlannedRecurringExpense($id $month on $spentOn)';
}

/// Недостающие траты правила [rule] на [today] (идемпотентно, 00-spec §7.5).
///
/// [existingExpenseIds] — id трат, которые уже есть локально, в том числе
/// удалённые пользователем (надгробия): такие не пересоздаются. Удалённое
/// правило новых трат не создаёт.
List<PlannedRecurringExpense> planRecurringExpenses(
  RecurringRule rule,
  LocalDate today, {
  required Set<String> existingExpenseIds,
}) {
  if (rule.isDeleted) return const [];
  return [
    for (final month in dueMonths(
      startMonth: rule.startMonth,
      dayOfMonth: rule.dayOfMonth,
      today: today,
    ))
      if (!existingExpenseIds.contains(recurringExpenseId(rule.id, month)))
        PlannedRecurringExpense(
          id: recurringExpenseId(rule.id, month),
          month: month,
          spentOn: chargeDate(rule.dayOfMonth, month),
        ),
  ];
}
