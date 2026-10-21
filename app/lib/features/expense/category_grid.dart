import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/components/button.dart';
import '../../ui/components/category_tile.dart';
import '../../ui/components/sheet.dart';
import '../../ui/theme/app_text.dart';
import '../../ui/theme/app_theme.dart';

const double categoryTileWidth = 76;

const int categoryGridColumns = 4;

const String allCategoriesEmoji = '⋯';

class CategoryGrid extends StatelessWidget {
  const CategoryGrid({
    super.key,
    required this.tiles,
    this.rowGap = 12,
    this.firstRowTop = 0,
  });

  final List<Widget> tiles;
  final double rowGap;
  final double firstRowTop;

  static int columnsFor(double width) => math.max(
    1,
    math.min(categoryGridColumns, (width / categoryTileWidth).floor()),
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = columnsFor(width);
        final gap = columns == 1
            ? 0.0
            : (width - columns * categoryTileWidth) / (columns - 1);
        final rows = <Widget>[];
        for (var start = 0; start < tiles.length; start += columns) {
          final row = tiles.sublist(
            start,
            math.min(start + columns, tiles.length),
          );
          rows.add(
            Padding(
              padding: EdgeInsets.only(top: start == 0 ? firstRowTop : rowGap),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < row.length; i++) ...[
                    if (i > 0) SizedBox(width: gap),
                    row[i],
                  ],
                ],
              ),
            ),
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rows,
        );
      },
    );
  }
}

sealed class AllCategoriesChoice {
  const AllCategoriesChoice();
}

final class PickedCategory extends AllCategoriesChoice {
  const PickedCategory(this.category);

  final Category category;
}

final class SetupCategories extends AllCategoriesChoice {
  const SetupCategories();
}

Future<AllCategoriesChoice?> showAllCategoriesSheet(
  BuildContext context, {
  required List<Category> categories,
}) {
  final root = Navigator.of(context, rootNavigator: true);
  return showAppSheet<AllCategoriesChoice>(
    root.context,
    builder: (context) => [AllCategoriesSheet(categories: categories)],
  );
}

class AllCategoriesSheet extends StatelessWidget {
  const AllCategoriesSheet({super.key, required this.categories});

  final List<Category> categories;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final navigator = Navigator.of(context);
    return Flexible(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                l10n.newExpenseAllTitle,
                style: AppText.titleM.copyWith(color: colors.textPrimary),
              ),
            ),
            const SizedBox(height: 16),
            CategoryGrid(
              tiles: [
                for (final category in categories)
                  CategoryTile(
                    emoji: category.emoji,
                    name: category.name,
                    color: category.color,
                    onTap: () => navigator.pop(PickedCategory(category)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            AppButton(
              label: l10n.newExpenseSetup,
              onPressed: () => navigator.pop(const SetupCategories()),
              type: AppButtonType.soft,
              expand: true,
            ),
          ],
        ),
      ),
    );
  }
}
