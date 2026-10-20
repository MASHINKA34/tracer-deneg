import 'package:flutter/material.dart';
import 'package:shared/shared.dart' show CategoryColor;

import '../theme/app_text.dart';
import '../theme/app_theme.dart';

/// Логотип «Милиончика» (Figma Logo `5:178`): монетка с ростком на
/// квадрате 72 со скруглением 20. Цвета привязаны к настроению, как в Figma:
/// фон и «М» — `accent`, монетка — `on-accent`, кольцо — `accent` 1.5,
/// росток — `category/green`. Рисуется в 72 и масштабируется до [size].
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 72, this.semanticLabel});

  final double size;

  /// Подпись TalkBack; без неё логотип — украшение.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mood = context.mood;
    final logo = SizedBox.square(
      dimension: size,
      child: FittedBox(
        child: SizedBox.square(
          dimension: 72,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                Positioned.fill(child: ColoredBox(color: mood.accent)),
                Positioned(
                  left: 16,
                  top: 22,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: mood.onAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Positioned(
                  left: 20,
                  top: 26,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: mood.accent, width: 1.5),
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  top: 31,
                  width: 40,
                  child: Text(
                    'М',
                    textAlign: TextAlign.center,
                    style: AppText.displayS.copyWith(color: mood.accent),
                    textScaler: TextScaler.noScaling,
                  ),
                ),
                Positioned(
                  left: 0,
                  top: 0,
                  child: CustomPaint(
                    size: const Size(72, 72),
                    painter: _SproutPainter(
                      colors.category(CategoryColor.green)!.solid,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return semanticLabel == null
        ? ExcludeSemantics(child: logo)
        : Semantics(image: true, label: semanticLabel, child: logo);
  }
}

/// Росток: два листа и стебель — пути из Figma (кадр `sprout` в 24,5).
class _SproutPainter extends CustomPainter {
  _SproutPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    canvas
      ..save()
      ..translate(24, 5);
    final left = Path()
      ..moveTo(12, 13)
      ..cubicTo(7, 13, 2.5, 9.50001, 1.5, 3.50001)
      ..cubicTo(7.5, 2.50001, 11, 6.50001, 12, 13)
      ..close();
    final right = Path()
      ..moveTo(12, 13)
      ..cubicTo(13, 6, 16.5, 1.5, 22.5, 1)
      ..cubicTo(22.5, 8, 18, 13, 12, 13)
      ..close();
    canvas
      ..drawPath(left, paint)
      ..drawPath(right, paint)
      ..restore()
      // Стебель 2 × 7 со скруглением 1 в (35, 17).
      ..drawRRect(
        RRect.fromLTRBR(35, 17, 37, 24, const Radius.circular(1)),
        paint,
      );
  }

  @override
  bool shouldRepaint(_SproutPainter oldDelegate) => oldDelegate.color != color;
}
