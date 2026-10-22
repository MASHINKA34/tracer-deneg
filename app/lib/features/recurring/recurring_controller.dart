import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../core/clock.dart';
import '../../data/providers.dart';
import 'recurring_overview.dart';

final class RecurringDataError implements Exception {
  const RecurringDataError(this.what, this.cause);

  final String what;
  final Object cause;

  @override
  String toString() => 'RecurringDataError($what): $cause';
}

final recurringOverviewProvider =
    Provider.autoDispose<AsyncValue<RecurringOverview>>(
      _overview,
      name: 'recurringOverview',
    );

AsyncValue<RecurringOverview> _overview(Ref ref) {
  final today = ref.watch(clockProvider).today();
  final budget = ref.watch(selectedBudgetIdProvider);
  switch (budget) {
    case AsyncError(:final error, :final stackTrace):
      return AsyncError(
        RecurringDataError('selected budget unavailable', error),
        stackTrace,
      );
    case AsyncData(value: null):
      return AsyncData(RecurringOverview.empty(budgetId: null, today: today));
    case AsyncData(value: final String budgetId):
      return _forBudget(ref, budgetId, today);
    default:
      return const AsyncLoading();
  }
}

AsyncValue<RecurringOverview> _forBudget(
  Ref ref,
  String budgetId,
  LocalDate today,
) {
  final month = YearMonth.of(today);
  final rules = ref.watch(recurringRulesProvider(budgetId));
  final charges = ref.watch(
    recurringChargesProvider((budgetId: budgetId, month: month)),
  );
  final categories = ref.watch(categoriesProvider(budgetId));
  for (final (value, what) in <(AsyncValue<Object?>, String)>[
    (rules, 'rules stream failed'),
    (charges, 'charges stream failed month=$month'),
    (categories, 'categories stream failed'),
  ]) {
    if (value case AsyncError(:final error, :final stackTrace)) {
      return AsyncError(RecurringDataError(what, error), stackTrace);
    }
  }
  final r = rules.value;
  final c = charges.value;
  final k = categories.value;
  if (r == null || c == null || k == null) return const AsyncLoading();
  return AsyncData(
    RecurringOverview.of(
      budgetId: budgetId,
      today: today,
      rules: r,
      charges: c,
      categories: k,
    ),
  );
}
