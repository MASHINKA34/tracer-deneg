import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../core/clock.dart';
import '../../core/router.dart';
import '../../data/db/redact_db_error.dart';
import '../../data/providers.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/components/button.dart';
import '../../ui/components/expense_row.dart';
import '../../ui/components/fitting_text.dart';
import '../../ui/components/sheet.dart';
import '../../ui/icons/app_icon.dart';
import '../../ui/theme/app_text.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/tokens/tokens.g.dart';
import '../budgets/expense_authors.dart';
import '../expense/expense_swipe_to_delete.dart';

final _log = Logger('month');

String dayTitle(LocalDate day) {
  final text = DateFormat(
    'EEEE, d MMMM',
    'ru',
  ).format(DateTime(day.year, day.month, day.day));
  return text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';
}

String? expenseTime(Expense expense) {
  final created = expense.createdAt.toLocal();
  if (LocalDate.fromDateTime(created) != expense.spentOn) return null;
  return DateFormat.Hm('ru').format(created);
}

String? expenseSubtitle(Expense expense) {
  final time = expenseTime(expense);
  final parts = [if (expense.comment.isNotEmpty) expense.comment, ?time];
  return parts.isEmpty ? null : parts.join(' · ');
}

String spokenAmount(AppLocalizations l10n, Money amount) {
  final rubles = amount.wholeRubles;
  final kopecks = amount.kopecksPart;
  if (kopecks == 0) return l10n.a11yRubles(rubles);
  if (rubles == 0) return l10n.a11yKopecks(kopecks);
  return '${l10n.a11yRubles(rubles)} ${l10n.a11yKopecks(kopecks)}';
}

String expenseLabel(
  AppLocalizations l10n,
  Expense expense,
  String categoryName,
) => [
  categoryName,
  if (expense.comment.isNotEmpty) expense.comment,
  ?expenseTime(expense),
  spokenAmount(l10n, expense.amount),
].join(', ');

Category? expenseCategory(Expense expense, List<Category> categories) {
  Category? system;
  for (final category in categories) {
    if (category.id == expense.categoryId) return category;
    if (category.isSystem) system ??= category;
  }
  return system;
}

final class DaySummary {
  const DaySummary({
    required this.count,
    required this.total,
    required this.average,
    required this.difference,
  });

  factory DaySummary.of({
    required LocalDate day,
    required LocalDate today,
    required List<Expense> expenses,
    required Money? monthTotal,
  }) {
    final total = Money.sum([for (final e in expenses) e.amount]);
    final average = monthTotal == null
        ? null
        : averagePerDay(
            monthTotal: monthTotal,
            month: YearMonth.of(day),
            today: today,
          );
    return DaySummary(
      count: expenses.length,
      total: total,
      average: average,
      difference: average == null
          ? null
          : differenceFromAverage(daySum: total, average: average),
    );
  }

  final int count;
  final Money total;
  final Money? average;
  final Money? difference;
}

String daySummaryLine(AppLocalizations l10n, DaySummary summary) {
  final expenses = l10n.daySheetExpenses(summary.count);
  final difference = summary.difference;
  if (difference == null) return expenses;
  final amount = difference.abs;
  if (amount.roundedRubles == 0) return l10n.daySheetSame(expenses);
  return difference.isPositive
      ? l10n.daySheetMore(expenses, amount.formatTotal())
      : l10n.daySheetLess(expenses, amount.formatTotal());
}

Future<void> showDaySheet(
  BuildContext context, {
  required LocalDate day,
}) async {
  final sw = Stopwatch()..start();
  final root = Navigator.of(context, rootNavigator: true);
  await showAppSheet<void>(
    root.context,
    builder: (context) => [DaySheet(day: day)],
  );
  _log.fine(
    'day sheet closed date=$day after ${sw.elapsedMilliseconds}ms: back '
    'gesture, tap outside or swipe down',
  );
}

class DayExpenseRow extends StatelessWidget {
  const DayExpenseRow({
    super.key,
    required this.expense,
    required this.category,
    this.onTap,
    this.author,
  });

  final Expense expense;
  final Category? category;
  final VoidCallback? onTap;
  final ExpenseAuthorView? author;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final other = presetCategories.last;
    final category = this.category;
    final title = category?.name ?? other.name;
    final author = this.author;
    final label = expenseLabel(l10n, expense, title);
    return Semantics(
      button: onTap != null,
      label: author == null
          ? label
          : '$label, ${l10n.expenseRowAddedBy(expenseAuthorName(l10n, author))}',
      excludeSemantics: true,
      onTap: onTap,
      child: withAuthorColors(
        author,
        ExpenseRow(
          emoji: category?.emoji ?? other.emoji,
          color: category == null ? other.color : category.color,
          title: title,
          subtitle: expenseSubtitle(expense),
          amount: expense.amount.format(),
          author: author == null ? null : expenseRowAuthor(l10n, author),
          onTap: onTap,
        ),
      ),
    );
  }
}

class DaySheet extends ConsumerStatefulWidget {
  const DaySheet({super.key, required this.day});

  final LocalDate day;

  @override
  ConsumerState<DaySheet> createState() => _DaySheetState();
}

class _DaySheetState extends ConsumerState<DaySheet> {
  final Stopwatch _sw = Stopwatch()..start();
  final List<ProviderSubscription<Object?>> _data = [];
  final Set<String> _reportedCategories = {};
  String? _budgetId;
  bool _shown = false;

  LocalDate get _day => widget.day;

  @override
  void initState() {
    super.initState();
    ref.listenManual(
      selectedBudgetIdProvider,
      _onBudget,
      fireImmediately: true,
    );
  }

  void _onBudget(AsyncValue<String?>? previous, AsyncValue<String?> next) {
    switch (next) {
      case AsyncData(value: null):
        _closeData();
        _budgetId = null;
        _log.fine(
          'day sheet opened date=$_day without budget: no budget selected, '
          'empty day',
        );
      case AsyncData(value: final String budgetId) when budgetId != _budgetId:
        _closeData();
        _budgetId = budgetId;
        _listenData(budgetId);
      case AsyncError(:final error, :final stackTrace):
        _logFailed('unknown', 'selected budget unavailable', error, stackTrace);
      default:
    }
  }

  void _closeData() {
    for (final sub in _data) {
      sub.close();
    }
    _data.clear();
  }

  void _listenData(String budgetId) {
    final month = YearMonth.of(_day);
    _data.addAll([
      ref.listenManual<AsyncValue<List<Expense>>>(
        dayExpensesProvider((budgetId: budgetId, day: _day)),
        (previous, next) => _onExpenses(budgetId, next),
        fireImmediately: true,
      ),
      ref.listenManual<AsyncValue<List<Category>>>(
        categoriesProvider(budgetId),
        (previous, next) =>
            _onFailure(budgetId, 'categories stream failed', next),
        fireImmediately: true,
      ),
      ref.listenManual<AsyncValue<Money>>(
        monthTotalProvider((budgetId: budgetId, month: month)),
        (previous, next) => _onFailure(
          budgetId,
          'month total stream failed month=$month, no comparison with average',
          next,
        ),
        fireImmediately: true,
      ),
    ]);
  }

  void _onExpenses(String budgetId, AsyncValue<List<Expense>> next) {
    switch (next) {
      case AsyncData(value: final expenses):
        final withTime = expenses.where((e) => expenseTime(e) != null).length;
        if (_shown) {
          _log.fine(
            'day sheet data updated date=$_day budgetId=$budgetId '
            'expenses=${expenses.length} withTime=$withTime',
          );
        } else {
          _shown = true;
          _log.fine(
            'day sheet opened date=$_day budgetId=$budgetId '
            'expenses=${expenses.length} withTime=$withTime '
            'in ${_sw.elapsedMilliseconds}ms',
          );
        }
      case AsyncError(:final error, :final stackTrace):
        _logFailed(budgetId, 'day expenses stream failed', error, stackTrace);
      default:
    }
  }

  void _onFailure(String budgetId, String what, AsyncValue<Object?> next) {
    if (next case AsyncError(:final error, :final stackTrace)) {
      _logFailed(budgetId, what, error, stackTrace);
    }
  }

  void _logFailed(
    String budgetId,
    String what,
    Object error,
    StackTrace stackTrace,
  ) {
    var cause = error;
    while (cause is ProviderException) {
      cause = cause.exception;
    }
    final redacted = redactDbError(cause);
    _log.severe(
      'day sheet data failed budgetId=$budgetId date=$_day: $what: '
      '${describeError(redacted)}',
      redacted,
      stackTrace,
    );
  }

  Category? _categoryOf(
    Expense expense,
    List<Category> categories,
    String budgetId,
  ) {
    final category = expenseCategory(expense, categories);
    if (category?.id != expense.categoryId &&
        _reportedCategories.add(expense.id)) {
      _log.warning(
        'day sheet expense id=${expense.id} category=${expense.categoryId} '
        'not found among ${categories.length} categories of '
        'budgetId=$budgetId, showing it as '
        '${category == null ? 'preset other' : 'system category ${category.id}'}',
      );
    }
    return category;
  }

  void _add() {
    _log.fine(
      'day sheet add expense date=$_day → ${AppRoutes.newExpense} with '
      'date=$_day',
    );
    context.push(AppRoutes.newExpenseOn(_day));
  }

  void _open(Expense expense) {
    _log.fine(
      'day sheet expense tap id=${expense.id} date=$_day → '
      '${AppRoutes.expense}',
    );
    context.push(AppRoutes.expenseOf(expense.id));
  }

  static T? _ok<T>(AsyncValue<T>? value) =>
      value == null || value.hasError ? null : value.value;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final today = ref.watch(clockProvider).today();
    final budget = ref.watch(selectedBudgetIdProvider);
    final budgetId = _ok(budget);
    final key = budgetId == null ? null : (budgetId: budgetId, day: _day);
    final expensesValue = key == null
        ? null
        : ref.watch(dayExpensesProvider(key));
    final categoriesValue = budgetId == null
        ? null
        : ref.watch(categoriesProvider(budgetId));
    final monthTotal = budgetId == null
        ? null
        : _ok(
            ref.watch(
              monthTotalProvider((
                budgetId: budgetId,
                month: YearMonth.of(_day),
              )),
            ),
          );

    final failed =
        budget.hasError ||
        (expensesValue?.hasError ?? false) ||
        (categoriesValue?.hasError ?? false);
    final categories = _ok(categoriesValue) ?? const <Category>[];
    final authors = budgetId == null
        ? null
        : ref.watch(expenseAuthorsProvider(budgetId));
    final List<Expense>? expenses = failed
        ? null
        : budget.hasValue && budgetId == null
        ? const []
        : categoriesValue?.hasValue == true
        ? _ok(expensesValue)
        : null;
    final summary = expenses == null
        ? null
        : DaySummary.of(
            day: _day,
            today: today,
            expenses: expenses,
            monthTotal: monthTotal,
          );

    return Flexible(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Head(
              title: dayTitle(_day),
              subtitle: summary == null ? null : daySummaryLine(l10n, summary),
              total: failed ? '—' : summary?.total.formatTotal(),
            ),
            if (expenses != null && expenses.isNotEmpty) ...[
              const SizedBox(height: 16),
              Material(
                color: colors.bgSurface2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(RadiusTokens.lg),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final expense in expenses)
                      ExpenseSwipeToDelete(
                        key: ValueKey<String>(expense.id),
                        expense: expense,
                        from: 'day sheet',
                        child: DayExpenseRow(
                          expense: expense,
                          category: _categoryOf(expense, categories, budgetId!),
                          author: authors?.of(expense.authorId),
                          onTap: () => _open(expense),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              FittingText(
                l10n.daySheetHint,
                textAlign: TextAlign.center,
                style: AppText.caption.copyWith(color: colors.textTertiary),
              ),
            ],
            const SizedBox(height: 16),
            AppButton(
              label: l10n.daySheetAdd,
              onPressed: _add,
              type: AppButtonType.soft,
              icon: AppIcons.plus,
              expand: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _Head extends StatelessWidget {
  const _Head({required this.title, this.subtitle, this.total});

  final String title;
  final String? subtitle;
  final String? total;

  static const double _gap = 12;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mood = context.mood;
    final titleStyle = AppText.titleM.copyWith(color: colors.textPrimary);
    final subtitleStyle = AppText.caption.copyWith(color: colors.textTertiary);
    final totalStyle = AppText.displayS.copyWith(color: mood.accentStrong);
    final subtitle = this.subtitle;
    final total = this.total;

    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(header: true, child: FittingText(title, style: titleStyle)),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          FittingText(subtitle, style: subtitleStyle),
        ],
      ],
    );
    if (total == null) return texts;

    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: total, style: totalStyle),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        final totalWidth = painter.width;
        painter.dispose();
        var widest = FittingText.widestWord(context, title, titleStyle);
        if (subtitle != null) {
          final w = FittingText.widestWord(context, subtitle, subtitleStyle);
          if (w > widest) widest = w;
        }
        if (widest <= constraints.maxWidth - _gap - totalWidth) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: texts),
              const SizedBox(width: _gap),
              Text(total, maxLines: 1, style: totalStyle),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            texts,
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(total, maxLines: 1, style: totalStyle),
            ),
          ],
        );
      },
    );
  }
}
