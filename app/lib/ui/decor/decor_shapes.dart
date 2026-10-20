import 'dart:ui';

/// Цвет узора: C1…C4 генератора → `decor-1…4` настроения.
enum DecorInk { c1, c2, c3, c4 }

/// Команда пути SVG: `M`, `L`, `C`, `Q`, `A`, `Z` с координатами.
final class PathCommand {
  const PathCommand(this.op, this.args);

  final String op;
  final List<double> args;
}

/// Фигура узора — то, что генератор декора в JS пишет как `<path>` или
/// `<circle>`. Координаты уже округлены до 0,01, как в JS (`f()`), —
/// именно такими они попали в Figma.
final class DecorElement {
  const DecorElement.path(
    this.commands, {
    this.fill,
    this.stroke,
    this.strokeWidth,
    this.roundCap = false,
    this.roundJoin = false,
    this.explicitNoFill = false,
  }) : cx = 0,
       cy = 0,
       r = 0;

  const DecorElement.circle(
    this.cx,
    this.cy,
    this.r, {
    this.fill,
    this.stroke,
    this.strokeWidth,
    this.explicitNoFill = false,
  }) : commands = null,
       roundCap = false,
       roundJoin = false;

  /// `null` — круг.
  final List<PathCommand>? commands;
  final double cx;
  final double cy;
  final double r;
  final DecorInk? fill;
  final DecorInk? stroke;
  final double? strokeWidth;
  final bool roundCap;
  final bool roundJoin;

  /// В SVG явно `fill="none"` (для сверки с JS; рисуется так же, как без
  /// заливки).
  final bool explicitNoFill;

  bool get isCircle => commands == null;

  /// Путь для рисования (`dart:ui`).
  Path toPath() {
    if (isCircle) {
      return Path()
        ..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r));
    }
    final path = Path();
    var current = Offset.zero;
    for (final c in commands!) {
      final a = c.args;
      switch (c.op) {
        case 'M':
          path.moveTo(a[0], a[1]);
          current = Offset(a[0], a[1]);
        case 'L':
          path.lineTo(a[0], a[1]);
          current = Offset(a[0], a[1]);
        case 'C':
          path.cubicTo(a[0], a[1], a[2], a[3], a[4], a[5]);
          current = Offset(a[4], a[5]);
        case 'Q':
          path.quadraticBezierTo(a[0], a[1], a[2], a[3]);
          current = Offset(a[2], a[3]);
        case 'A':
          // A rx ry rotation large-arc sweep x y; sweep 1 — по часовой.
          path.arcToPoint(
            Offset(a[5], a[6]),
            radius: Radius.elliptical(a[0], a[1]),
            rotation: a[2],
            largeArc: a[3] != 0,
            clockwise: a[4] != 0,
          );
          current = Offset(a[5], a[6]);
        case 'Z':
          path.close();
        default:
          throw StateError('unknown path command ${c.op} at $current');
      }
    }
    return path;
  }

  /// Атрибуты SVG как у JS-генератора (для сверки в тестах): цвета —
  /// маркерами `#FF0000`…`#FFFF00`, числа — как в JS.
  Map<String, String> svgAttributes() {
    final out = <String, String>{};
    if (isCircle) {
      out['cx'] = jsNumber(cx);
      out['cy'] = jsNumber(cy);
      out['r'] = jsNumber(r);
    } else {
      out['d'] = svgPathData(commands!);
    }
    if (fill != null) out['fill'] = _marker(fill!);
    if (explicitNoFill) out['fill'] = 'none';
    if (stroke != null) out['stroke'] = _marker(stroke!);
    if (strokeWidth != null) out['stroke-width'] = jsNumber(strokeWidth!);
    if (roundCap) out['stroke-linecap'] = 'round';
    if (roundJoin) out['stroke-linejoin'] = 'round';
    return out;
  }

  static String _marker(DecorInk ink) => switch (ink) {
    DecorInk.c1 => '#FF0000',
    DecorInk.c2 => '#00FF00',
    DecorInk.c3 => '#0000FF',
    DecorInk.c4 => '#FFFF00',
  };
}

/// Строка `d` пути в формате JS-генератора.
String svgPathData(List<PathCommand> commands) {
  final b = StringBuffer();
  for (final c in commands) {
    b
      ..write(c.op)
      ..write(c.args.map(jsNumber).join(' '));
  }
  return b.toString();
}

/// Число так, как его печатает JS после `+n.toFixed(2)`: `4`, `3.5`, `-0.4`.
String jsNumber(double v) {
  if (v == 0) return '0';
  if (v == v.truncateToDouble() && v.abs() < 1e15) return v.toInt().toString();
  return v.toString();
}

/// Округление как `+n.toFixed(2)` в JS (без `-0`).
double f2(double n) {
  final v = double.parse(n.toStringAsFixed(2));
  return v == 0 ? 0 : v;
}
