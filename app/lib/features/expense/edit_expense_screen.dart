import 'dart:async';

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
import '../../ui/components/category_badge.dart';
import '../../ui/components/fitting_text.dart';
import '../../ui/components/snackbar.dart';
import '../../ui/components/tap_target.dart';
import '../../ui/icons/app_icon.dart';
import '../../ui/theme/app_text.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/tokens/tokens.g.dart';
import '../month/day_sheet.dart' show expenseCategory, spokenAmount;
import 'category_grid.dart';
import 'edit_expense_controller.dart';
import 'expense_amount_sheet.dart';
import 'expense_comment_sheet.dart';
import 'expense_date_sheet.dart';
import 'expense_delete_controller.dart';

final _log = Logger('expense');

final _nav = Logger('nav');

String expenseLongDate(LocalDate date, LocalDate today) => DateFormat(
  date.year == today.year ? 'd MMMM' : 'd MMMM y',
  'ru',
).format(DateTime(date.year, date.month, date.day)).replaceAll(' ', nbsp);

String expenseLongDateLabel(
  AppLocalizations l10n,
  LocalDate date,
  LocalDate today,
) {
  final long = expenseLongDate(date, today);
  if (date == today) return l10n.newExpenseToday(long);
  if (date == today.addDays(-1)) return l10n.newExpenseYesterday(long);
  return long;
}

String _budgetName(AppLocalizations l10n, Budget budget) =>
    budget.kind == BudgetKind.personal
    ? l10n.newExpensePersonalBudget
    : budget.name;

String expenseAmountDigits(Money amount) {
  final whole = groupDigits(amount.wholeRubles);
  final kopecks = amount.kopecksPart;
  return kopecks == 0 ? whole : '$whole,${kopecks.toString().padLeft(2, '0')}';
}

class EditExpenseScreen extends ConsumerStatefulWidget {
  const EditExpenseScreen({super.key, required this.expenseId});

  final String expenseId;

  @override
  ConsumerState<EditExpenseScreen> createState() => _EditExpenseScreenState();
}

class _EditExpenseScreenState extends ConsumerState<EditExpenseScreen> {
  final Stopwatch _sinceOpen = Stopwatch()..start();
  String _closedBy = 'back';
  String? _warnedCategory;
  String? _loggedMissingRule;
  Expense? _deleted;

  String get _id => widget.expenseId;

  EditExpenseController get _controller =>
      ref.read(editExpenseControllerProvider(_id).notifier);

  @override
  void initState() {
    super.initState();
    _log.info('expense edit opened id=$_id');
    ref.listenManual(expenseProvider(_id), _logExpense, fireImmediately: true);
  }

  void _logExpense(AsyncValue<Expense?>? previous, AsyncValue<Expense?> next) {
    switch (next) {
      case AsyncData(value: final expense?):
        if (previous?.value != null) return;
        _log.fine(
          'expense edit loaded id=$_id budgetId=${expense.budgetId} '
          'category=${expense.categoryId} date=${expense.spentOn} '
          'kopecks=${expense.amount.kopecks} '
          'commentLength=${textLength(expense.comment)} '
          'in ${_sinceOpen.elapsedMilliseconds}ms',
        );
      case AsyncData() when _deleted != null:
        _log.fine(
          'expense edit id=$_id: expense deleted from this screen, keeping '
          'the form until the screen is closed',
        );
      case AsyncData():
        if (previous?.value != null) {
          _log.info(
            'expense edit id=$_id: expense was deleted while the screen was '
            'open → not found screen',
          );
        } else {
          _log.warning(
            'expense edit id=$_id: expense is not found or deleted → not '
            'found screen',
          );
        }
      case AsyncError(:final error, :final stackTrace):
        var cause = error;
        while (cause is ProviderException) {
          cause = cause.exception;
        }
        final redacted = redactDbError(cause);
        _log.severe(
          'expense edit id=$_id: reading the expense failed after '
          '${_sinceOpen.elapsedMilliseconds}ms → error screen: '
          '${describeError(redacted)}',
          redacted,
          stackTrace,
        );
      default:
    }
  }

  void _logCategories(String budgetId, AsyncValue<List<Category>> next) {
    if (next case AsyncError(:final error, :final stackTrace)) {
      var cause = error;
      while (cause is ProviderException) {
        cause = cause.exception;
      }
      final redacted = redactDbError(cause);
      _log.severe(
        'expense edit id=$_id categories failed budgetId=$budgetId, '
        'category row shows no name: ${describeError(redacted)}',
        redacted,
        stackTrace,
      );
    }
  }

  void _logBudget(String budgetId, AsyncValue<Budget?> next) {
    if (next case AsyncError(:final error, :final stackTrace)) {
      var cause = error;
      while (cause is ProviderException) {
        cause = cause.exception;
      }
      final redacted = redactDbError(cause);
      _log.warning(
        'expense edit id=$_id budget budgetId=$budgetId unavailable, budget '
        'row shows no name: ${describeError(redacted)}',
        redacted,
        stackTrace,
      );
    }
  }

  void _leave(String reason) {
    _closedBy = reason;
    if (context.canPop()) {
      context.pop();
      return;
    }
    _nav.fine(
      'expense edit id=$_id closed by $reason with nothing under it → '
      '${AppRoutes.month}',
    );
    context.go(AppRoutes.month);
  }

  void _handlePop(bool didPop, Object? result) {
    if (!didPop) return;
    _nav.fine('expense edit closed id=$_id by $_closedBy');
    if (_closedBy == 'save' || _closedBy == 'delete') return;
    final expense = ref.read(expenseProvider(_id)).value;
    if (expense == null) return;
    final changed = ref
        .read(editExpenseControllerProvider(_id))
        .changedFields(expense);
    if (changed.isEmpty) return;
    _log.fine(
      'expense edit id=$_id closed by $_closedBy with unsaved '
      'fields=${fieldNames(changed)} → changes discarded',
    );
  }

  Future<void> _editAmount(Expense expense) async {
    final edits = ref.read(editExpenseControllerProvider(_id));
    _log.fine('expense edit id=$_id amount tap → amount sheet');
    final chosen = await showExpenseAmountSheet(
      context,
      initial: edits.amountOf(expense),
    );
    if (!mounted || chosen == null) return;
    _controller.setAmount(chosen);
  }

  Future<void> _editCategory(List<Category> categories) async {
    _log.fine(
      'expense edit id=$_id category tap → sheet with '
      '${categories.length} categories',
    );
    final choice = await showAllCategoriesSheet(
      context,
      categories: categories,
    );
    if (!mounted) return;
    switch (choice) {
      case PickedCategory(:final category):
        _controller.setCategory(category.id);
      case SetupCategories():
        _log.fine(
          'categories setup from=edit expense sheet → ${AppRoutes.categories}',
        );
        context.push(AppRoutes.categories);
      case null:
        _log.fine(
          'expense edit id=$_id categories sheet closed without choice',
        );
    }
  }

  Future<void> _editDate(Expense expense) async {
    final current = ref
        .read(editExpenseControllerProvider(_id))
        .dateOf(expense);
    _log.fine('expense edit id=$_id date tap date=$current → date sheet');
    final chosen = await showExpenseDateSheet(context, initial: current);
    if (!mounted || chosen == null) return;
    _controller.setDate(chosen, by: 'date sheet');
  }

  Future<void> _editComment(Expense expense) async {
    final current = ref
        .read(editExpenseControllerProvider(_id))
        .commentOf(expense);
    _log.fine(
      'expense edit id=$_id comment tap length=${textLength(current)} → '
      'comment sheet',
    );
    final result = await showExpenseCommentSheet(
      context,
      initial: current,
      budgetId: expense.budgetId,
    );
    if (!mounted || result == null) return;
    _controller.setComment(result);
  }

  Future<void> _save(Expense expense) async {
    final result = await _controller.save(expense);
    if (!mounted) return;
    switch (result) {
      case EditExpenseSave.saved:
        _leave('save');
      case EditExpenseSave.failed:
        showAppSnackbar(
          context,
          text: AppLocalizations.of(context).expenseEditSaveFailed,
        );
      case EditExpenseSave.missing ||
          EditExpenseSave.noChanges ||
          EditExpenseSave.busy:
        break;
    }
  }

  void _delete(Expense expense, String from) {
    if (_deleted != null) {
      _log.fine(
        'expense edit id=$_id delete tap from=$from ignored: already deleting',
      );
      return;
    }
    final changed = ref
        .read(editExpenseControllerProvider(_id))
        .changedFields(expense);
    _log.fine(
      'expense edit id=$_id delete tap from=$from unsaved '
      'fields=${fieldNames(changed)} → back and delete with undo',
    );
    final deleting = ref.read(expenseDeleteProvider.notifier);
    setState(() => _deleted = expense);
    _leave('delete');
    unawaited(deleting.delete(expense, from: 'edit $from'));
  }

  Category? _categoryOf(
    Expense expense,
    String categoryId,
    AsyncValue<List<Category>> categories,
  ) {
    final list = categories.value;
    if (list == null) return null;
    final category = expenseCategory(
      expense.copyWith(categoryId: categoryId),
      list,
    );
    if (category?.id != categoryId && _warnedCategory != categoryId) {
      _warnedCategory = categoryId;
      _log.warning(
        'expense edit id=$_id category=$categoryId not found in '
        'budgetId=${expense.budgetId} → shown as '
        '${category == null ? 'no category' : 'system category ${category.id}'}',
      );
    }
    return category;
  }

  String _recurringCaption(AppLocalizations l10n, String recurringId) {
    final value = ref.watch(recurringRuleWithDeletedProvider(recurringId));
    if (value case AsyncData(value: final rule)) {
      if (rule != null && rule.deletedAt == null) {
        return l10n.expenseEditRecurringNamed(rule.title);
      }
      if (_loggedMissingRule != recurringId) {
        _loggedMissingRule = recurringId;
        _log.fine(
          'recurring rule not found for expense id=$_id '
          'recurringId=$recurringId '
          'reason=${rule == null ? 'missing' : 'deleted'} → caption without '
          'rule name',
        );
      }
    }
    return l10n.expenseEditRecurring;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final value = ref.watch(expenseProvider(_id));
    final Widget body;
    Expense? loaded;
    final deleted = _deleted;
    switch (value) {
      case _ when deleted != null:
        body = _form(context, deleted);
      case AsyncError():
        body = _MissingView(failed: true, onBack: () => _leave('back button'));
      case AsyncData(value: final expense?):
        loaded = expense;
        body = _form(context, expense);
      case AsyncData():
        body = _MissingView(failed: false, onBack: () => _leave('back button'));
      default:
        body = const SizedBox.shrink();
    }
    final current = loaded;
    return PopScope<Object?>(
      onPopInvokedWithResult: _handlePop,
      child: Scaffold(
        backgroundColor: colors.bgApp,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SafeArea(
              bottom: false,
              child: _TopBar(
                onBack: () => _leave('back button'),
                onDelete: current == null
                    ? null
                    : () => _delete(current, 'top bar'),
              ),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }

  Widget _form(BuildContext context, Expense expense) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final edits = ref.watch(editExpenseControllerProvider(_id));
    final today = ref.watch(clockProvider).today();
    final budgetId = expense.budgetId;
    ref.listen(
      categoriesProvider(budgetId),
      (previous, next) => _logCategories(budgetId, next),
    );
    ref.listen(
      budgetProvider(budgetId),
      (previous, next) => _logBudget(budgetId, next),
    );
    final categoriesValue = ref.watch(categoriesProvider(budgetId));
    final categories = categoriesValue.hasError
        ? const <Category>[]
        : categoriesValue.value ?? const <Category>[];
    final category = _categoryOf(
      expense,
      edits.categoryOf(expense),
      categoriesValue,
    );
    final budgetValue = ref.watch(budgetProvider(budgetId));
    final budget = budgetValue.hasError ? null : budgetValue.value;
    final changed = edits.changedFields(expense);
    final comment = edits.commentOf(expense);
    final recurringId = expense.recurringId;
    final bottom = MediaQuery.paddingOf(context).bottom;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AmountBlock(
            amount: edits.amountOf(expense),
            onTap: () => _editAmount(expense),
          ),
          const SizedBox(height: 16),
          Material(
            color: colors.bgSurface,
            borderRadius: BorderRadius.circular(RadiusTokens.lg),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _FieldRow(
                    label: l10n.expenseEditCategory,
                    value: category?.name ?? '',
                    badge: category,
                    padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
                    onTap: () => _editCategory(categories),
                  ),
                  _FieldRow(
                    label: l10n.expenseEditDate,
                    value: expenseLongDateLabel(
                      l10n,
                      edits.dateOf(expense),
                      today,
                    ),
                    padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
                    onTap: () => _editDate(expense),
                  ),
                  _FieldRow(
                    label: l10n.expenseEditComment,
                    value: comment,
                    padding: const EdgeInsets.fromLTRB(14, 10, 12, 18),
                    onTap: () => _editComment(expense),
                  ),
                  _FieldRow(
                    label: l10n.expenseEditBudget,
                    value: budget == null
                        ? ''
                        : '${budget.emoji} ${_budgetName(l10n, budget)}',
                    padding: const EdgeInsets.fromLTRB(14, 6, 12, 12),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (recurringId != null)
            Text(
              _recurringCaption(l10n, recurringId),
              style: AppText.caption.copyWith(color: colors.textTertiary),
            ),
          Text(
            l10n.expenseEditSyncHint,
            style: AppText.caption.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: 16),
          AppButton(
            label: l10n.expenseEditSave,
            onPressed: changed.isEmpty || edits.saving
                ? null
                : () => _save(expense),
            expand: true,
          ),
          const SizedBox(height: 16),
          AppButton(
            label: l10n.expenseEditDelete,
            type: AppButtonType.text,
            destructive: true,
            expand: true,
            onPressed: () => _delete(expense, 'button'),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onBack, required this.onDelete});

  final VoidCallback onBack;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final delete = onDelete;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            _IconButton(
              icon: AppIcons.arrowLeft,
              size: 24,
              color: colors.textPrimary,
              label: l10n.a11yBack,
              onTap: onBack,
            ),
            const SizedBox(width: 2),
            Expanded(
              child: Semantics(
                header: true,
                child: FittingText(
                  l10n.expenseTitle,
                  style: AppText.titleM.copyWith(color: colors.textPrimary),
                ),
              ),
            ),
            if (delete != null)
              _IconButton(
                icon: AppIcons.trash,
                size: 22,
                color: colors.statusDanger,
                label: l10n.expenseEditDelete,
                onTap: delete,
              ),
          ],
        ),
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.icon,
    required this.size,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final AppIcons icon;
  final double size;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: InkResponse(
        radius: 22,
        onTap: onTap,
        child: SizedBox.square(
          dimension: kMinTapTarget,
          child: Center(
            child: AppIcon(icon, size: size, color: color),
          ),
        ),
      ),
    );
  }
}

class _AmountBlock extends StatelessWidget {
  const _AmountBlock({required this.amount, required this.onTap});

  final Money amount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    return Semantics(
      button: true,
      label: l10n.expenseEditAmount,
      value: spokenAmount(l10n, amount),
      hint: l10n.expenseEditAmountHint,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        key: const ValueKey('edit-expense-amount'),
        borderRadius: BorderRadius.circular(RadiusTokens.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              Text(
                l10n.expenseEditAmount,
                style: AppText.labelS.copyWith(color: colors.textTertiary),
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      expenseAmountDigits(amount),
                      maxLines: 1,
                      style: AppText.displayXl.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      rubleSign,
                      style: AppText.displayL.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              FittingText(
                l10n.expenseEditAmountHint,
                textAlign: TextAlign.center,
                style: AppText.caption.copyWith(color: colors.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.label,
    required this.value,
    required this.padding,
    this.badge,
    this.onTap,
  });

  final String label;
  final String value;
  final EdgeInsets padding;
  final Category? badge;
  final VoidCallback? onTap;

  static const double _gap = 12;
  static const double _chevron = 18;
  static const double _badgeGap = 8;

  double _width(BuildContext context, String text, TextStyle style) {
    if (text.isEmpty) return 0;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: DefaultTextStyle.of(context).style.merge(style),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final labelStyle = AppText.bodyM.copyWith(color: colors.textSecondary);
    final valueStyle = AppText.labelM.copyWith(color: colors.textPrimary);
    final category = badge;
    final semantics = value.isEmpty ? label : '$label, $value';
    return Semantics(
      button: onTap != null,
      label: semantics,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: onTap == null ? 0 : kMinTapTarget,
          ),
          child: Padding(
            padding: padding,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final room = constraints.maxWidth - _gap - _chevron;
                final valueWidth =
                    _width(context, value, valueStyle) +
                    (category == null
                        ? 0
                        : CategoryBadge.size + (value.isEmpty ? 0 : _badgeGap));
                final labelWidth = _width(context, label, labelStyle);
                final oneLine =
                    labelWidth + (valueWidth == 0 ? 0 : _gap + valueWidth) <=
                    room;
                final valueWidget = _value(
                  category,
                  valueStyle,
                  oneLine ? TextAlign.end : TextAlign.start,
                );
                final Widget content;
                if (oneLine) {
                  content = Row(
                    children: [
                      Text(label, style: labelStyle),
                      const SizedBox(width: _gap),
                      Expanded(
                        child: Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: valueWidget,
                        ),
                      ),
                    ],
                  );
                } else {
                  content = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittingText(label, style: labelStyle),
                      if (valueWidth > 0) ...[
                        const SizedBox(height: 2),
                        valueWidget,
                      ],
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: content),
                    const SizedBox(width: _gap),
                    AppIcon(
                      AppIcons.chevronRight,
                      size: _chevron,
                      color: colors.textTertiary,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _value(Category? category, TextStyle style, TextAlign align) {
    final text = value.isEmpty
        ? null
        : FittingText(value, style: style, textAlign: align);
    if (category == null) return text ?? const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CategoryBadge(emoji: category.emoji, color: category.color),
        if (text != null) ...[
          const SizedBox(width: _badgeGap),
          Flexible(child: text),
        ],
      ],
    );
  }
}

class _MissingView extends StatelessWidget {
  const _MissingView({required this.failed, required this.onBack});

  final bool failed;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              header: true,
              child: FittingText(
                failed ? l10n.expenseLoadFailedTitle : l10n.expenseMissingTitle,
                textAlign: TextAlign.center,
                style: AppText.titleM.copyWith(color: colors.textPrimary),
              ),
            ),
            const SizedBox(height: 8),
            FittingText(
              failed ? l10n.expenseLoadFailedText : l10n.expenseMissingText,
              textAlign: TextAlign.center,
              style: AppText.bodyM.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: 24),
            AppButton(
              label: l10n.expenseMissingBack,
              type: AppButtonType.soft,
              onPressed: onBack,
            ),
          ],
        ),
      ),
    );
  }
}
