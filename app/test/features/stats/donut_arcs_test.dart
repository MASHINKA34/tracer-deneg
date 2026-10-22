import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/features/stats/donut_chart.dart';

const List<int> _octoberKopecks = [
  624000,
  318000,
  290000,
  215000,
  164000,
  110000,
  109000,
];

const List<(double, double)> _figmaArcs = [
  (-1.5532963275909424, 0.554166853427887),
  (0.5891668796539307, 1.6459990739822388),
  (1.6809990406036377, 2.641695022583008),
  (2.6766951084136963, 3.3798835277557373),
  (3.414883613586426, 3.9429666996002197),
  (3.977966785430908, 4.320644378662109),
  (4.355644702911377, 4.694889068603516),
];

void main() {
  test('7 сегментов октября совпадают с дугами 12:820: старт сверху, по '
      'часовой, по убыванию, зазор 0,035 рад между соседями', () {
    final arcs = donutArcs(_octoberKopecks);

    expect(arcs, hasLength(7));
    for (final (i, (start, end)) in _figmaArcs.indexed) {
      expect(arcs[i].start, closeTo(start, 1e-6), reason: 'start #$i');
      expect(arcs[i].start + arcs[i].sweep, closeTo(end, 1e-6), reason: '#$i');
    }
    for (var i = 1; i < arcs.length; i++) {
      final gap = arcs[i].start - (arcs[i - 1].start + arcs[i - 1].sweep);
      expect(gap, closeTo(donutGap, 1e-9));
    }
    final last = arcs.last.start + arcs.last.sweep;
    expect(arcs.first.start + 2 * math.pi - last, closeTo(donutGap, 1e-9));
  });

  test('одна категория — целое кольцо без зазора', () {
    final arcs = donutArcs([500]);

    expect(arcs, hasLength(1));
    expect(arcs.single.start, closeTo(-math.pi / 2, 1e-12));
    expect(arcs.single.sweep, closeTo(2 * math.pi, 1e-12));
  });

  test('нулевые суммы — пустые дуги, остальные без них как одна', () {
    final arcs = donutArcs([0, 700, 0]);

    expect(arcs[0].sweep, 0);
    expect(arcs[1].start, closeTo(-math.pi / 2, 1e-12));
    expect(arcs[1].sweep, closeTo(2 * math.pi, 1e-12));
    expect(arcs[2].sweep, 0);
  });

  test('все суммы нулевые или список пуст — рисовать нечего', () {
    expect(donutArcs(const []), isEmpty);
    expect(donutArcs([0, 0]).map((a) => a.sweep), [0, 0]);
  });

  test('крошечная доля не пропадает: дуга не тоньше 0,02 рад и по центру '
      'своего места', () {
    final arcs = donutArcs([100000, 1]);
    final slot = 2 * math.pi / 100001;
    final tiny = arcs[1];

    expect(tiny.sweep, donutMinSweep);
    expect(
      tiny.start + tiny.sweep / 2,
      closeTo(-math.pi / 2 + 2 * math.pi - slot / 2, 1e-9),
    );
  });
}
