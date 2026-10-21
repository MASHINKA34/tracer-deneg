import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../core/router.dart';
import '../../data/db/redact_db_error.dart';
import '../../data/providers.dart';
import '../../data/queries/today_queries.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/components/button.dart';
import '../../ui/components/fitting_text.dart';
import '../../ui/theme/app_text.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/tokens/tokens.g.dart';
import '../expense/expense_swipe_to_delete.dart';
import 'day_sheet.dart';

final _log = Logger('month');

String todayDate(LocalDate day) =>
    DateFormat('d MMMM', 'ru').format(DateTime(day.year, day.month, day.day));

class TodayBlock extends ConsumerStatefulWidget {
  const TodayBlock({super.key, required this.today});

  final LocalDate today;

  @override
  ConsumerState<TodayBlock> createState() => _TodayBlockState();
}

typedef _Shown = ({bool empty, int count});

class _TodayBlockState extends ConsumerState<TodayBlock> {
  Stopwatch _sw = Stopwatch()..start();
  final List<ProviderSubscription<Object?>> _data = [];
  final Set<String> _reportedCategories = {};
  String? _budgetId;
  _Shown? _shown;

  LocalDate get _day => widget.today;

  @override
  void initState() {
    super.initState();
    ref.listenManual(
      selectedBudgetIdProvider,
      _onBudget,
      fireImmediately: true,
    );
  }

  @override
  void didUpdateWidget(covariant TodayBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.today == widget.today) return;
    _log.fine('today block date ${oldWidget.today} → ${widget.today}');
    _closeData();
    _shown = null;
    _sw = Stopwatch()..start();
    final budgetId = _budgetId;
    if (budgetId != null) _listenData(budgetId);
  }

  void _onBudget(AsyncValue<String?>? previous, AsyncValue<String?> next) {
    switch (next) {
      case AsyncData(value: null):
        _closeData();
        _budgetId = null;
        _shown = null;
        _log.fine(
          'today block empty state shown date=$_day without budget: no '
          'budget selected, first expense hint and button',
        );
      case AsyncData(value: final String budgetId) when budgetId != _budgetId:
        _closeData();
        _budgetId = budgetId;
        _shown = null;
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
    _data.addAll([
      ref.listenManual<AsyncValue<TodayExpenses>>(
        todayExpensesProvider((budgetId: budgetId, day: _day)),
        (previous, next) => _onToday(budgetId, next),
        fireImmediately: true,
      ),
      ref.listenManual<AsyncValue<List<Category>>>(
        categoriesProvider(budgetId),
        (previous, next) =>
            _onFailure(budgetId, 'categories stream failed', next),
        fireImmediately: true,
      ),
    ]);
  }

  void _onToday(String budgetId, AsyncValue<TodayExpenses> next) {
    switch (next) {
      case AsyncData(value: final today):
        final shown = (
          empty: !today.budgetHasExpenses,
          count: today.expenses.length,
        );
        final previous = _shown;
        if (previous == shown) return;
        _shown = shown;
        final count = today.expenses.length;
        if (shown.empty) {
          _log.fine(
            'today block empty state shown date=$_day budgetId=$budgetId: '
            'no expenses in budget yet, first expense hint and button'
            '${previous == null ? ' in ${_sw.elapsedMilliseconds}ms' : ''}',
          );
        } else if (previous == null) {
          final withTime = today.expenses
              .where((e) => expenseTime(e) != null)
              .length;
          _log.fine(
            'today block shown date=$_day budgetId=$budgetId '
            'expenses=$count withTime=$withTime'
            '${count == 0 ? ': no expenses today, budget has earlier ones' : ''}'
            ' in ${_sw.elapsedMilliseconds}ms',
          );
        } else {
          _log.fine(
            'today block updated date=$_day budgetId=$budgetId '
            'expenses=${previous.count} → $count'
            '${previous.empty ? ', empty state left: budget has expenses' : ''}',
          );
        }
      case AsyncError(:final error, :final stackTrace):
        _logFailed(budgetId, 'today expenses stream failed', error, stackTrace);
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
      'today block data failed budgetId=$budgetId date=$_day: $what, '
      'showing «—» without list: ${describeError(redacted)}',
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
        'today block expense id=${expense.id} category=${expense.categoryId} '
        'not found among ${categories.length} categories of '
        'budgetId=$budgetId, showing it as '
        '${category == null ? 'preset other' : 'system category ${category.id}'}',
      );
    }
    return category;
  }

  void _open(Expense expense) {
    _log.fine(
      'today expense tap id=${expense.id} date=$_day → ${AppRoutes.expense}',
    );
    context.push(AppRoutes.expenseOf(expense.id));
  }

  void _addFirst() {
    _log.fine('today block add first expense → ${AppRoutes.newExpense}');
    context.pushNamed(AppRoutes.newExpenseName);
  }

  static T? _ok<T>(AsyncValue<T>? value) =>
      value == null || value.hasError ? null : value.value;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final budget = ref.watch(selectedBudgetIdProvider);
    final budgetId = _ok(budget);
    final todayValue = budgetId == null
        ? null
        : ref.watch(todayExpensesProvider((budgetId: budgetId, day: _day)));
    final categoriesValue = budgetId == null
        ? null
        : ref.watch(categoriesProvider(budgetId));
    final title = l10n.todayTitle(todayDate(_day));

    if (budget.hasError ||
        (todayValue?.hasError ?? false) ||
        (categoriesValue?.hasError ?? false)) {
      return _TodayHead(title: title, total: '—');
    }
    if (!budget.hasValue) return const SizedBox.shrink();
    if (budgetId == null) {
      return _TodayView(
        title: title,
        total: Money.zero,
        child: _FirstExpense(onAdd: _addFirst),
      );
    }
    final today = _ok(todayValue);
    final categories = _ok(categoriesValue);
    if (today == null || categories == null) return const SizedBox.shrink();

    if (!today.budgetHasExpenses) {
      return _TodayView(
        title: title,
        total: Money.zero,
        child: _FirstExpense(onAdd: _addFirst),
      );
    }
    final expenses = today.expenses;
    if (expenses.isEmpty) {
      return _TodayView(title: title, total: Money.zero, child: const _None());
    }
    return _TodayView(
      title: title,
      total: Money.sum([for (final e in expenses) e.amount]),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            for (final expense in expenses)
              ExpenseSwipeToDelete(
                key: ValueKey<String>(expense.id),
                expense: expense,
                from: 'today',
                child: DayExpenseRow(
                  expense: expense,
                  category: _categoryOf(expense, categories, budgetId),
                  onTap: () => _open(expense),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TodayView extends StatelessWidget {
  const _TodayView({
    required this.title,
    required this.total,
    required this.child,
  });

  final String title;
  final Money total;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _TodayHead(title: title, total: total.formatTotal()),
        const SizedBox(height: 10),
        Material(
          color: context.colors.bgSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(RadiusTokens.lg),
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ],
    );
  }
}

class _TodayHead extends StatelessWidget {
  const _TodayHead({required this.title, required this.total});

  final String title;
  final String total;

  static const double _gap = 12;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: FittingText(
                title,
                style: AppText.titleS.copyWith(color: colors.textPrimary),
              ),
            ),
          ),
          const SizedBox(width: _gap),
          Text(
            total,
            maxLines: 1,
            style: AppText.labelM.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _FirstExpense extends StatelessWidget {
  const _FirstExpense({required this.onAdd});

  final VoidCallback onAdd;

  static const String _wave = '👋';

  static const double _padding = 20;

  static const double _gap = 10;

  static const double _buttonHeight = 40;

  static const double _buttonSlack =
      (kMinInteractiveDimension - _buttonHeight) / 2;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        _padding,
        _padding,
        _padding,
        _padding - _buttonSlack,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: Text(
              _wave,
              style: AppText.displayL.copyWith(color: colors.textPrimary),
            ),
          ),
          const SizedBox(height: _gap),
          FittingText(
            l10n.todayFirstHint,
            textAlign: TextAlign.center,
            style: AppText.bodyM.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: _gap - _buttonSlack),
          AppButton(
            label: l10n.todayFirstAdd,
            onPressed: onAdd,
            type: AppButtonType.soft,
            size: AppButtonSize.m,
          ),
        ],
      ),
    );
  }
}

class _None extends StatelessWidget {
  const _None();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: FittingText(
        AppLocalizations.of(context).todayNone,
        textAlign: TextAlign.center,
        style: AppText.bodyM.copyWith(color: context.colors.textSecondary),
      ),
    );
  }
}
