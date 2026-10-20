import 'package:flutter/material.dart';
import 'package:shared/shared.dart' show CategoryColor;

import '../theme/app_text.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';
import 'fitting_text.dart';

/// Плитка категории в «Новой трате» (Figma CategoryTile `4:43`): квадрат
/// 56 с эмодзи на `category/<цвет>-soft`, под ним название. «Выбрана» —
/// рамка `accent-strong` 2 снаружи и название `Label/S` `text/primary`;
/// иначе — `Micro` `text/secondary`. Ширина 76; длинное название
/// переносится.
class CategoryTile extends StatelessWidget {
  const CategoryTile({
    super.key,
    required this.emoji,
    required this.name,
    required this.color,
    this.selected = false,
    this.onTap,
  });

  final String emoji;
  final String name;

  /// `null` — «Другое».
  final CategoryColor? color;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mood = context.mood;
    final radius = BorderRadius.circular(RadiusTokens.md);

    final box = Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: selected
            ? Border.all(
                color: mood.accentStrong,
                width: 2,
                strokeAlign: BorderSide.strokeAlignOutside,
              )
            : null,
      ),
      child: Material(
        color: colors.categorySoft(color),
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Center(
            child: Text(
              emoji,
              style: AppText.titleL.copyWith(color: colors.textPrimary),
              textScaler: TextScaler.noScaling,
            ),
          ),
        ),
      ),
    );

    return Semantics(
      button: onTap != null,
      selected: selected,
      label: name,
      onTap: onTap,
      excludeSemantics: true,
      child: SizedBox(
        width: 76,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            box,
            const SizedBox(height: 6),
            FittingText(
              name,
              textAlign: TextAlign.center,
              style: selected
                  ? AppText.labelS.copyWith(color: colors.textPrimary)
                  : AppText.micro.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
