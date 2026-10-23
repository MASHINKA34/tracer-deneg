import 'package:flutter/material.dart';

import '../icons/app_icon.dart';
import '../theme/app_text.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';
import 'fitting_text.dart';

/// Тип кнопки (Figma Button `3:218`, свойство «Тип»).
enum AppButtonType { primary, soft, outline, text, danger }

/// Размер кнопки: L — высота 52, M — 40 (область нажатия всё равно ≥ 48).
enum AppButtonSize { l, m }

/// Кнопка дизайн-системы.
///
/// Состояния, которых нет в Figma (решение этапа 03): «недоступна» — фон
/// `bg/surface-3` и текст `text/disabled` (Outline — рамка `border/default`,
/// Text — только текст `text/disabled`); «нажата» — рябь цвета настроения
/// и лёгкое затемнение заливки.
/// [destructive] у типа Text — красный текст (диалог «Выйти и потерять»,
/// макет `42:4321`).
/// При крупном шрифте текст переносится, кнопка растёт по высоте.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.type = AppButtonType.primary,
    this.size = AppButtonSize.l,
    this.icon,
    this.expand = false,
    this.destructive = false,
    this.statesController,
    this.background,
    this.horizontalPadding,
  });

  final String label;

  /// `null` — кнопка недоступна.
  final VoidCallback? onPressed;
  final AppButtonType type;
  final AppButtonSize size;

  /// Иконка слева (свойство «Иконка слева»).
  final AppIcons? icon;

  /// Растянуть на всю ширину (шторки, диалоги).
  final bool expand;

  /// Только для [AppButtonType.text]: текст цвета `status/danger`.
  final bool destructive;

  /// Внешнее управление состояниями (фокус, «нажата» в каталоге).
  final WidgetStatesController? statesController;

  final Color? background;

  final double? horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mood = context.mood;
    final enabled = onPressed != null;
    final isL = size == AppButtonSize.l;
    final height = isL ? 52.0 : 40.0;
    final radius = isL ? RadiusTokens.md : RadiusTokens.sm;
    final textStyle = isL ? AppText.labelL : AppText.labelM;
    final iconSize = isL ? 20.0 : 18.0;
    final lineHeight = textStyle.fontSize! * textStyle.height!;

    final (Color background, Color foreground, Color overlay) = switch (type) {
      AppButtonType.primary => (
        mood.accent,
        mood.onAccent,
        mood.onAccent.withValues(alpha: 0.16),
      ),
      AppButtonType.soft => (
        mood.soft,
        mood.onSoft,
        mood.accent.withValues(alpha: 0.12),
      ),
      AppButtonType.outline => (
        Colors.transparent,
        colors.textPrimary,
        mood.accent.withValues(alpha: 0.12),
      ),
      AppButtonType.text => (
        Colors.transparent,
        destructive ? colors.statusDanger : mood.accentStrong,
        (destructive ? colors.statusDanger : mood.accent).withValues(
          alpha: 0.12,
        ),
      ),
      AppButtonType.danger => (
        colors.statusDanger,
        colors.textInverse,
        colors.textInverse.withValues(alpha: 0.16),
      ),
    };
    final fill = this.background ?? background;
    final filled = fill != Colors.transparent;
    final disabledBackground =
        type == AppButtonType.outline || type == AppButtonType.text
        ? Colors.transparent
        : colors.bgSurface3;
    final fg = enabled ? foreground : colors.textDisabled;

    final style = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(0, height)),
      // Вертикальный отступ = (высота − строка) / 2: при шрифте 1.0 кнопка
      // ровно 52/40, при крупном — растёт.
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(
          // У Outline обводка 1,5 входит в размер, как в Figma (105 / 86).
          horizontal:
              (horizontalPadding ?? (isL ? 22 : 16)) +
              (type == AppButtonType.outline ? 1.5 : 0),
          vertical: (height - lineHeight) / 2,
        ),
      ),
      tapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      ),
      side: type == AppButtonType.outline
          ? WidgetStatePropertyAll(
              BorderSide(
                color: enabled ? colors.borderStrong : colors.borderDefault,
                width: 1.5,
              ),
            )
          : null,
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return disabledBackground;
        if (filled && states.contains(WidgetState.pressed)) {
          return Color.alphaBlend(
            const Color(0xFF1E1A15).withValues(alpha: 0.08),
            fill,
          );
        }
        return fill;
      }),
      foregroundColor: WidgetStatePropertyAll(fg),
      overlayColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.pressed) ||
                states.contains(WidgetState.focused)
            ? overlay
            : null,
      ),
      elevation: const WidgetStatePropertyAll(0),
      shadowColor: const WidgetStatePropertyAll(Colors.transparent),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      textStyle: WidgetStatePropertyAll(textStyle.copyWith(color: fg)),
      splashFactory: InkRipple.splashFactory,
    );

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          AppIcon(icon!, size: iconSize, color: fg),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: FittingText(
            label,
            textAlign: TextAlign.center,
            style: textStyle.copyWith(color: fg),
          ),
        ),
      ],
    );

    final button = TextButton(
      onPressed: onPressed,
      style: style,
      statesController: statesController,
      child: content,
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}
