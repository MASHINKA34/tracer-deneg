import 'package:intl/intl.dart';
import 'package:shared/shared.dart';

import '../../l10n/app_localizations.dart';
import '../month/month_picker_sheet.dart' show monthTitle;

enum SearchPeriodKind { all, month, year, custom }

typedef SearchRange = ({LocalDate? from, LocalDate? to});

final class SearchPeriod {
  const SearchPeriod._(this.kind, this.from, this.to);

  const SearchPeriod.month() : this._(SearchPeriodKind.month, null, null);

  const SearchPeriod.year() : this._(SearchPeriodKind.year, null, null);

  factory SearchPeriod.custom(LocalDate from, LocalDate to) {
    if (from > to) {
      throw ArgumentError.value(
        '$from..$to',
        'period',
        'ends before it starts',
      );
    }
    return SearchPeriod._(SearchPeriodKind.custom, from, to);
  }

  factory SearchPeriod.ofRange(
    LocalDate from,
    LocalDate to, {
    required LocalDate today,
  }) {
    final month = today.yearMonth;
    if (from == month.firstDay && to == month.lastDay) {
      return const SearchPeriod.month();
    }
    if (from == LocalDate(today.year, 1, 1) &&
        to == LocalDate(today.year, 12, 31)) {
      return const SearchPeriod.year();
    }
    return SearchPeriod.custom(from, to);
  }

  static const SearchPeriod all = SearchPeriod._(
    SearchPeriodKind.all,
    null,
    null,
  );

  final SearchPeriodKind kind;
  final LocalDate? from;
  final LocalDate? to;

  bool get isAll => kind == SearchPeriodKind.all;

  SearchRange rangeOn(LocalDate today) => switch (kind) {
    SearchPeriodKind.all => (from: null, to: null),
    SearchPeriodKind.month => (
      from: today.yearMonth.firstDay,
      to: today.yearMonth.lastDay,
    ),
    SearchPeriodKind.year => (
      from: LocalDate(today.year, 1, 1),
      to: LocalDate(today.year, 12, 31),
    ),
    SearchPeriodKind.custom => (from: from, to: to),
  };

  @override
  bool operator ==(Object other) =>
      other is SearchPeriod &&
      other.kind == kind &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(kind, from, to);

  @override
  String toString() =>
      kind == SearchPeriodKind.custom ? 'custom $from..$to' : kind.name;
}

String searchPeriodLabel(AppLocalizations l10n, LocalDate from, LocalDate to) {
  final month = from.yearMonth;
  if (from == month.firstDay && to == month.lastDay) return monthTitle(month);
  if (from == LocalDate(from.year, 1, 1) &&
      to == LocalDate(from.year, 12, 31)) {
    return l10n.searchPeriodYearChip('${from.year}');
  }
  final format = DateFormat('dd.MM.yyyy', 'ru');
  String date(LocalDate d) => format.format(DateTime(d.year, d.month, d.day));
  return l10n.searchFilterPeriod(date(from), date(to));
}

String searchPeriodChipLabel(
  AppLocalizations l10n,
  SearchPeriod period,
  LocalDate today,
) {
  if (period.isAll) return l10n.searchPeriodAll;
  final range = period.rangeOn(today);
  return searchPeriodLabel(l10n, range.from!, range.to!);
}

String searchDayTitle(LocalDate day, LocalDate today) {
  final date = DateTime(day.year, day.month, day.day);
  final pattern = day.year == today.year ? 'd MMMM' : 'd MMMM y';
  return DateFormat(pattern, 'ru').format(date);
}

typedef SearchDay = ({LocalDate day, List<Expense> expenses});

List<SearchDay> groupSearchResults(List<Expense> expenses) {
  final days = <SearchDay>[];
  for (final expense in expenses) {
    final last = days.lastOrNull;
    if (last != null && last.day == expense.spentOn) {
      last.expenses.add(expense);
    } else {
      days.add((day: expense.spentOn, expenses: [expense]));
    }
  }
  return days;
}
