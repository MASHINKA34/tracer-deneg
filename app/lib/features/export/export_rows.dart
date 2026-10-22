import 'package:intl/intl.dart';
import 'package:shared/shared.dart';

import '../../l10n/app_localizations.dart';
import '../month/day_sheet.dart' show expenseCategory;
import '../month/month_picker_sheet.dart' show monthTitle;

enum ExportPeriodKind { month, year, custom }

ExportPeriod exportPeriodOf(
  ExportPeriodKind kind,
  LocalDate today, {
  RangePeriod? custom,
}) => switch (kind) {
  ExportPeriodKind.month => MonthPeriod(today.yearMonth),
  ExportPeriodKind.year => YearPeriod(today.year),
  ExportPeriodKind.custom =>
    custom ?? RangePeriod(today.yearMonth.firstDay, today),
};

String exportMonthChip(LocalDate today) => monthTitle(today.yearMonth);

String exportYearChip(AppLocalizations l10n, LocalDate today) =>
    l10n.exportPeriodYear('${today.year}');

String exportCustomChip(AppLocalizations l10n, RangePeriod? custom) {
  if (custom == null) return l10n.exportPeriodCustom;
  final format = DateFormat('dd.MM.yyyy', 'ru');
  String date(LocalDate d) => format.format(DateTime(d.year, d.month, d.day));
  return l10n.exportPeriodRange(date(custom.from), date(custom.to));
}

String exportBudgetName(AppLocalizations l10n, Budget budget) =>
    budget.kind == BudgetKind.personal
    ? l10n.exportPersonalBudget
    : budget.name;

String exportAuthorName(
  AppLocalizations l10n,
  String authorId, {
  required String currentUserId,
  required Map<String, MemberProfile> profiles,
}) {
  final profile = profiles[authorId];
  if (profile != null) return profile.displayName;
  if (authorId == currentUserId) return l10n.exportAuthorMe;
  return l10n.exportAuthorRemoved;
}

List<CsvExpenseRow> exportRows({
  required List<Expense> expenses,
  required List<Category> categories,
  required String budgetName,
  required String Function(String authorId) authorOf,
}) {
  final other = presetCategories.last.name;
  return [
    for (final expense in expenses)
      CsvExpenseRow(
        spentOn: expense.spentOn,
        amount: expense.amount,
        category: expenseCategory(expense, categories)?.name ?? other,
        comment: expense.comment,
        budget: budgetName,
        author: authorOf(expense.authorId),
        createdAt: expense.createdAt,
      ),
  ];
}
