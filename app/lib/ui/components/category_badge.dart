import 'package:flutter/widgets.dart';
import 'package:shared/shared.dart' show CategoryColor;

import '../theme/app_text.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';

/// Значок категории (Figma CategoryBadge `4:33`): эмодзи на подложке
/// `category/<цвет>-soft` 40 × 40, скругление 12. У «Другое» ([color] =
/// `null`) — подложка `bg/surface-3` (00-spec §7.4).
/// Эмодзи — системные (Noto Color Emoji на Android), со шрифтом не растут.
class CategoryBadge extends StatelessWidget {
  const CategoryBadge({super.key, required this.emoji, required this.color});

  /// Сторона значка.
  static const double size = 40;

  final String emoji;
  final CategoryColor? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.categorySoft(color),
          borderRadius: BorderRadius.circular(RadiusTokens.sm),
        ),
        child: Text(
          emoji,
          style: AppText.titleM.copyWith(color: colors.textPrimary),
          textScaler: TextScaler.noScaling,
        ),
      ),
    );
  }
}
