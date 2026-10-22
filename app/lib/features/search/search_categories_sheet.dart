import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/components/button.dart';
import '../../ui/components/category_badge.dart';
import '../../ui/components/checkbox.dart';
import '../../ui/components/fitting_text.dart';
import '../../ui/components/sheet.dart';
import '../../ui/theme/app_text.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/tokens/tokens.g.dart';

final _log = Logger('search');

Future<void> showSearchCategoriesSheet(
  BuildContext context, {
  required List<Category> categories,
  required Set<String> selected,
  required ValueChanged<Set<String>> onChanged,
}) async {
  final sw = Stopwatch()..start();
  final root = Navigator.of(context, rootNavigator: true);
  _log.fine(
    'search categories sheet opened categories=${categories.length} '
    'selected=${selected.length}',
  );
  final done = await showAppSheet<bool>(
    root.context,
    builder: (context) => [
      SearchCategoriesSheet(
        categories: categories,
        initial: selected,
        onChanged: onChanged,
        onDone: () => Navigator.of(context).pop(true),
      ),
    ],
  );
  _log.fine(
    'search categories sheet closed by '
    '${done == true ? 'done button' : 'back gesture, tap outside or swipe down'} '
    'after ${sw.elapsedMilliseconds}ms',
  );
}

class SearchCategoriesSheet extends StatefulWidget {
  const SearchCategoriesSheet({
    super.key,
    required this.categories,
    required this.initial,
    required this.onChanged,
    required this.onDone,
  });

  final List<Category> categories;
  final Set<String> initial;
  final ValueChanged<Set<String>> onChanged;
  final VoidCallback onDone;

  @override
  State<SearchCategoriesSheet> createState() => _SearchCategoriesSheetState();
}

class _SearchCategoriesSheetState extends State<SearchCategoriesSheet> {
  late Set<String> _selected = {...widget.initial};

  void _set(Set<String> selected) {
    setState(() => _selected = selected);
    widget.onChanged(Set.unmodifiable(selected));
  }

  void _toggle(Category category) {
    final next = {..._selected};
    if (!next.remove(category.id)) next.add(category.id);
    _set(next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    return Flexible(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            header: true,
            child: FittingText(
              l10n.searchCategoriesTitle,
              style: AppText.titleM.copyWith(color: colors.textPrimary),
            ),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: Material(
              color: colors.bgSurface2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(RadiusTokens.lg),
              ),
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _CategoryRow(
                      label: l10n.searchCategoriesAll,
                      checked: _selected.isEmpty,
                      onTap: () => _set(const {}),
                    ),
                    for (final category in widget.categories)
                      _CategoryRow(
                        label: category.name,
                        badge: CategoryBadge(
                          emoji: category.emoji,
                          color: category.color,
                        ),
                        checked: _selected.contains(category.id),
                        onTap: () => _toggle(category),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          AppButton(
            label: l10n.searchCategoriesDone,
            onPressed: widget.onDone,
            expand: true,
          ),
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.label,
    required this.checked,
    required this.onTap,
    this.badge,
  });

  final String label;
  final Widget? badge;
  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final badge = this.badge;
    return MergeSemantics(
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
            child: Row(
              children: [
                if (badge != null) ...[badge, const SizedBox(width: 12)],
                Expanded(
                  child: FittingText(
                    label,
                    style: AppText.labelM.copyWith(color: colors.textPrimary),
                  ),
                ),
                AppCheckbox(value: checked, onChanged: (_) => onTap()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
