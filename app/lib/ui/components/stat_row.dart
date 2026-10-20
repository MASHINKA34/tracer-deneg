import 'package:flutter/material.dart';
import 'package:shared/shared.dart' show CategoryColor;

import '../theme/app_text.dart';
import '../theme/app_theme.dart';
import 'category_badge.dart';
import 'fitting_text.dart';

/// Строка категории в статистике (Figma StatRow `4:62`): значок, название,
/// «34% · 18 покупок», сумма и полоса длиной [fraction] от самой большой
/// категории, цвета категории `solid` на `bg/surface-2`.
class StatRow extends StatelessWidget {
  const StatRow({
    super.key,
    required this.emoji,
    required this.color,
    required this.name,
    required this.share,
    required this.amount,
    required this.fraction,
    this.onTap,
  });

  final String emoji;

  /// `null` — «Другое».
  final CategoryColor? color;
  final String name;

  /// «34% · 18 покупок».
  final String share;

  /// «6 240 ₽».
  final String amount;

  /// Длина полосы 0…1.
  final double fraction;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bar = colors.category(color)?.solid ?? colors.textTertiary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                CategoryBadge(emoji: emoji, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittingText(
                        name,
                        style: AppText.labelM.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      FittingText(
                        share,
                        style: AppText.caption.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  amount,
                  style: AppText.numericM.copyWith(color: colors.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              height: 6,
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                color: colors.bgSurface2,
                borderRadius: BorderRadius.circular(999),
              ),
              child: FractionallySizedBox(
                widthFactor: fraction.clamp(0, 1),
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: bar,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
