import 'package:shared/shared.dart';

final class UpcomingRecurring {
  const UpcomingRecurring({
    required this.rule,
    required this.category,
    required this.date,
    required this.days,
  });

  final RecurringRule rule;
  final Category? category;
  final LocalDate date;
  final int days;
}

final class ChargedRecurring {
  const ChargedRecurring({
    required this.rule,
    required this.category,
    required this.expense,
  });

  final RecurringRule rule;
  final Category? category;
  final Expense expense;
}

final class RecurringOverview {
  const RecurringOverview({
    required this.budgetId,
    required this.today,
    required this.ruleCount,
    required this.monthly,
    required this.upcoming,
    required this.charged,
    this.unknownCategoryIds = const {},
  });

  const RecurringOverview.empty({required this.budgetId, required this.today})
    : ruleCount = 0,
      monthly = Money.zero,
      upcoming = const [],
      charged = const [],
      unknownCategoryIds = const {};

  factory RecurringOverview.of({
    required String budgetId,
    required LocalDate today,
    required List<RecurringRule> rules,
    required Map<String, Expense> charges,
    required List<Category> categories,
  }) {
    final byId = {for (final c in categories) c.id: c};
    Category? system;
    for (final c in categories) {
      if (c.isSystem) {
        system = c;
        break;
      }
    }
    final unknown = <String>{};
    Category? categoryOf(RecurringRule rule) {
      final found = byId[rule.categoryId];
      if (found != null) return found;
      unknown.add(rule.categoryId);
      return system;
    }

    var monthly = Money.zero;
    final upcoming = <UpcomingRecurring>[];
    final charged = <ChargedRecurring>[];
    for (final rule in rules) {
      if (rule.isDeleted) continue;
      monthly += rule.amount;
      final expense = charges[rule.id];
      if (expense != null) {
        charged.add(
          ChargedRecurring(
            rule: rule,
            category: categoryOf(rule),
            expense: expense,
          ),
        );
        continue;
      }
      final date = nextChargeDate(
        startMonth: rule.startMonth,
        dayOfMonth: rule.dayOfMonth,
        today: today,
      );
      upcoming.add(
        UpcomingRecurring(
          rule: rule,
          category: categoryOf(rule),
          date: date,
          days: today.daysUntil(date),
        ),
      );
    }
    upcoming.sort((a, b) => a.date.compareTo(b.date));
    charged.sort((a, b) => a.expense.spentOn.compareTo(b.expense.spentOn));
    return RecurringOverview(
      budgetId: budgetId,
      today: today,
      ruleCount: upcoming.length + charged.length,
      monthly: monthly,
      upcoming: List.unmodifiable(upcoming),
      charged: List.unmodifiable(charged),
      unknownCategoryIds: Set.unmodifiable(unknown),
    );
  }

  final String? budgetId;
  final LocalDate today;
  final int ruleCount;
  final Money monthly;
  final List<UpcomingRecurring> upcoming;
  final List<ChargedRecurring> charged;
  final Set<String> unknownCategoryIds;

  YearMonth get month => YearMonth.of(today);

  bool get isEmpty => ruleCount == 0;

  Money get upcomingTotal =>
      upcoming.fold(Money.zero, (sum, r) => sum + r.rule.amount);

  Money get chargedTotal =>
      charged.fold(Money.zero, (sum, r) => sum + r.expense.amount);
}
