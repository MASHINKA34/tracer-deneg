import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../core/router.dart';
import '../../data/db/redact_db_error.dart';
import '../../data/providers.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/components/button.dart';
import '../../ui/components/dialog.dart';
import '../../ui/components/fitting_text.dart';
import '../../ui/components/snackbar.dart';
import '../../ui/components/tap_target.dart';
import '../../ui/components/text_field.dart';
import '../../ui/theme/app_text.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/tokens/tokens.g.dart';
import 'categories_top_bar.dart';
import 'category_editor_controller.dart';
import 'category_emoji_sheet.dart';

final _log = Logger('categories');

final _nav = Logger('nav');

const double _emojiCell = 40;

const double _emojiSlack = (kMinTapTarget - _emojiCell) / 2;

const double _colorDot = 30;

const double _colorMinGap = 2;

const double _colorSlack = (kMinTapTarget - _colorDot) / 2;

String categoryNameErrorText(AppLocalizations l10n, ValidationError error) =>
    switch (error) {
      ValidationError.categoryNameTooLong => l10n.categoryNameTooLong(
        categoryNameMaxLength,
      ),
      _ => l10n.categoryNameEmpty,
    };

class CategoryEditorScreen extends ConsumerStatefulWidget {
  const CategoryEditorScreen({super.key, this.categoryId});

  final String? categoryId;

  @override
  ConsumerState<CategoryEditorScreen> createState() =>
      _CategoryEditorScreenState();
}

class _CategoryEditorScreenState extends ConsumerState<CategoryEditorScreen> {
  final Stopwatch _sinceOpen = Stopwatch()..start();
  final TextEditingController _name = TextEditingController();
  String _closedBy = 'back';
  bool _nameFilled = false;
  Category? _deleting;

  String? get _id => widget.categoryId;

  String get _target => _id == null ? 'new' : 'id=$_id';

  CategoryEditorController get _controller =>
      ref.read(categoryEditorControllerProvider(_id).notifier);

  @override
  void initState() {
    super.initState();
    _log.fine('category editor opened $_target');
    final id = _id;
    if (id == null) {
      _nameFilled = true;
      return;
    }
    ref.listenManual(categoryProvider(id), _onCategory, fireImmediately: true);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Object _unwrap(Object error) {
    var cause = error;
    while (cause is ProviderException) {
      cause = cause.exception;
    }
    return cause;
  }

  void _onCategory(
    AsyncValue<Category?>? previous,
    AsyncValue<Category?> next,
  ) {
    switch (next) {
      case AsyncData(value: final category?):
        if (!_nameFilled) {
          _nameFilled = true;
          _name.text = category.name;
        }
        if (previous?.value != null) return;
        _log.fine(
          'category editor loaded $_target budgetId=${category.budgetId} '
          'system=${category.isSystem} color=${category.color?.name} '
          'order=${category.sortOrder} '
          'nameLength=${textLength(category.name)} '
          'in ${_sinceOpen.elapsedMilliseconds}ms',
        );
        if (category.isSystem) {
          _log.warning(
            'category editor $_target is the system category → read-only '
            'screen, editing and deleting are not allowed',
          );
        }
      case AsyncData() when _deleting != null:
        _log.fine(
          'category editor $_target: category deleted from this screen, '
          'keeping the form until the screen is closed',
        );
      case AsyncData():
        if (previous?.value != null) {
          _log.info(
            'category editor $_target: category was deleted while the screen '
            'was open → not found screen',
          );
        } else {
          _log.warning(
            'category editor $_target: category is not found or deleted → '
            'not found screen',
          );
        }
      case AsyncError(:final error, :final stackTrace):
        final redacted = redactDbError(_unwrap(error));
        _log.severe(
          'category editor $_target: reading the category failed after '
          '${_sinceOpen.elapsedMilliseconds}ms → error screen: '
          '${describeError(redacted)}',
          redacted,
          stackTrace,
        );
      default:
    }
  }

  void _leave(String reason) {
    _closedBy = reason;
    if (context.canPop()) {
      context.pop();
      return;
    }
    _nav.fine(
      'category editor $_target closed by $reason with nothing under it → '
      '${AppRoutes.categories}',
    );
    context.go(AppRoutes.categories);
  }

  void _handlePop(bool didPop, Object? result) {
    if (!didPop) return;
    _nav.fine('category editor closed $_target by $_closedBy');
    if (_closedBy == 'save' || _closedBy == 'delete') return;
    final id = _id;
    final draft = ref.read(categoryEditorControllerProvider(id));
    final original = id == null ? null : ref.read(categoryProvider(id)).value;
    final changed = original == null
        ? [
            if (draft.name != null) CategoryField.name,
            if (draft.emoji != null) CategoryField.emoji,
            if (draft.color != null) CategoryField.color,
          ]
        : draft.changedFields(original);
    if (changed.isEmpty) return;
    _log.fine(
      'category editor $_target closed by $_closedBy with unsaved '
      'fields=${categoryFieldNames(changed)} → changes discarded',
    );
  }

  Future<void> _pickOther() async {
    _log.fine('category edit $_target ➕ tap → emoji keyboard sheet');
    FocusManager.instance.primaryFocus?.unfocus();
    final emoji = await showCategoryEmojiSheet(context);
    if (!mounted || emoji == null) return;
    _controller.setEmoji(emoji, from: 'keyboard');
  }

  Future<void> _save(Category? original, String? budgetId) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final result = await _controller.save(original, budgetId: budgetId);
    if (!mounted) return;
    switch (result) {
      case CategorySave.saved || CategorySave.noChanges:
        _leave('save');
      case CategorySave.failed:
        showAppSnackbar(
          context,
          text: AppLocalizations.of(context).categorySaveFailed,
        );
      case CategorySave.missing when original == null:
        showAppSnackbar(
          context,
          text: AppLocalizations.of(context).categorySaveFailed,
        );
      case CategorySave.invalid ||
          CategorySave.busy ||
          CategorySave.missing ||
          CategorySave.system:
        break;
    }
  }

  Future<void> _delete(Category category) async {
    if (_deleting != null ||
        ref.read(categoryEditorControllerProvider(_id)).busy) {
      _log.fine('category delete tap $_target ignored: already in progress');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    _log.fine('category delete tap $_target → counting expenses to move');
    final l10n = AppLocalizations.of(context);
    final count = await _controller.expenseCount(category);
    if (!mounted) return;
    if (count == null) {
      showAppSnackbar(context, text: l10n.categoryDeleteFailed);
      return;
    }
    final confirmed = await showAppDialog<bool>(
      context,
      builder: (context) => AppDialog(
        title: l10n.categoryDeleteTitle(category.name),
        message: l10n.categoryDeleteMessage(count),
        textAlign: TextAlign.start,
        primary: AppDialogAction(
          l10n.categoryDeleteConfirm,
          () => Navigator.of(context).pop(true),
          destructive: true,
        ),
        secondary: AppDialogAction(
          l10n.categoryDeleteCancel,
          () => Navigator.of(context).pop(false),
        ),
      ),
    );
    if (!mounted) return;
    if (confirmed != true) {
      _log.fine(
        'category delete $_target dialog '
        '${confirmed == null ? 'dismissed' : '→ cancel'}: nothing deleted',
      );
      return;
    }
    setState(() => _deleting = category);
    final result = await _controller.delete(category, shownExpenses: count);
    if (!mounted) return;
    switch (result) {
      case CategoryDelete.deleted:
        _leave('delete');
      case CategoryDelete.failed:
        setState(() => _deleting = null);
        showAppSnackbar(context, text: l10n.categoryDeleteFailed);
      case CategoryDelete.busy ||
          CategoryDelete.missing ||
          CategoryDelete.system:
        setState(() => _deleting = null);
    }
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
      switch (ref.watch(categoryProvider(id))) {
        case _ when deleting != null:
          body = _form(context, deleting, deleting.budgetId);
        case AsyncError():
          body = _MessageView(
            title: l10n.categoryLoadFailedTitle,
            text: l10n.categoryLoadFailedText,
            onBack: () => _leave('back button'),
          );
        case AsyncData(value: final category?) when category.isSystem:
          body = _MessageView(
            title: l10n.categorySystemTitle,
            text: l10n.categorySystemText,
            onBack: () => _leave('back button'),
          );
        case AsyncData(value: final category?):
          body = _form(context, category, category.budgetId);
        case AsyncData():
          body = _MessageView(
            title: l10n.categoryMissingTitle,
            text: l10n.categoryMissingText,
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
                title: id == null ? l10n.categoryNewTitle : l10n.categoryTitle,
                onBack: () => _leave('back button'),
              ),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }

  Widget _form(BuildContext context, Category? original, String? budgetId) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final draft = ref.watch(categoryEditorControllerProvider(_id));
    final emoji = draft.emojiOf(original);
    final color = draft.colorOf(original);
    final error = draft.visibleNameError(original);
    final canSave = !draft.busy && _deleting == null;
    final bottom = MediaQuery.paddingOf(context).bottom;
    const inset = EdgeInsets.symmetric(horizontal: _emojiSlack);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        16 - _emojiSlack,
        8,
        16 - _emojiSlack,
        16 + bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: _Preview(emoji: emoji, color: color),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: inset,
            child: AppTextField(
              label: l10n.categoryName,
              controller: _name,
              errorText: error == null
                  ? null
                  : categoryNameErrorText(l10n, error),
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.done,
              onChanged: _controller.setName,
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: inset,
            child: Text(
              l10n.categoryEmoji,
              style: AppText.labelS.copyWith(color: colors.textSecondary),
            ),
          ),
          const SizedBox(height: 16 - _emojiSlack),
          Wrap(
            children: [
              for (final (i, value) in frequentCategoryEmojis.indexed)
                _EmojiCell(
                  emoji: value,
                  label: value,
                  selected: value == emoji,
                  color: color,
                  onTap: () => _controller.setEmoji(value, from: 'grid#$i'),
                ),
              _EmojiCell(
                emoji: otherEmojiTile,
                label: l10n.categoryEmojiOther,
                selected: false,
                color: color,
                onTap: _pickOther,
              ),
            ],
          ),
          const SizedBox(height: 16 - _emojiSlack),
          Padding(
            padding: inset,
            child: Text(
              l10n.categoryColor,
              style: AppText.labelS.copyWith(color: colors.textSecondary),
            ),
          ),
          const SizedBox(height: 16 - _colorSlack),
          Padding(
            padding: inset,
            child: _ColorRow(selected: color, onPick: _controller.setColor),
          ),
          const SizedBox(height: 16 - _colorSlack),
          Padding(
            padding: inset,
            child: AppButton(
              label: l10n.categorySave,
              expand: true,
              onPressed: canSave ? () => _save(original, budgetId) : null,
            ),
          ),
          if (original != null) ...[
            const SizedBox(height: 16),
            Padding(
              padding: inset,
              child: AppButton(
                label: l10n.categoryDelete,
                type: AppButtonType.text,
                destructive: true,
                expand: true,
                onPressed: () => _delete(original),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Padding(
            padding: inset,
            child: Text(
              l10n.categoryEmojiHint,
              style: AppText.caption.copyWith(color: colors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.emoji, required this.color});

  final String emoji;
  final CategoryColor color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ExcludeSemantics(
      child: Container(
        width: 72,
        height: 72,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.categorySoft(color),
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
    required this.color,
    required this.onTap,
  });

  final String emoji;
  final String label;
  final bool selected;
  final CategoryColor color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mood = context.mood;
    final radius = BorderRadius.circular(RadiusTokens.sm);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: TapTarget(
        child: Material(
          color: selected ? colors.categorySoft(color) : colors.bgSurface,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
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
                  style: AppText.titleM.copyWith(color: colors.textSecondary),
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

class _ColorRow extends StatelessWidget {
  const _ColorRow({required this.selected, required this.onPick});

  final CategoryColor selected;
  final ValueChanged<CategoryColor> onPick;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const values = CategoryColor.values;
        final n = values.length;
        final width = constraints.maxWidth;
        final dot = math.min(_colorDot, (width - (n - 1) * _colorMinGap) / n);
        final gap = (width - n * dot) / (n - 1);
        double center(int i) => i * (dot + gap) + dot / 2;
        double edge(int i) => i == 0
            ? 0
            : i == n
            ? width
            : (center(i - 1) + center(i)) / 2;
        return Row(
          children: [
            for (final (i, value) in values.indexed)
              SizedBox(
                width: edge(i + 1) - edge(i),
                height: kMinTapTarget,
                child: _ColorDot(
                  color: value,
                  size: dot,
                  offset: center(i) - dot / 2 - edge(i),
                  selected: value == selected,
                  onTap: () => onPick(value),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.size,
    required this.offset,
    required this.selected,
    required this.onTap,
  });

  final CategoryColor color;
  final double size;
  final double offset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final solid = colors.category(color)!.solid;
    final fill = selected ? size - 10 : size - 4;
    return Semantics(
      button: true,
      selected: selected,
      label: l10n.categoryColorName(color.name),
      excludeSemantics: true,
      onTap: onTap,
      child: InkResponse(
        radius: 22,
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.only(left: offset),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: selected
                    ? Border.all(color: colors.textPrimary, width: 2)
                    : null,
              ),
              child: Container(
                width: fill,
                height: fill,
                decoration: BoxDecoration(color: solid, shape: BoxShape.circle),
              ),
            ),
          ),
        ),
      ),
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
              label: l10n.categoryBack,
              type: AppButtonType.soft,
              onPressed: onBack,
            ),
          ],
        ),
      ),
    );
  }
}
