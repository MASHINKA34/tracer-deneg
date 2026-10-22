import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../core/clock.dart';
import '../../core/router.dart';
import '../../data/db/redact_db_error.dart';
import '../../data/providers.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/components/button.dart';
import '../../ui/components/category_badge.dart';
import '../../ui/components/dialog.dart';
import '../../ui/components/fitting_text.dart';
import '../../ui/components/snackbar.dart';
import '../../ui/components/text_field.dart';
import '../../ui/icons/app_icon.dart';
import '../../ui/theme/app_text.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/tokens/tokens.g.dart';
import '../categories/categories_top_bar.dart';
import '../expense/category_grid.dart';
import '../expense/edit_expense_screen.dart' show expenseLongDate;
import '../expense/expense_amount_sheet.dart';
import '../month/day_sheet.dart' show spokenAmount;
import 'recurring_day_sheet.dart';
import 'recurring_editor_controller.dart';

final _log = Logger('recurring');

final _nav = Logger('nav');

const double recurringEditorGap = 14;

const int recurringShortMonthsFrom = 29;

String recurringTitleErrorText(AppLocalizations l10n, ValidationError error) =>
    switch (error) {
      ValidationError.recurringTitleTooLong => l10n.recurringTitleTooLong(
        recurringTitleMaxLength,
      ),
      _ => l10n.recurringTitleEmpty,
    };

String recurringFirstChargeText(
  AppLocalizations l10n,
  int dayOfMonth,
  LocalDate today,
) {
  final first = firstChargeOfNewRule(dayOfMonth, today);
  final date = expenseLongDate(first, today);
  return first == today
      ? l10n.recurringFirstChargeToday(date)
      : l10n.recurringFirstCharge(date);
}

String recurringDayHint(AppLocalizations l10n, int dayOfMonth) =>
    dayOfMonth < recurringShortMonthsFrom
    ? l10n.recurringEditorHint
    : '${l10n.recurringEditorHint} '
          '${l10n.recurringEditorShortMonths('$dayOfMonth')}';

class RecurringEditorScreen extends ConsumerStatefulWidget {
  const RecurringEditorScreen({super.key, this.ruleId});

  final String? ruleId;

  @override
  ConsumerState<RecurringEditorScreen> createState() =>
      _RecurringEditorScreenState();
}

class _RecurringEditorScreenState extends ConsumerState<RecurringEditorScreen> {
  final Stopwatch _sinceOpen = Stopwatch()..start();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  final FocusNode _amountFocus = FocusNode(
    debugLabel: 'recurring amount',
    canRequestFocus: false,
  );
  String _closedBy = 'back';
  bool _filled = false;
  String? _warnedCategory;
  RecurringRule? _deleting;

  String? get _id => widget.ruleId;

  String get _target => _id == null ? 'new' : 'id=$_id';

  RecurringEditorController get _controller =>
      ref.read(recurringEditorControllerProvider(_id).notifier);

  @override
  void initState() {
    super.initState();
    _log.fine('recurring editor opened $_target');
    final id = _id;
    if (id == null) {
      _filled = true;
      return;
    }
    ref.listenManual(
      recurringRuleWithDeletedProvider(id),
      _onRule,
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _amountFocus.dispose();
    super.dispose();
  }

  Object _unwrap(Object error) {
    var cause = error;
    while (cause is ProviderException) {
      cause = cause.exception;
    }
    return cause;
  }

  void _onRule(
    AsyncValue<RecurringRule?>? previous,
    AsyncValue<RecurringRule?> next,
  ) {
    final before = previous?.value;
    switch (next) {
      case AsyncData(value: final rule?) when !rule.isDeleted:
        if (!_filled) {
          _filled = true;
          _title.text = rule.title;
          _amount.text = rule.amount.format();
        }
        if (before != null && !before.isDeleted) return;
        _log.fine(
          'recurring editor loaded $_target budgetId=${rule.budgetId} '
          'category=${rule.categoryId} day=${rule.dayOfMonth} '
          'from=${rule.startMonth} kopecks=${rule.amount.kopecks} '
          'titleLength=${textLength(rule.title)} '
          'in ${_sinceOpen.elapsedMilliseconds}ms',
        );
      case AsyncData() when _deleting != null:
        _log.fine(
          'recurring editor $_target: rule deleted from this screen, keeping '
          'the form until the screen is closed',
        );
      case AsyncData():
        if (before != null && !before.isDeleted) {
          _log.info(
            'recurring editor $_target: rule was deleted while the screen was '
            'open → not found screen',
          );
        } else {
          _log.warning(
            'recurring editor $_target: rule is '
            '${next.value == null ? 'not found' : 'deleted'} → not found '
            'screen',
          );
        }
      case AsyncError(:final error, :final stackTrace):
        final redacted = redactDbError(_unwrap(error));
        _log.severe(
          'recurring editor $_target: reading the rule failed after '
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
      final redacted = redactDbError(_unwrap(error));
      _log.severe(
        'recurring editor $_target categories failed budgetId=$budgetId, '
        'category row shows no name: ${describeError(redacted)}',
        redacted,
        stackTrace,
      );
    }
  }

  void _logBudget(String budgetId, AsyncValue<Budget?> next) {
    if (next case AsyncError(:final error, :final stackTrace)) {
      final redacted = redactDbError(_unwrap(error));
      _log.warning(
        'recurring editor $_target budget budgetId=$budgetId unavailable, '
        'budget row shows no name: ${describeError(redacted)}',
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
      'recurring editor $_target closed by $reason with nothing under it → '
      '${AppRoutes.recurring}',
    );
    context.go(AppRoutes.recurring);
  }

  void _handlePop(bool didPop, Object? result) {
    if (!didPop) return;
    _nav.fine('recurring editor closed $_target by $_closedBy');
    if (_closedBy == 'save' || _closedBy == 'delete') return;
    final id = _id;
    final draft = ref.read(recurringEditorControllerProvider(id));
    final original = id == null
        ? null
        : ref.read(recurringRuleWithDeletedProvider(id)).value;
    final changed = original == null
        ? [
            if (draft.title != null) RecurringField.title,
            if (draft.amount != null) RecurringField.amount,
            if (draft.categoryId != null) RecurringField.category,
            if (draft.day != null) RecurringField.day,
          ]
        : draft.changedFields(original);
    if (changed.isEmpty) return;
    _log.fine(
      'recurring editor $_target closed by $_closedBy with unsaved '
      'fields=${recurringFieldNames(changed)} → changes discarded',
    );
  }

  Future<void> _editAmount(RecurringRule? original) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final current = ref
        .read(recurringEditorControllerProvider(_id))
        .amountOf(original);
    _log.fine('recurring edit $_target amount tap → amount sheet');
    final chosen = await showExpenseAmountSheet(context, initial: current);
    if (!mounted || chosen == null) return;
    if (_controller.setAmount(chosen)) _amount.text = chosen.format();
  }

  Future<void> _editCategory(List<Category> categories) async {
    FocusManager.instance.primaryFocus?.unfocus();
    _log.fine(
      'recurring edit $_target category tap → sheet with '
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
          'categories setup from=recurring editor sheet → '
          '${AppRoutes.categories}',
        );
        context.push(AppRoutes.categories);
      case null:
        _log.fine(
          'recurring edit $_target categories sheet closed without choice',
        );
    }
  }

  Future<void> _editDay(RecurringRule? original) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final today = ref.read(clockProvider).today();
    final current = ref
        .read(recurringEditorControllerProvider(_id))
        .dayOf(original, today);
    _log.fine('recurring edit $_target day tap day=$current → day sheet');
    final chosen = await showRecurringDaySheet(context, initial: current);
    if (!mounted || chosen == null) return;
    _controller.setDay(chosen);
  }

  Future<void> _save(RecurringRule? original, String? budgetId) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final result = await _controller.save(original, budgetId: budgetId);
    if (!mounted) return;
    switch (result) {
      case RecurringSave.saved || RecurringSave.noChanges:
        _leave('save');
      case RecurringSave.failed:
        showAppSnackbar(
          context,
          text: AppLocalizations.of(context).recurringSaveFailed,
        );
      case RecurringSave.missing when original == null:
        showAppSnackbar(
          context,
          text: AppLocalizations.of(context).recurringSaveFailed,
        );
      case RecurringSave.invalid || RecurringSave.busy || RecurringSave.missing:
        break;
    }
  }

  Future<void> _delete(RecurringRule rule) async {
    if (_deleting != null ||
        ref.read(recurringEditorControllerProvider(_id)).busy) {
      _log.fine('recurring delete tap $_target ignored: already in progress');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    _log.fine('recurring delete tap $_target → confirm dialog');
    final l10n = AppLocalizations.of(context);
    final confirmed = await showAppDialog<bool>(
      context,
      builder: (context) => AppDialog(
        title: l10n.recurringDeleteTitle,
        message: l10n.recurringDeleteMessage(rule.title),
        primary: AppDialogAction(
          l10n.recurringDeleteConfirm,
          () => Navigator.of(context).pop(true),
          destructive: true,
        ),
        secondary: AppDialogAction(
          l10n.recurringDeleteCancel,
          () => Navigator.of(context).pop(false),
        ),
      ),
    );
    if (!mounted) return;
    if (confirmed != true) {
      _log.fine(
        'recurring delete $_target dialog '
        '${confirmed == null ? 'dismissed' : '→ cancel'}: nothing deleted',
      );
      return;
    }
    setState(() => _deleting = rule);
    final result = await _controller.delete(rule);
    if (!mounted) return;
    switch (result) {
      case RecurringDelete.deleted:
        _leave('delete');
      case RecurringDelete.failed:
        setState(() => _deleting = null);
        showAppSnackbar(context, text: l10n.recurringDeleteFailed);
      case RecurringDelete.busy || RecurringDelete.missing:
        setState(() => _deleting = null);
    }
  }

  Category? _categoryOf(
    String? categoryId,
    String budgetId,
    List<Category>? categories,
  ) {
    if (categoryId == null || categories == null) return null;
    for (final category in categories) {
      if (category.id == categoryId) return category;
    }
    Category? system;
    for (final category in categories) {
      if (category.isSystem) system = category;
    }
    if (_warnedCategory != categoryId) {
      _warnedCategory = categoryId;
      _log.warning(
        'recurring editor $_target category=$categoryId not found in '
        'budgetId=$budgetId → shown as '
        '${system == null ? 'no category' : 'system category ${system.id}'}',
      );
    }
    return system;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final id = _id;
    final Widget body;
    if (id == null) {
      body = _form(context, null, ref.watch(selectedBudgetIdProvider).value);
    } else {
      final deleting = _deleting;
      switch (ref.watch(recurringRuleWithDeletedProvider(id))) {
        case _ when deleting != null:
          body = _form(context, deleting, deleting.budgetId);
        case AsyncError():
          body = _MessageView(
            title: l10n.recurringLoadFailedTitle,
            text: l10n.recurringLoadFailedText,
            onBack: () => _leave('back button'),
          );
        case AsyncData(value: final rule?) when !rule.isDeleted:
          body = _form(context, rule, rule.budgetId);
        case AsyncData():
          body = _MessageView(
            title: l10n.recurringMissingTitle,
            text: l10n.recurringMissingText,
            onBack: () => _leave('back button'),
          );
        default:
          body = const SizedBox.shrink();
      }
    }
    return PopScope<Object?>(
      onPopInvokedWithResult: _handlePop,
      child: Scaffold(
        backgroundColor: colors.bgApp,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SafeArea(
              bottom: false,
              child: CategoriesTopBar(
                title: id == null
                    ? l10n.recurringNewTitle
                    : l10n.recurringEditorTitle,
                onBack: () => _leave('back button'),
              ),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }

  Widget _form(
    BuildContext context,
    RecurringRule? original,
    String? budgetId,
  ) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final draft = ref.watch(recurringEditorControllerProvider(_id));
    final today = ref.watch(clockProvider).today();
    final day = draft.dayOf(original, today);
    final amount = draft.amountOf(original);
    final titleError = draft.visibleTitleError(original);
    final amountError = draft.visibleAmountError(original);
    final categoryMissing = draft.visibleCategoryMissing(original);
    final bottom = MediaQuery.paddingOf(context).bottom;

    List<Category>? categories;
    Category? category;
    Budget? budget;
    if (budgetId != null) {
      ref.listen(
        categoriesProvider(budgetId),
        (previous, next) => _logCategories(budgetId, next),
      );
      ref.listen(
        budgetProvider(budgetId),
        (previous, next) => _logBudget(budgetId, next),
      );
      final categoriesValue = ref.watch(categoriesProvider(budgetId));
      categories = categoriesValue.hasError ? null : categoriesValue.value;
      category = _categoryOf(draft.categoryOf(original), budgetId, categories);
      final budgetValue = ref.watch(budgetProvider(budgetId));
      budget = budgetValue.hasError ? null : budgetValue.value;
    }
    final pickable = categories ?? const <Category>[];

    final String categoryValue;
    final Color categoryColor;
    if (category != null) {
      categoryValue = category.name;
      categoryColor = colors.textPrimary;
    } else if (categoryMissing) {
      categoryValue = l10n.recurringCategoryEmpty;
      categoryColor = colors.statusDanger;
    } else if (draft.categoryOf(original) == null) {
      categoryValue = l10n.recurringEditorNoCategory;
      categoryColor = colors.textTertiary;
    } else {
      categoryValue = '';
      categoryColor = colors.textPrimary;
    }

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            label: l10n.recurringEditorName,
            controller: _title,
            errorText: titleError == null
                ? null
                : recurringTitleErrorText(l10n, titleError),
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.done,
            onChanged: _controller.setTitle,
          ),
          const SizedBox(height: recurringEditorGap),
          Semantics(
            button: true,
            label: l10n.recurringEditorAmount,
            value: amount.kopecks == 0 ? null : spokenAmount(l10n, amount),
            hint: amountError == null ? null : l10n.recurringAmountEmpty,
            excludeSemantics: true,
            onTap: () => _editAmount(original),
            child: AppTextField(
              key: const ValueKey('recurring-amount'),
              label: l10n.recurringEditorAmount,
              controller: _amount,
              focusNode: _amountFocus,
              readOnly: true,
              errorText: amountError == null ? null : l10n.recurringAmountEmpty,
              onTap: () => _editAmount(original),
            ),
          ),
          const SizedBox(height: recurringEditorGap),
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
                    label: l10n.recurringEditorCategory,
                    value: categoryValue,
                    valueColor: categoryColor,
                    badge: category,
                    minHeight: CategoryBadge.size,
                    padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                    onTap: () => _editCategory(pickable),
                  ),
                  _FieldRow(
                    label: l10n.recurringEditorDay,
                    value: l10n.recurringEditorDayValue(day),
                    padding: const EdgeInsets.fromLTRB(14, 12, 12, 16),
                    onTap: () => _editDay(original),
                  ),
                  _FieldRow(
                    label: l10n.recurringEditorBudget,
                    value: budget == null ? '' : _budgetLabel(l10n, budget),
                    padding: const EdgeInsets.fromLTRB(14, 8, 12, 12),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: recurringEditorGap),
          if (original == null) ...[
            Text(
              recurringFirstChargeText(l10n, day, today),
              style: AppText.caption.copyWith(color: colors.textTertiary),
            ),
            const SizedBox(height: 4),
          ],
          Text(
            recurringDayHint(l10n, day),
            style: AppText.caption.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: recurringEditorGap),
          AppButton(
            label: l10n.recurringEditorSave,
            expand: true,
            onPressed: draft.busy || _deleting != null
                ? null
                : () => _save(original, budgetId),
          ),
          if (original != null) ...[
            const SizedBox(height: recurringEditorGap),
            AppButton(
              label: l10n.recurringEditorDelete,
              type: AppButtonType.text,
              destructive: true,
              expand: true,
              onPressed: () => _delete(original),
            ),
            const SizedBox(height: recurringEditorGap),
            Text(
              l10n.recurringEditorKeepHint,
              style: AppText.caption.copyWith(color: colors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

String _budgetLabel(AppLocalizations l10n, Budget budget) {
  final name = budget.kind == BudgetKind.personal
      ? l10n.newExpensePersonalBudget
      : budget.name;
  return '${budget.emoji} $name';
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.label,
    required this.value,
    required this.padding,
    this.valueColor,
    this.badge,
    this.minHeight = 0,
    this.onTap,
  });

  final String label;
  final String value;
  final EdgeInsets padding;
  final double minHeight;
  final Color? valueColor;
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
    final valueStyle = AppText.labelM.copyWith(
      color: valueColor ?? colors.textPrimary,
    );
    final category = badge;
    final semantics = value.isEmpty ? label : '$label, $value';
    return Semantics(
      button: onTap != null,
      label: semantics,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
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
              return ConstrainedBox(
                constraints: BoxConstraints(minHeight: minHeight),
                child: Row(
                  children: [
                    Expanded(child: content),
                    const SizedBox(width: _gap),
                    AppIcon(
                      AppIcons.chevronRight,
                      size: _chevron,
                      color: colors.textTertiary,
                    ),
                  ],
                ),
              );
            },
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

class _MessageView extends StatelessWidget {
  const _MessageView({
    required this.title,
    required this.text,
    required this.onBack,
  });

  final String title;
  final String text;
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
                title,
                textAlign: TextAlign.center,
                style: AppText.titleM.copyWith(color: colors.textPrimary),
              ),
            ),
            const SizedBox(height: 8),
            FittingText(
              text,
              textAlign: TextAlign.center,
              style: AppText.bodyM.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: 24),
            AppButton(
              label: l10n.recurringBack,
              type: AppButtonType.soft,
              onPressed: onBack,
            ),
          ],
        ),
      ),
    );
  }
}
