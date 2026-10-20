import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../icons/app_icon.dart';
import '../theme/app_text.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';

/// Кнопка «+» (Figma Fab `5:27`): круг 60 цвета `accent`, тень raised,
/// плюс 28 `on-accent`. На праздник — наклейка с эмодзи (свойство
/// «Наклейка»): кружок 26 `bg/surface` с рамкой `accent-strong` 1.5,
/// справа сверху.
class AppFab extends StatelessWidget {
  const AppFab({super.key, required this.onPressed, this.stickerEmoji});

  final VoidCallback? onPressed;

  /// Эмодзи наклейки; `null` — без наклейки.
  final String? stickerEmoji;

  static const double size = 60;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mood = context.mood;
    return Semantics(
      button: true,
      label: AppLocalizations.of(context).a11yAddExpense,
      excludeSemantics: true,
      onTap: onPressed,
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: ShadowTokens.raised,
              ),
              child: Material(
                color: mood.accent,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  splashColor: mood.onAccent.withValues(alpha: 0.16),
                  highlightColor: mood.onAccent.withValues(alpha: 0.08),
                  onTap: onPressed,
                  child: SizedBox.square(
                    dimension: size,
                    child: Center(
                      child: AppIcon(
                        AppIcons.plus,
                        size: 28,
                        strokeWidth: 2.6,
                        color: mood.onAccent,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (stickerEmoji != null)
              Positioned(
                left: 40,
                top: -6,
                child: IgnorePointer(
                  child: Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.bgSurface,
                      shape: BoxShape.circle,
                      border: Border.all(color: mood.accentStrong, width: 1.5),
                    ),
                    child: Text(
                      stickerEmoji!,
                      style: AppText.labelM.copyWith(color: colors.textPrimary),
                      textScaler: TextScaler.noScaling,
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
