import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../core/clock.dart';
import '../../data/providers.dart';
import 'stats_month.dart';
import 'stats_year.dart';

final _log = Logger('stats');

final class StatsMonthController extends Notifier<YearMonth> {
  @override
  YearMonth build() {
    final today = ref.watch(clockProvider).today();
    final month = YearMonth.of(today);
    _log.fine('stats month=$month (current) today=$today');
    return month;
  }

  bool open(YearMonth month) {
    final today = ref.read(clockProvider).today();
    final from = state;
    if (isFutureMonth(month, today)) {
      _log.warning(
        'stats month open $month by=picker ignored: future month '
        'today=$today, staying on $from',
      );
      return false;
    }
    if (month == from) {
      _log.fine('stats month open $month by=picker: already shown');
      return true;
    }
    state = month;
    _log.fine('stats month $from → $state by=picker');
    return true;
  }
}

final statsMonthControllerProvider =
    NotifierProvider<StatsMonthController, YearMonth>(
      StatsMonthController.new,
      name: 'statsMonthController',
    );

final class StatsDataError implements Exception {
  const StatsDataError(this.what, this.cause);

  final String what;
  final Object cause;

  @override
  String toString() => 'StatsDataError($what): $cause';
}

final statsMonthProvider = Provider.autoDispose<AsyncValue<StatsMonth>>(
  _statsMonth,
  name: 'statsMonth',
);

AsyncValue<StatsMonth> _statsMonth(Ref ref) {
  final month = ref.watch(statsMonthControllerProvider);
  final today = ref.watch(clockProvider).today();
  final budget = ref.watch(selectedBudgetIdProvider);
  switch (budget) {
    case AsyncError(:final error, :final stackTrace):
      return AsyncError(
        StatsDataError('selected budget unavailable', error),
        stackTrace,
      );
    case AsyncData(value: null):
      return AsyncData(StatsMonth.empty(month, budgetId: null));
    case AsyncData(value: final String budgetId):
      return _forBudget(ref, budgetId, month, today);
    default:
      return const AsyncLoading();
  }
}

AsyncValue<StatsMonth> _forBudget(
  Ref ref,
  String budgetId,
  YearMonth month,
  LocalDate today,
) {
  final totals = ref.watch(
    categoryTotalsProvider((
      budgetId: budgetId,
      from: month.firstDay,
      to: month.lastDay,
    )),
  );
  final categories = ref.watch(categoriesProvider(budgetId));
  final days = ref.watch(dayTotalsProvider((budgetId: budgetId, month: month)));
  final previousDays = ref.watch(
    dayTotalsProvider((budgetId: budgetId, month: month.previous)),
  );
  for (final (value, what) in <(AsyncValue<Object?>, String)>[
    (totals, 'category totals stream failed'),
    (categories, 'categories stream failed'),
    (days, 'day totals stream failed month=$month'),
    (previousDays, 'day totals stream failed month=${month.previous}'),
  ]) {
    if (value case AsyncError(:final error, :final stackTrace)) {
      return AsyncError(StatsDataError(what, error), stackTrace);
    }
  }
  final t = totals.value;
  final c = categories.value;
  final d = days.value;
  final p = previousDays.value;
  if (t == null || c == null || d == null || p == null) {
    return const AsyncLoading();
  }
  return AsyncData(
    StatsMonth.of(
      month: month,
      today: today,
      budgetId: budgetId,
      totals: t,
      categories: c,
      days: d,
      previousDays: p,
    ),
  );
}

final class StatsYearController extends Notifier<int> {
  @override
  int build() {
    final today = ref.watch(clockProvider).today();
    _log.fine('stats year=${today.year} (current) today=$today');
    return today.year;
  }

  bool open(int year, {required String by}) {
    final today = ref.read(clockProvider).today();
    final from = state;
    if (year > today.year || year < 1) {
      _log.fine(
        'stats year $from → $year by=$by ignored: '
        '${year > today.year ? 'future year' : 'no earlier years'} '
        'today=$today',
      );
      return false;
    }
    if (year == from) {
      _log.fine('stats year open $year by=$by: already shown');
      return true;
    }
    state = year;
    _log.fine('stats year $from → $year by=$by');
    return true;
  }
}

final statsYearControllerProvider = NotifierProvider<StatsYearController, int>(
  StatsYearController.new,
  name: 'statsYearController',
);

final statsYearProvider = Provider.autoDispose<AsyncValue<StatsYear>>(
  _statsYear,
  name: 'statsYear',
);

AsyncValue<StatsYear> _statsYear(Ref ref) {
  final year = ref.watch(statsYearControllerProvider);
  final today = ref.watch(clockProvider).today();
  final budget = ref.watch(selectedBudgetIdProvider);
  switch (budget) {
    case AsyncError(:final error, :final stackTrace):
      return AsyncError(
        StatsDataError('selected budget unavailable', error),
        stackTrace,
      );
    case AsyncData(value: null):
      return AsyncData(StatsYear.empty(year, budgetId: null));
    case AsyncData(value: final String budgetId):
      return _yearForBudget(ref, budgetId, year, today);
    default:
      return const AsyncLoading();
  }
}

AsyncValue<StatsYear> _yearForBudget(
  Ref ref,
  String budgetId,
  int year,
  LocalDate today,
) {
  final months = ref.watch(
    yearMonthTotalsProvider((budgetId: budgetId, year: year)),
  );
  final totals = ref.watch(
    categoryTotalsProvider((
      budgetId: budgetId,
      from: LocalDate(year, 1, 1),
      to: LocalDate(year, 12, 31),
    )),
  );
  final categories = ref.watch(categoriesProvider(budgetId));
  for (final (value, what) in <(AsyncValue<Object?>, String)>[
    (months, 'month totals stream failed'),
    (totals, 'category totals stream failed'),
    (categories, 'categories stream failed'),
  ]) {
    if (value case AsyncError(:final error, :final stackTrace)) {
      return AsyncError(StatsDataError(what, error), stackTrace);
    }
  }
  final m = months.value;
  final t = totals.value;
  final c = categories.value;
  if (m == null || t == null || c == null) return const AsyncLoading();
  return AsyncData(
    StatsYear.of(
      year: year,
      today: today,
      budgetId: budgetId,
      monthTotals: m,
      totals: t,
      categories: c,
    ),
  );
}
