import 'package:flutter/material.dart';

import '../theme/app_text.dart';
import '../theme/app_theme.dart';
import 'tap_target.dart';
import 'fitting_text.dart';

/// Чип (Figma Chip `3:259`): эмодзи + текст, «Выбран» — заливка `accent`.
/// Высота 36, область нажатия 48.
class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    this.emoji,
    this.selected = false,
    this.onTap,
    this.dropdown = false,
  });

  final String label;

  /// Эмодзи слева (свойство «Показать эмодзи»).
  final String? emoji;
  final bool selected;
  final VoidCallback? onTap;
  final bool dropdown;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mood = context.mood;
    final background = selected ? mood.accent : colors.bgSurface2;
    final foreground = selected ? mood.onAccent : colors.textPrimary;
    const shape = StadiumBorder();

    return Semantics(
      button: onTap != null,
      selected: selected,
      child: TapTarget(
        minWidth: 0,
        child: Material(
          color: background,
          shape: shape,
          child: InkWell(
            customBorder: shape,
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 36),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 14, 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (emoji != null) ...[
                      ExcludeSemantics(
                        child: Text(
                          emoji!,
                          style: AppText.bodyM.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: FittingText(
                        label,
                        style: AppText.labelM.copyWith(color: foreground),
                      ),
                    ),
                    if (dropdown) _DropdownMark(color: foreground),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DropdownMark extends StatelessWidget {
  const _DropdownMark({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final style = AppText.labelM;
    final size = MediaQuery.textScalerOf(context).scale(style.fontSize!);
    final k = size / style.fontSize!;
    return CustomPaint(
      size: Size(8 * k, size * style.height!),
      painter: _TrianglePainter(color: color, scale: k),
    );
  }
}

class _TrianglePainter extends CustomPainter {
  const _TrianglePainter({required this.color, required this.scale});

  final Color color;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final top = size.height / 2 - 2 * scale;
    final path = Path()
      ..moveTo(3 * scale, top)
      ..lineTo(8 * scale, top)
      ..lineTo(5.5 * scale, top + 4.5 * scale)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TrianglePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.scale != scale;
}
