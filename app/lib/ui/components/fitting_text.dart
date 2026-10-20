import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Текст, который переносится только по словам: если самое длинное слово
/// не помещается в ширину (узкий экран, крупный шрифт), кегль уменьшается
/// ровно настолько, чтобы оно поместилось. Flutter в такой ситуации рвёт
/// слово по буквам («Синхрон / изирова / ть») — этого не допускаем.
/// Слова, склеенные неразрывным пробелом (`640 ₽`), считаются одним словом.
class FittingText extends StatelessWidget {
  const FittingText(
    this.text, {
    super.key,
    required this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  final String text;
  final TextStyle style;
  final TextAlign? textAlign;

  /// Как у [Text]: не больше строк, лишнее — по [overflow].
  final int? maxLines;
  final TextOverflow? overflow;

  static final RegExp _spaces = RegExp(r'[ \t\n]+');

  /// Ширина самого длинного слова [text] стилем [style] (поверх
  /// `DefaultTextStyle`) с системным масштабом шрифта. Если она больше
  /// ширины места, [FittingText] уменьшит кегль; по ней же раскладка может
  /// решить дать тексту больше места (ExpenseRow).
  static double widestWord(BuildContext context, String text, TextStyle style) {
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final merged = DefaultTextStyle.of(context).style.merge(style);
    var widest = 0.0;
    for (final word in text.split(_spaces)) {
      if (word.isEmpty) continue;
      final painter = TextPainter(
        text: TextSpan(text: word, style: merged),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      widest = math.max(widest, painter.width);
      painter.dispose();
    }
    return widest;
  }

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final merged = DefaultTextStyle.of(context).style.merge(style);
    return LayoutBuilder(
      builder: (context, constraints) {
        var factor = 1.0;
        if (constraints.hasBoundedWidth) {
          final widest = widestWord(context, text, style);
          if (widest > constraints.maxWidth && widest > 0) {
            factor = constraints.maxWidth / widest;
          }
        }
        if (factor >= 1) {
          return Text(
            text,
            style: style,
            textAlign: textAlign,
            maxLines: maxLines,
            overflow: overflow,
          );
        }
        // Уменьшаем кегль (уже с учётом системного масштаба) с небольшим
        // запасом на округление ширины глифов.
        final size = scaler.scale(merged.fontSize ?? 14) * factor * 0.98;
        return Text(
          text,
          style: style.copyWith(fontSize: size),
          textAlign: textAlign,
          maxLines: maxLines,
          overflow: overflow,
          textScaler: TextScaler.noScaling,
        );
      },
    );
  }
}
