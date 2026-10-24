import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../core/router.dart';
import '../../data/api/api_error_text.dart';
import '../../data/api/api_exception.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/components/button.dart';
import '../../ui/components/snackbar.dart';
import '../../ui/components/tap_target.dart';
import '../../ui/components/text_field.dart';
import '../../ui/theme/app_text.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/tokens/tokens.g.dart';
import '../categories/categories_top_bar.dart';
import '../categories/category_emoji_sheet.dart';
import 'budget_create_service.dart';
import 'budget_screen.dart';

final _log = Logger('budgets');

final _nav = Logger('nav');

const List<String> sharedBudgetEmojis = [
  '🏡',
  '🏠',
  '👨‍👩‍👧',
  '💑',
  '✈️',
  '🎉',
  '🚗',
  '🐾',
  '🎓',
  '💼',
  '🏖️',
];

const String otherBudgetEmojiTile = '➕';

const CategoryColor newBudgetColor = CategoryColor.teal;

const double _emojiCell = 44;

const double _emojiSlack = (kMinTapTarget - _emojiCell) / 2;

const double _emojiGap = 8;

String budgetNameErrorText(AppLocalizations l10n, ValidationError error) =>
    switch (error) {
      ValidationError.budgetNameTooLong => l10n.newBudgetNameTooLong(
        budgetNameMaxLength,
      ),
      _ => l10n.newBudgetNameEmpty,
    };

String budgetCreateFailureText(
  AppLocalizations l10n,
  BudgetCreateFailed failure,
) => switch (failure) {
  BudgetCreateFailed(stage: BudgetCreateStage.select) =>
    l10n.budgetSwitcherFailed,
  BudgetCreateFailed(stage: BudgetCreateStage.pull) => l10n.newBudgetNotLoaded,
  BudgetCreateFailed(offline: true) => l10n.newBudgetOffline,
  BudgetCreateFailed(error: final ApiException e) => apiErrorText(l10n, e),
  BudgetCreateFailed() => l10n.newBudgetFailed,
};

class NewBudgetScreen extends ConsumerStatefulWidget {
  const NewBudgetScreen({super.key});

  @override
  ConsumerState<NewBudgetScreen> createState() => _NewBudgetScreenState();
}

class _NewBudgetScreenState extends ConsumerState<NewBudgetScreen> {
  final TextEditingController _name = TextEditingController();
  String _budgetId = newId();
  String _emoji = sharedBudgetEmojis.first;
  bool _nameTouched = false;
  bool _submitted = false;
  bool _busy = false;
  String _closedBy = 'back';

  @override
  void initState() {
    super.initState();
    _log.fine('new budget screen opened budgetId=$_budgetId');
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  ValidationError? get _nameError => validateBudgetName(_name.text);

  ValidationError? get _visibleNameError {
    final error = _nameError;
    if (error == ValidationError.budgetNameEmpty &&
        !_nameTouched &&
        !_submitted) {
      return null;
    }
    return error;
  }

  void _nameChanged(String text) {
    _log.fine(
      'new budget name changed length=${textLength(text)} '
      'error=${validateBudgetName(text)?.code ?? 'none'}',
    );
    setState(() => _nameTouched = true);
  }

  void _setEmoji(String emoji, {required String from}) {
    final value = normalizeText(emoji);
    final error = validateEmoji(value);
    if (error != null) {
      _log.warning(
        'new budget emoji from=$from rejected: ${error.code} '
        'length=${textLength(value)}, keeping the previous emoji',
      );
      return;
    }
    if (value == _emoji) {
      _log.fine('new budget emoji from=$from unchanged');
      return;
    }
    _log.fine('new budget emoji set from=$from');
    setState(() => _emoji = value);
  }

  Future<void> _pickOther() async {
    _log.fine('new budget ➕ tap → emoji keyboard sheet');
    FocusManager.instance.primaryFocus?.unfocus();
    final emoji = await showCategoryEmojiSheet(
      context,
      hint: AppLocalizations.of(context).newBudgetEmojiSheetHint,
    );
    if (!mounted || emoji == null) return;
    _setEmoji(emoji, from: 'keyboard');
  }

  Future<void> _create() async {
    if (_busy) {
      _log.fine('new budget create tap ignored: request in progress');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final error = _nameError;
    if (error != null) {
      setState(() => _submitted = true);
      _log.info(
        'budget create blocked budgetId=$_budgetId: ${error.code} '
        'length=${textLength(normalizeText(_name.text))} '
        'max=$budgetNameMaxLength, error shown under the name field, no '
        'request',
      );
      return;
    }
    setState(() {
      _submitted = true;
      _busy = true;
    });
    final outcome = await ref
        .read(budgetCreateServiceProvider)
        .create(
          budgetId: _budgetId,
          name: normalizeText(_name.text),
          emoji: _emoji,
        );
    if (!mounted) {
      _log.fine(
        'new budget screen closed before the result $outcome → nothing more '
        'to show',
      );
      return;
    }
    setState(() => _busy = false);
    switch (outcome) {
      case BudgetCreated(:final budgetId):
        _closedBy = 'create';
        _nav.fine(
          'new budget budgetId=$budgetId created and selected → '
          '${AppRoutes.budget} with a new invite code',
        );
        context.pushReplacement(
          AppRoutes.budgetOf(budgetId),
          extra: BudgetScreenOpen.created,
        );
      case final BudgetCreateFailed failure:
        if (failure.code == ApiErrorCode.conflict) {
          final taken = _budgetId;
          _budgetId = newId();
          _log.info(
            'budget create budgetId=$taken: id belongs to another budget on '
            'the server → next attempt uses budgetId=$_budgetId',
          );
        }
        _log.fine(
          'new budget create failed stage=${failure.stage.name} → snackbar, '
          'form kept',
        );
        showAppSnackbar(
          context,
          text: budgetCreateFailureText(AppLocalizations.of(context), failure),
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
      'new budget closed by $reason with nothing under it → '
      '${AppRoutes.month}',
    );
    context.go(AppRoutes.month);
  }

  void _handlePop(bool didPop, Object? result) {
    if (!didPop) return;
    _nav.fine(
      'new budget closed by $_closedBy${_busy ? ' while creating' : ''}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final error = _visibleNameError;
    final bottom = MediaQuery.paddingOf(context).bottom;
    const inset = EdgeInsets.symmetric(horizontal: _emojiSlack);
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
                title: l10n.newBudgetTitle,
                onBack: () => _leave('back button'),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  16 - _emojiSlack,
                  8,
                  16 - _emojiSlack,
                  16 + bottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: _Preview(emoji: _emoji)),
                    const SizedBox(height: 16),
                    Padding(
                      padding: inset,
                      child: AppTextField(
                        label: l10n.newBudgetName,
                        controller: _name,
                        errorText: error == null
                            ? null
                            : budgetNameErrorText(l10n, error),
                        keyboardType: TextInputType.text,
                        textInputAction: TextInputAction.done,
                        onChanged: _nameChanged,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: inset,
                      child: Text(
                        l10n.newBudgetEmoji,
                        style: AppText.labelS.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16 - _emojiSlack),
                    Wrap(
                      spacing: _emojiGap - 2 * _emojiSlack,
                      runSpacing: _emojiGap - 2 * _emojiSlack,
                      children: [
                        for (final (i, value) in sharedBudgetEmojis.indexed)
                          _EmojiCell(
                            emoji: value,
                            label: value,
                            selected: value == _emoji,
                            onTap: () => _setEmoji(value, from: 'grid#$i'),
                          ),
                        _EmojiCell(
                          emoji: otherBudgetEmojiTile,
                          label: l10n.newBudgetEmojiOther,
                          selected: false,
                          onTap: _pickOther,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16 - _emojiSlack),
                    Padding(
                      padding: inset,
                      child: Text(
                        l10n.newBudgetHint,
                        style: AppText.caption.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: inset,
                      child: AppButton(
                        label: l10n.newBudgetCreate,
                        expand: true,
                        onPressed: _busy ? null : _create,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.emoji});

  final String emoji;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ExcludeSemantics(
      child: Container(
        width: 72,
        height: 72,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.categorySoft(newBudgetColor),
          borderRadius: BorderRadius.circular(RadiusTokens.lg),
        ),
        child: Text(
          emoji,
          style: AppText.displayL.copyWith(color: colors.textPrimary),
          textScaler: TextScaler.noScaling,
        ),
      ),
    );
  }
}

class _EmojiCell extends StatelessWidget {
  const _EmojiCell({
    required this.emoji,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String emoji;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mood = context.mood;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: TapTarget(
        child: Material(
          color: selected
              ? colors.categorySoft(newBudgetColor)
              : colors.bgSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(RadiusTokens.sm),
            side: selected
                ? BorderSide(color: mood.accentStrong, width: 2)
                : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox.square(
              dimension: _emojiCell,
              child: Center(
                child: Text(
                  emoji,
                  style: AppText.titleM.copyWith(color: colors.textPrimary),
                  textScaler: TextScaler.noScaling,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
