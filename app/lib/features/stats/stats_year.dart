import 'package:shared/shared.dart';

import '../../data/queries/stats_queries.dart';
import '../month/month_picker_sheet.dart' show priciestMonth;
import 'stats_month.dart';

enum StatsYearMonthKind { past, current, future }

StatsYearMonthKind statsYearMonthKind(YearMonth month, LocalDate today) {
  if (isFutureMonth(month, today)) return StatsYearMonthKind.future;
  if (month == YearMonth.of(today)) return StatsYearMonthKind.current;
  return StatsYearMonthKind.past;
}

final class StatsYear {
  const StatsYear({
    required this.year,
    required this.budgetId,
    required this.months,
    required this.categories,
    required this.total,
    required this.expenseCount,
    required this.average,
    this.unknownCategoryIds = const [],
  });

  StatsYear.empty(this.year, {required this.budgetId})
    : months = List.unmodifiable(List<Money>.filled(12, Money.zero)),
      categories = const [],
      total = Money.zero,
      expenseCount = 0,
      average = null,
      unknownCategoryIds = const [];

  factory StatsYear.of({
    required int year,
    required LocalDate today,
    required String budgetId,
    required List<Money> monthTotals,
    required List<CategoryTotal> totals,
    required List<Category> categories,
  }) {
    if (monthTotals.length != 12) {
      throw ArgumentError.value(
        monthTotals.length,
        'monthTotals.length',
        'must be 12',
      );
    }
    final summary = StatsCategories.of(totals: totals, categories: categories);
    final total = Money.sum(monthTotals);
    return StatsYear(
      year: year,
      budgetId: budgetId,
      months: List.unmodifiable(monthTotals),
      categories: summary.categories,
      total: total,
      expenseCount: summary.expenseCount,
      average: averagePerMonth(yearTotal: total, year: year, today: today),
      unknownCategoryIds: summary.unknownCategoryIds,
    );
  }

  final int year;
  final String? budgetId;
  final List<Money> months;
  final List<StatsCategory> categories;
  final Money total;
  final int expenseCount;
  final Money? average;
  final List<String> unknownCategoryIds;

  bool get isEmpty => categories.isEmpty && total.isZero;

  int? get priciest => priciestMonth(months);

  int get monthsWithSpending => months.where((m) => !m.isZero).length;

  LocalDate get from => LocalDate(year, 1, 1);

  LocalDate get to => LocalDate(year, 12, 31);

  @override
  String toString() =>
      'StatsYear($year budget=$budgetId months=$monthsWithSpending '
      'categories=${categories.length} expenses=$expenseCount)';
}
