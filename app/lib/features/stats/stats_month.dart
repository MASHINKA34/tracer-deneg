import 'package:shared/shared.dart';

import '../../data/queries/stats_queries.dart';
import '../month/month_picker_sheet.dart' show sumOfDays;

final class StatsCategory {
  const StatsCategory({
    required this.id,
    required this.emoji,
    required this.name,
    required this.color,
    required this.total,
    required this.count,
    required this.percent,
    required this.fraction,
  });

  final String id;
  final String emoji;
  final String name;
  final CategoryColor? color;
  final Money total;
  final int count;
  final int percent;
  final double fraction;

  @override
  bool operator ==(Object other) =>
      other is StatsCategory &&
      other.id == id &&
      other.emoji == emoji &&
      other.name == name &&
      other.color == color &&
      other.total == total &&
      other.count == count &&
      other.percent == percent &&
      other.fraction == fraction;

  @override
  int get hashCode =>
      Object.hash(id, emoji, name, color, total, count, percent, fraction);

  @override
  String toString() =>
      'StatsCategory($id $name $total count=$count $percent% '
      'fraction=${fraction.toStringAsFixed(3)})';
}

final class StatsCategories {
  const StatsCategories({
    required this.categories,
    required this.total,
    required this.expenseCount,
    required this.unknownCategoryIds,
  });

  factory StatsCategories.of({
    required List<CategoryTotal> totals,
    required List<Category> categories,
  }) {
    final byId = {for (final c in categories) c.id: c};
    Category? system;
    for (final category in categories) {
      if (category.isSystem) {
        system = category;
        break;
      }
    }
    final other = presetCategories.firstWhere((p) => p.isSystem);
    final otherId = system?.id ?? '';
    final unknown = <String>[];
    final merged = <String, ({Money total, int count})>{};
    for (final t in totals) {
      final known = byId.containsKey(t.categoryId);
      if (!known) unknown.add(t.categoryId);
      final id = known ? t.categoryId : otherId;
      final previous = merged[id];
      merged[id] = previous == null
          ? (total: t.total, count: t.count)
          : (total: previous.total + t.total, count: previous.count + t.count);
    }
    final ids = merged.keys.toList();
    final order = List.generate(ids.length, (i) => i)
      ..sort((a, b) {
        final byTotal = merged[ids[b]]!.total.compareTo(merged[ids[a]]!.total);
        return byTotal != 0 ? byTotal : a.compareTo(b);
      });
    final sorted = [for (final i in order) ids[i]];
    final amounts = [for (final id in sorted) merged[id]!.total.kopecks];
    final percents = percentShares(amounts);
    final max = amounts.isEmpty ? 0 : amounts.first;
    return StatsCategories(
      categories: List.unmodifiable([
        for (final (i, id) in sorted.indexed)
          _category(
            byId[id],
            id: id,
            other: other,
            total: merged[id]!.total,
            count: merged[id]!.count,
            percent: percents[i],
            fraction: max <= 0 ? 0 : amounts[i] / max,
          ),
      ]),
      total: Money.sum([for (final id in sorted) merged[id]!.total]),
      expenseCount: merged.values.fold(0, (sum, m) => sum + m.count),
      unknownCategoryIds: List.unmodifiable(unknown),
    );
  }

  static StatsCategory _category(
    Category? category, {
    required String id,
    required PresetCategory other,
    required Money total,
    required int count,
    required int percent,
    required double fraction,
  }) => StatsCategory(
    id: id,
    emoji: category?.emoji ?? other.emoji,
    name: category?.name ?? other.name,
    color: category == null ? other.color : category.color,
    total: total,
    count: count,
    percent: percent,
    fraction: fraction,
  );

  final List<StatsCategory> categories;
  final Money total;
  final int expenseCount;
  final List<String> unknownCategoryIds;
}

final class StatsMonth {
  const StatsMonth({
    required this.month,
    required this.budgetId,
    required this.categories,
    required this.total,
    required this.expenseCount,
    required this.average,
    required this.comparison,
    this.unknownCategoryIds = const [],
  });

  const StatsMonth.empty(this.month, {required this.budgetId})
    : categories = const [],
      total = Money.zero,
      expenseCount = 0,
      average = null,
      comparison = null,
      unknownCategoryIds = const [];

  factory StatsMonth.of({
    required YearMonth month,
    required LocalDate today,
    required String budgetId,
    required List<CategoryTotal> totals,
    required List<Category> categories,
    required Map<int, Money> days,
    required Map<int, Money> previousDays,
  }) {
    final summary = StatsCategories.of(totals: totals, categories: categories);
    final total = summary.total;
    final period = comparisonPeriod(month, today);
    return StatsMonth(
      month: month,
      budgetId: budgetId,
      categories: summary.categories,
      total: total,
      expenseCount: summary.expenseCount,
      average: averagePerDay(monthTotal: total, month: month, today: today),
      comparison: compareMonths(
        current: sumOfDays(days, period.currentFrom, period.currentTo),
        previous: sumOfDays(
          previousDays,
          period.previousFrom,
          period.previousTo,
        ),
      ),
      unknownCategoryIds: summary.unknownCategoryIds,
    );
  }

  final YearMonth month;
  final String? budgetId;
  final List<StatsCategory> categories;
  final Money total;
  final int expenseCount;
  final Money? average;
  final MonthComparison? comparison;
  final List<String> unknownCategoryIds;

  bool get isEmpty => categories.isEmpty;

  YearMonth get previous => month.previous;

  @override
  String toString() =>
      'StatsMonth($month budget=$budgetId categories=${categories.length} '
      'expenses=$expenseCount)';
}
