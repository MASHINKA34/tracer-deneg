import 'dart:math' as math;

import 'package:flutter/widgets.dart';

const double donutSize = 132;

const double donutHoleRatio = 0.66;

const double donutGap = 0.035;

const double donutMinSweep = 0.02;

const double donutStart = -math.pi / 2;

final class DonutArc {
  const DonutArc(this.start, this.sweep);

  final double start;
  final double sweep;

  @override
  bool operator ==(Object other) =>
      other is DonutArc && other.start == start && other.sweep == sweep;

  @override
  int get hashCode => Object.hash(start, sweep);

  @override
  String toString() =>
      'DonutArc(${start.toStringAsFixed(4)}, ${sweep.toStringAsFixed(4)})';
}

List<DonutArc> donutArcs(List<int> weights, {double gap = donutGap}) {
  final total = weights.fold(0, (sum, w) => sum + math.max(w, 0));
  if (total == 0) {
    return [for (final _ in weights) const DonutArc(donutStart, 0)];
  }
  final withGaps = weights.where((w) => w > 0).length > 1;
  final arcs = <DonutArc>[];
  var start = donutStart;
  for (final weight in weights) {
    if (weight <= 0) {
      arcs.add(DonutArc(start, 0));
      continue;
    }
    final slot = 2 * math.pi * weight / total;
    final sweep = withGaps ? math.max(slot - gap, donutMinSweep) : slot;
    arcs.add(DonutArc(start + (slot - sweep) / 2, sweep));
    start += slot;
  }
  return arcs;
}

final class DonutSegment {
  const DonutSegment({required this.weight, required this.color});

  final int weight;
  final Color color;

  @override
  bool operator ==(Object other) =>
      other is DonutSegment && other.weight == weight && other.color == color;

  @override
  int get hashCode => Object.hash(weight, color);
}

class DonutChart extends StatelessWidget {
  const DonutChart({
    super.key,
    required this.segments,
    this.center,
    this.size = donutSize,
  });

  final List<DonutSegment> segments;
  final Widget? center;
  final double size;

  @override
  Widget build(BuildContext context) {
    final hole = size * donutHoleRatio;
    final center = this.center;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: DonutPainter(
          arcs: donutArcs([for (final s in segments) s.weight]),
          colors: [for (final s in segments) s.color],
        ),
        child: center == null
            ? null
            : Center(
                child: SizedBox(
                  width: hole * 0.8,
                  height: hole * 0.56,
                  child: FittedBox(fit: BoxFit.scaleDown, child: center),
                ),
              ),
      ),
    );
  }
}

class DonutPainter extends CustomPainter {
  DonutPainter({required this.arcs, required this.colors})
    : assert(arcs.length == colors.length);

  final List<DonutArc> arcs;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outer = Rect.fromCircle(
      center: center,
      radius: size.shortestSide / 2,
    );
    final inner = Rect.fromCircle(
      center: center,
      radius: size.shortestSide / 2 * donutHoleRatio,
    );
    for (var i = 0; i < arcs.length; i++) {
      final arc = arcs[i];
      if (arc.sweep <= 0) continue;
      final paint = Paint()
        ..color = colors[i]
        ..isAntiAlias = true;
      if (arc.sweep >= 2 * math.pi - 1e-9) {
        canvas.drawPath(
          Path()
            ..fillType = PathFillType.evenOdd
            ..addOval(outer)
            ..addOval(inner),
          paint,
        );
        continue;
      }
      canvas.drawPath(
        Path()
          ..arcTo(outer, arc.start, arc.sweep, true)
          ..arcTo(inner, arc.start + arc.sweep, -arc.sweep, false)
          ..close(),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant DonutPainter oldDelegate) =>
      !_listEquals(oldDelegate.arcs, arcs) ||
      !_listEquals(oldDelegate.colors, colors);

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
