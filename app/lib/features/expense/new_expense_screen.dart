import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../ui/components/category_tile.dart';
import '../../ui/components/chip.dart';
import '../../ui/components/dialog.dart';
import '../../ui/components/fitting_text.dart';
import '../../ui/components/keypad_key.dart';
import '../../ui/components/snackbar.dart';
import '../../ui/components/tap_target.dart';
import '../../ui/icons/app_icon.dart';
import '../../ui/theme/app_text.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/tokens/tokens.g.dart';
import '../month/day_sheet.dart' show spokenAmount;
import 'category_grid.dart';
import 'new_expense_controller.dart';

final _log = Logger('expense');

final _nav = Logger('nav');

const Duration caretBlinkInterval = Duration(milliseconds: 530);

const Duration amountShakeDuration = Duration(milliseconds: 420);

const int newExpenseGridCategories = 7;

String shortExpenseDate(LocalDate date, LocalDate today) {
  final pattern = date.year == today.year ? 'd MMM' : 'd MMM y';
  return DateFormat(
    pattern,
    'ru',
  ).format(DateTime(date.year, date.month, date.day)).replaceAll('.', '');
}

String expenseDateLabel(
  AppLocalizations l10n,
  LocalDate date,
  LocalDate today,
) {
  final short = shortExpenseDate(date, today);
  if (date == today) return l10n.newExpenseToday(short);
  if (date == today.addDays(-1)) return l10n.newExpenseYesterday(short);
  return short;
}

class NewExpenseScreen extends ConsumerStatefulWidget {
  const NewExpenseScreen({super.key, this.date});

  final String? date;

  @override
  ConsumerState<NewExpenseScreen> createState() => _NewExpenseScreenState();
}

class _NewExpenseScreenState extends ConsumerState<NewExpenseScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: amountShakeDuration,
  );
  Timer? _blink;
  bool _caretOn = true;
  bool _animate = true;
  String _closedBy = 'back';
  bool _leaving = false;
  bool _needAmount = false;

  NewExpenseController get _controller =>
      ref.read(newExpenseControllerProvider(widget.date).notifier);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animate = !MediaQuery.disableAnimationsOf(context);
    if (animate != _animate || _blink == null && animate) {
      _animate = animate;
      _caretOn = true;
      _startBlink();
    }
  }

  @override
  void dispose() {
    _blink?.cancel();
    _shake.dispose();
    super.dispose();
  }

  void _startBlink() {
    _blink?.cancel();
    _blink = null;
    if (!_animate) return;
    _blink = Timer.periodic(caretBlinkInterval, (_) {
      if (mounted) setState(() => _caretOn = !_caretOn);
    });
  }

  void _restartCaret() {
    if (!_caretOn) setState(() => _caretOn = true);
    _startBlink();
  }

  void _shakeAmount() {
    if (!_animate) return;
    _shake.forward(from: 0);
  }

  void _press(bool Function(NewExpenseController c) key, {bool shake = true}) {
    HapticFeedback.lightImpact();
    if (key(_controller)) {
      final input = ref.read(newExpenseControllerProvider(widget.date)).input;
      if (_needAmount && input.canSave) setState(() => _needAmount = false);
      _restartCaret();
    } else if (shake) {
      _shakeAmount();
    }
  }

  Future<void> _pick(Category category, {required String from}) async {
    final result = await _controller.save(category);
    if (!mounted) return;
    switch (result) {
      case NewExpenseSave.saved:
        HapticFeedback.lightImpact();
        _leave('save');
      case NewExpenseSave.zeroAmount:
        _log.fine(
          'category tap from=$from category=${category.id} with zero amount → '
          'shake and hint',
        );
        setState(() => _needAmount = true);
        _shakeAmount();
      case NewExpenseSave.failed || NewExpenseSave.noBudget:
        showAppSnackbar(
          context,
          text: AppLocalizations.of(context).newExpenseSaveFailed,
        );
      case NewExpenseSave.busy:
        break;
    }
  }

  Future<void> _openAll(List<Category> categories) async {
    _log.fine(
      'category tile «all» → sheet with ${categories.length} categories',
    );
    final choice = await showAllCategoriesSheet(
      context,
      categories: categories,
    );
    if (!mounted) return;
    switch (choice) {
      case PickedCategory(:final category):
        await _pick(category, from: 'all sheet');
      case SetupCategories():
        _openSetup(from: 'all sheet');
      case null:
        _log.fine('all categories sheet closed without choice');
    }
  }

  void _openSetup({required String from}) {
    _log.fine('categories setup from=$from → ${AppRoutes.categories}');
    context.push(AppRoutes.categories);
  }

  void _logCategories(String budgetId, AsyncValue<List<Category>> next) {
    switch (next) {
      case AsyncData(value: final categories):
        _log.fine(
          'new expense categories budgetId=$budgetId '
          'total=${categories.length} '
          'grid=${math.min(categories.length, newExpenseGridCategories)} + all',
        );
      case AsyncError(:final error, :final stackTrace):
        var cause = error;
        while (cause is ProviderException) {
          cause = cause.exception;
        }
        final redacted = redactDbError(cause);
        _log.severe(
          'new expense categories failed budgetId=$budgetId, grid shows only '
          '«all»: ${describeError(redacted)}',
          redacted,
          stackTrace,
        );
      default:
    }
  }

  void _leave(String reason) {
    _closedBy = reason;
    setState(() => _leaving = true);
    if (context.canPop()) {
      context.pop();
      return;
    }
    _nav.fine(
      'new expense closed by $reason with nothing under it → '
      '${AppRoutes.month}',
    );
    context.go(AppRoutes.month);
  }

  void _close() {
    final input = ref.read(newExpenseControllerProvider(widget.date)).input;
    if (input.isEmpty) {
      _leave('close button');
      return;
    }
    _confirmDiscard('close button');
  }

  void _handlePop(bool didPop, Object? result) {
    if (didPop) {
      _nav.fine('new expense closed by $_closedBy');
      return;
    }
    _confirmDiscard('back');
  }

  Future<void> _confirmDiscard(String source) async {
    _log.fine(
      'new expense close by $source with amount entered → '
      'discard dialog',
    );
    final l10n = AppLocalizations.of(context);
    final discard = await showAppDialog<bool>(
      context,
      builder: (context) => AppDialog(
        title: l10n.newExpenseDiscardTitle,
        primary: AppDialogAction(
          l10n.newExpenseDiscard,
          () => Navigator.of(context).pop(true),
          destructive: true,
        ),
        secondary: AppDialogAction(
          l10n.newExpenseStay,
          () => Navigator.of(context).pop(false),
        ),
      ),
    );
    if (!mounted) return;
    if (discard ?? false) {
      _log.fine(
        'new expense discarded by $source: amount dropped, nothing saved',
      );
      _leave(source);
      return;
    }
    _log.fine(
      'new expense discard dialog '
      '${discard == null ? 'dismissed' : '→ stay'}: amount kept',
    );
  }

  void _logBudget(String budgetId, AsyncValue<Budget?> next) {
    if (next case AsyncError(:final error, :final stackTrace)) {
      var cause = error;
      while (cause is ProviderException) {
        cause = cause.exception;
      }
      final redacted = redactDbError(cause);
      _log.warning(
        'new expense budget budgetId=$budgetId unavailable, budget chip '
        'hidden: ${describeError(redacted)}',
        redacted,
        stackTrace,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final state = ref.watch(newExpenseControllerProvider(widget.date));
    final today = ref.watch(clockProvider).today();
    final budgetId = ref.watch(selectedBudgetIdProvider).value;
    Budget? budget;
    if (budgetId != null) {
      ref.listen(
        budgetProvider(budgetId),
        (previous, next) => _logBudget(budgetId, next),
      );
      budget = ref.watch(budgetProvider(budgetId)).value;
      ref.listen(
        categoriesProvider(budgetId),
        (previous, next) => _logCategories(budgetId, next),
      );
    }
    final categoriesValue = budgetId == null
        ? null
        : ref.watch(categoriesProvider(budgetId));
    final categories = categoriesValue == null || categoriesValue.hasError
        ? const <Category>[]
        : categoriesValue.value ?? const <Category>[];
    final bottom = MediaQuery.paddingOf(context).bottom;

    return PopScope<Object?>(
      canPop: _leaving || state.input.isEmpty,
      onPopInvokedWithResult: _handlePop,
      child: Scaffold(
        backgroundColor: colors.bgApp,
        body: Column(
          children: [
            SafeArea(
              bottom: false,
              child: _TopBar(
                budgetEmoji: budget?.emoji,
                budgetLabel: budget == null
                    ? null
                    : budget.kind == BudgetKind.personal
                    ? l10n.newExpensePersonalBudget
                    : budget.name,
                onClose: _close,
              ),
            ),
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _AmountView(
                          input: state.input,
                          caretOn: _caretOn,
                          shake: _shake,
                        ),
                        Center(
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            children: [
                              AppChip(
                                emoji: '📅',
                                label: expenseDateLabel(
                                  l10n,
                                  state.date,
                                  today,
                                ),
                              ),
                              AppChip(
                                emoji: '💬',
                                label: l10n.newExpenseComment,
                              ),
                            ],
                          ),
                        ),
                        _Categories(
                          categories: categories,
                          onPick: (c) => _pick(c, from: 'grid'),
                          onAll: () => _openAll(categories),
                          onSetup: () => _openSetup(from: 'grid'),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                          child: Semantics(
                            liveRegion: true,
                            child: FittingText(
                              _needAmount
                                  ? l10n.newExpenseNeedAmount
                                  : l10n.newExpenseHint,
                              textAlign: TextAlign.center,
                              style: AppText.caption.copyWith(
                                color: _needAmount
                                    ? colors.statusDanger
                                    : colors.textTertiary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SliverLayoutBuilder(
                    builder: (context, constraints) => SliverFillRemaining(
                      hasScrollBody: false,
                      child: _Keypad(
                        keyHeight: _Keypad.keyHeightFor(
                          context,
                          space:
                              constraints.viewportMainAxisExtent -
                              constraints.precedingScrollExtent,
                          bottomInset: bottom,
                        ),
                        bottomInset: bottom,
                        onDigit: (d) => _press((c) => c.digit(d)),
                        onComma: () => _press((c) => c.comma()),
                        onBackspace: () =>
                            _press((c) => c.backspace(), shake: false),
                        onClear: () => _press((c) => c.clear(), shake: false),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.budgetEmoji,
    required this.budgetLabel,
    required this.onClose,
  });

  final String? budgetEmoji;
  final String? budgetLabel;
  final VoidCallback onClose;

  static const double _closeWidth = 52;
  static const double _endGap = 12;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final label = budgetLabel;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          LayoutBuilder(
            builder: (context, constraints) => Row(
              children: [
                const SizedBox(width: _closeWidth),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: FittingText(
                      l10n.newExpenseTitle,
                      textAlign: TextAlign.center,
                      style: AppText.titleS.copyWith(color: colors.textPrimary),
                    ),
                  ),
                ),
                if (label != null)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth:
                          (constraints.maxWidth - _closeWidth - _endGap) / 2,
                    ),
                    child: AppChip(emoji: budgetEmoji, label: label),
                  ),
                const SizedBox(width: _endGap),
              ],
            ),
          ),
          Positioned(
            left: 6,
            top: 0,
            bottom: 0,
            width: 48,
            child: Center(
              child: Semantics(
                button: true,
                label: l10n.a11yClose,
                excludeSemantics: true,
                onTap: onClose,
                child: InkResponse(
                  radius: 22,
                  onTap: onClose,
                  child: SizedBox.square(
                    dimension: 48,
                    child: Center(
                      child: AppIcon(
                        AppIcons.x,
                        size: 24,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Categories extends StatelessWidget {
  const _Categories({
    required this.categories,
    required this.onPick,
    required this.onAll,
    required this.onSetup,
  });

  final List<Category> categories;
  final ValueChanged<Category> onPick;
  final VoidCallback onAll;
  final VoidCallback onSetup;

  static const double _side = 16;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final mood = context.mood;
    return LayoutBuilder(
      builder: (context, constraints) {
        final grid = categoryGridColumns * categoryTileWidth;
        final side = math.max(
          0.0,
          math.min(_side, (constraints.maxWidth - grid) / 2),
        );
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: side),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 16, bottom: 14),
                      child: FittingText(
                        l10n.newExpenseCategory,
                        style: AppText.labelM.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: l10n.newExpenseSetup,
                    excludeSemantics: true,
                    onTap: onSetup,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onSetup,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 17, 0, 15),
                        child: Text(
                          l10n.newExpenseSetup,
                          style: AppText.labelS.copyWith(
                            color: mood.accentStrong,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              CategoryGrid(
                rowGap: 10,
                tiles: [
                  for (final category in categories.take(
                    newExpenseGridCategories,
                  ))
                    CategoryTile(
                      emoji: category.emoji,
                      name: category.name,
                      color: category.color,
                      onTap: () => onPick(category),
                    ),
                  CategoryTile(
                    emoji: allCategoriesEmoji,
                    name: l10n.newExpenseAll,
                    color: null,
                    onTap: onAll,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AmountView extends StatelessWidget {
  const _AmountView({
    required this.input,
    required this.caretOn,
    required this.shake,
  });

  final KeypadInput input;
  final bool caretOn;
  final Animation<double> shake;

  static const double caretHeight = 42;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final mood = context.mood;
    final scaler = MediaQuery.textScalerOf(context);
    final empty = input.isEmpty;
    return Semantics(
      container: true,
      label: l10n.newExpenseAmount,
      value: spokenAmount(l10n, input.amount),
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
          child: Column(
            children: [
              Text(
                l10n.newExpenseAmount,
                style: AppText.labelS.copyWith(color: colors.textTertiary),
              ),
              const SizedBox(height: 4),
              AnimatedBuilder(
                animation: shake,
                builder: (context, child) {
                  final t = shake.value;
                  final dx = t == 0 || t == 1
                      ? 0.0
                      : math.sin(t * math.pi * 6) * 10 * (1 - t);
                  return Transform.translate(
                    offset: Offset(dx, 0),
                    child: child,
                  );
                },
                child: FittedBox(
                  key: const ValueKey('new-expense-amount'),
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        empty ? '0' : input.display,
                        maxLines: 1,
                        style: AppText.displayXl.tabular.copyWith(
                          color: empty
                              ? colors.textTertiary
                              : colors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Opacity(
                        opacity: caretOn ? 1 : 0,
                        child: Container(
                          key: const ValueKey('new-expense-caret'),
                          width: 3,
                          height: scaler.scale(caretHeight),
                          decoration: BoxDecoration(
                            color: mood.accent,
                            borderRadius: BorderRadius.circular(1.5),
                          ),
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.keyHeight,
    required this.bottomInset,
    required this.onDigit,
    required this.onComma,
    required this.onBackspace,
    required this.onClear,
  });

  final double keyHeight;
  final double bottomInset;
  final ValueChanged<int> onDigit;
  final VoidCallback onComma;
  final VoidCallback onBackspace;
  final VoidCallback onClear;

  static const double _gap = 8;
  static const double _padding = 12;
  static const double _keyHeight = 58;

  static double keyHeightFor(
    BuildContext context, {
    required double space,
    required double bottomInset,
  }) {
    final style = AppText.titleL;
    final text =
        MediaQuery.textScalerOf(context).scale(style.fontSize!) * style.height!;
    final shortest = math.min(_keyHeight, math.max(kMinTapTarget, text));
    final fits = (space - 2 * _padding - 3 * _gap - bottomInset) / 4;
    return fits.clamp(shortest, _keyHeight);
  }

  Widget _row(List<Widget> keys) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < keys.length; i++) ...[
        if (i > 0) const SizedBox(width: _gap),
        Expanded(
          child: SizedBox(height: keyHeight, child: keys[i]),
        ),
      ],
    ],
  );

  Widget _digit(int d) => KeypadKey.symbol('$d', onTap: () => onDigit(d));

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.bgSurface2,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(RadiusTokens.xl),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          _padding,
          _padding,
          _padding,
          _padding + bottomInset,
        ),
        child: Align(
          alignment: Alignment.topCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _row([_digit(1), _digit(2), _digit(3)]),
              const SizedBox(height: _gap),
              _row([_digit(4), _digit(5), _digit(6)]),
              const SizedBox(height: _gap),
              _row([_digit(7), _digit(8), _digit(9)]),
              const SizedBox(height: _gap),
              _row([
                KeypadKey.symbol(',', onTap: onComma),
                _digit(0),
                KeypadKey.backspace(onTap: onBackspace, onLongPress: onClear),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
