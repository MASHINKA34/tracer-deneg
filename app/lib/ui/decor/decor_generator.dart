import 'dart:math' as math;

import 'decor_shapes.dart';
import 'mulberry32.dart';

/// Слой декора карточки месяца: 4 сезона и 11 праздников; у Хеллоуина два
/// слоя — милый для светлой темы и жуткий для тёмной (00-spec §6.3).
enum DecorLayer {
  winter('winter', 11),
  spring('spring', 23),
  summer('summer', 37),
  autumn('autumn', 41),
  newyear('newyear', 101),
  valentine('valentine', 102),
  defender('defender', 103),
  maslenitsa('maslenitsa', 104),
  women('women', 105),
  labour('labour', 106),
  victory('victory', 201),
  children('children', 202),
  knowledge('knowledge', 203),
  halloweenCute('halloween-cute', 204),
  halloweenSpooky('halloween-spooky', 205),
  birthday('birthday', 206);

  const DecorLayer(this.key, this.seed);

  /// Ключ генератора в JS (`node decor-generator.js <key>`).
  final String key;

  /// Сид mulberry32 — как в Figma.
  final int seed;

  bool get isSeason => index <= DecorLayer.autumn.index;
}

enum DecorRegion { top, left, right, bottom }

enum DecorMotion {
  blink,
  swing,
  beat,
  twinkle,
  flutter,
  spin,
  hop,
  sway,
  knock,
  flash,
  rise,
  string,
  ring,
  fall,
  confetti,
  bob,
  descend,
  thread,
  flapLeft,
  flapRight,
}

final class DecorMotionSpan {
  const DecorMotionSpan(
    this.motion,
    this.region,
    this.start,
    this.end,
    this.pivotX,
    this.pivotY, {
    this.order = 0,
    this.amount = 0,
  });

  final DecorMotion motion;
  final DecorRegion region;
  final int start;
  final int end;
  final double pivotX;
  final double pivotY;
  final int order;
  final double amount;

  bool covers(DecorRegion r, int index) =>
      r == region && index >= start && index < end;

  DecorMotionSpan shifted(double dx) => DecorMotionSpan(
    motion,
    region,
    start,
    end,
    pivotX + dx,
    pivotY,
    order: order,
    amount: amount,
  );

  @override
  String toString() =>
      'DecorMotionSpan(${motion.name} ${region.name}[$start..$end) '
      'pivot=(${pivotX.toStringAsFixed(2)}, ${pivotY.toStringAsFixed(2)}) '
      'order=$order amount=$amount)';
}

/// Узор по областям карточки — как `seasonRegions` / `holidayRegions`
/// генератора в JS: [top] — от левого верхнего угла карточки, [left] —
/// от (0, 60), [right] — от (W − 12, 60), [bottom] — от (0, H − 12).
final class DecorRegions {
  const DecorRegions({
    required this.top,
    required this.left,
    required this.right,
    required this.bottom,
    required this.width,
    required this.height,
    this.motions = const [],
  });

  final List<DecorElement> top;
  final List<DecorElement> left;
  final List<DecorElement> right;
  final List<DecorElement> bottom;
  final double width;
  final double height;
  final List<DecorMotionSpan> motions;

  int get elementCount =>
      top.length + left.length + right.length + bottom.length;

  List<DecorElement> of(DecorRegion region) => switch (region) {
    DecorRegion.top => top,
    DecorRegion.left => left,
    DecorRegion.right => right,
    DecorRegion.bottom => bottom,
  };
}

/// Ширина карточки, под которую нарисован декор в Figma.
const double decorDesignWidth = 336;

/// Верхняя полоса карточки и ширина боковых/нижней полос.
const double decorTop = 60;
const double decorSide = 12;

/// Узор слоя [layer] для карточки [width] × [height].
///
/// Перенос генератора из Figma 1:1: тот же mulberry32, сиды и порядок
/// вызовов случайных чисел, координаты округлены до 0,01 — на ширине 336
/// рисунок совпадает с Figma. Боковые полосы — под фактическую высоту.
/// Другая ширина (решение пользователя на этапе 03): элементы верхнего
/// края растягиваются пропорционально (x · W / 336, размеры прежние),
/// композиция между названием месяца и стрелками сдвигается вместе со
/// стрелками (на W − 336), нижняя полоса — циклом по фактической ширине.
DecorRegions generateDecor(
  DecorLayer layer, {
  double width = decorDesignWidth,
  double height = 421,
}) => _Gen(layer, width, height).run();

final class _Gen {
  _Gen(this.layer, this.w, this.h)
    : _random = Mulberry32(layer.seed),
      k = w / decorDesignWidth,
      dx = w - decorDesignWidth;

  final DecorLayer layer;
  final double w;
  final double h;
  final Mulberry32 _random;

  /// Растяжение верхнего края и сдвиг композиции у стрелок.
  final double k;
  final double dx;

  List<DecorElement> _out = [];
  DecorRegion _region = DecorRegion.top;
  final Map<List<DecorElement>, DecorRegion> _regions = Map.identity();
  final List<DecorMotionSpan> _motions = [];
  final Map<DecorMotion, int> _orders = {};

  double rnd() => _random.next();

  /// x верхнего края при ширине [w].
  double sx(double x) => x * k;

  DecorRegions run() {
    final top = <DecorElement>[];
    final left = <DecorElement>[];
    final right = <DecorElement>[];
    final bottom = <DecorElement>[];
    _regions
      ..[top] = DecorRegion.top
      ..[left] = DecorRegion.left
      ..[right] = DecorRegion.right
      ..[bottom] = DecorRegion.bottom;
    if (layer.isSeason) {
      _season(top, left, right, bottom);
    } else {
      _holiday(top, left, right, bottom);
    }
    return DecorRegions(
      top: top,
      left: left,
      right: right,
      bottom: bottom,
      width: w,
      height: h,
      motions: List.unmodifiable(_motions),
    );
  }

  /// Рисует [body] в [target] (порядок фигур = порядок в JS).
  void into(List<DecorElement> target, void Function() body) {
    final saved = _out;
    final savedRegion = _region;
    _out = target;
    _region = _regions[target]!;
    body();
    _out = saved;
    _region = savedRegion;
  }

  /// Фигуры из [body] — со сдвигом на [dx] по x (композиция у стрелок).
  void shifted(void Function() body) {
    final start = _out.length;
    final motionsStart = _motions.length;
    body();
    if (dx == 0) return;
    for (var i = start; i < _out.length; i++) {
      _out[i] = _translate(_out[i], dx);
    }
    for (var i = motionsStart; i < _motions.length; i++) {
      _motions[i] = _motions[i].shifted(dx);
    }
  }

  int nextOrder(DecorMotion m) {
    final order = _orders[m] ?? 0;
    _orders[m] = order + 1;
    return order;
  }

  void span(
    DecorMotion m,
    int start,
    int end,
    (double, double) pivot, {
    int? order,
    double amount = 0,
  }) => _motions.add(
    DecorMotionSpan(
      m,
      _region,
      start,
      end,
      pivot.$1,
      pivot.$2,
      order: order ?? nextOrder(m),
      amount: amount,
    ),
  );

  void moving(
    DecorMotion m,
    (double, double) pivot,
    void Function() body, {
    double amount = 0,
  }) {
    final start = _out.length;
    body();
    span(m, start, _out.length, pivot, amount: amount);
  }

  double get fallDistance => switch (_region) {
    DecorRegion.top => 10,
    DecorRegion.left || DecorRegion.right => 22,
    DecorRegion.bottom => 6,
  };

  // ---------- примитивы (как в JS) ----------

  static (double, double) rot(double x, double y, double a) =>
      (x * math.cos(a) - y * math.sin(a), x * math.sin(a) + y * math.cos(a));

  static List<double> pt(
    double cx,
    double cy,
    double x,
    double y, [
    double a = 0,
  ]) {
    final (rx, ry) = rot(x, y, a);
    return [f2(cx + rx), f2(cy + ry)];
  }

  static (double, double) at(
    double cx,
    double cy,
    double x,
    double y,
    double a,
  ) {
    final (rx, ry) = rot(x, y, a);
    return (rx + cx, ry + cy);
  }

  void poly(
    double cx,
    double cy,
    List<List<double>> pts,
    double a,
    DecorInk col,
  ) {
    final cmds = <PathCommand>[
      for (final (i, p) in pts.indexed)
        PathCommand(i == 0 ? 'M' : 'L', pt(cx, cy, p[0], p[1], a)),
      const PathCommand('Z', []),
    ];
    _out.add(DecorElement.path(cmds, fill: col));
  }

  void dot(double cx, double cy, double r, DecorInk col) =>
      _out.add(DecorElement.circle(f2(cx), f2(cy), f2(r), fill: col));

  void ring(double cx, double cy, double r, DecorInk col, double wd) =>
      _out.add(
        DecorElement.circle(
          f2(cx),
          f2(cy),
          f2(r),
          stroke: col,
          strokeWidth: f2(wd),
          explicitNoFill: true,
        ),
      );

  void ln(
    double cx,
    double cy,
    double x1,
    double y1,
    double x2,
    double y2,
    double a,
    DecorInk col,
    double wd,
  ) => _out.add(
    DecorElement.path(
      [
        PathCommand('M', pt(cx, cy, x1, y1, a)),
        PathCommand('L', pt(cx, cy, x2, y2, a)),
      ],
      stroke: col,
      strokeWidth: f2(wd),
      roundCap: true,
    ),
  );

  void pl(
    double cx,
    double cy,
    List<List<double>> pts,
    double a,
    DecorInk col,
    double wd,
  ) => _out.add(
    DecorElement.path(
      [
        for (final (i, p) in pts.indexed)
          PathCommand(i == 0 ? 'M' : 'L', pt(cx, cy, p[0], p[1], a)),
      ],
      stroke: col,
      strokeWidth: f2(wd),
      roundCap: true,
      roundJoin: true,
      explicitNoFill: true,
    ),
  );

  void rect(
    double cx,
    double cy,
    double wd,
    double ht,
    DecorInk col, [
    double a = 0,
    double ox = 0,
    double oy = 0,
  ]) => poly(
    cx,
    cy,
    [
      [ox - wd / 2, oy - ht / 2],
      [ox + wd / 2, oy - ht / 2],
      [ox + wd / 2, oy + ht / 2],
      [ox - wd / 2, oy + ht / 2],
    ],
    a,
    col,
  );

  void ell(
    double cx,
    double cy,
    double rx,
    double ry,
    DecorInk col, [
    double a = 0,
    double ox = 0,
    double oy = 0,
  ]) {
    const kk = 0.5523;
    List<double> q(double x, double y) => pt(cx, cy, ox + x, oy + y, a);
    _out.add(
      DecorElement.path([
        PathCommand('M', q(rx, 0)),
        PathCommand('C', [...q(rx, ry * kk), ...q(rx * kk, ry), ...q(0, ry)]),
        PathCommand('C', [
          ...q(-rx * kk, ry),
          ...q(-rx, ry * kk),
          ...q(-rx, 0),
        ]),
        PathCommand('C', [
          ...q(-rx, -ry * kk),
          ...q(-rx * kk, -ry),
          ...q(0, -ry),
        ]),
        PathCommand('C', [...q(rx * kk, -ry), ...q(rx, -ry * kk), ...q(rx, 0)]),
        const PathCommand('Z', []),
      ], fill: col),
    );
  }

  void star5(double cx, double cy, double r, DecorInk col, [double a = 0]) {
    final p = <List<double>>[];
    for (var j = 0; j < 10; j++) {
      final g = -math.pi / 2 + j * math.pi / 5;
      final rr = j.isOdd ? r * 0.45 : r;
      p.add([rr * math.cos(g), rr * math.sin(g)]);
    }
    poly(cx, cy, p, a, col);
  }

  void heart(double cx, double cy, double s, DecorInk col, [double a = 0]) {
    List<double> q(double x, double y) => pt(cx, cy, x * s, y * s, a);
    _out.add(
      DecorElement.path([
        PathCommand('M', q(0, 0.85)),
        PathCommand('C', [
          ...q(-1.15, 0.05),
          ...q(-0.6, -0.95),
          ...q(0, -0.38),
        ]),
        PathCommand('C', [...q(0.6, -0.95), ...q(1.15, 0.05), ...q(0, 0.85)]),
        const PathCommand('Z', []),
      ], fill: col),
    );
  }

  void sparkle(double cx, double cy, double r, DecorInk col) {
    final c = [f2(cx), f2(cy)];
    _out.add(
      DecorElement.path([
        PathCommand('M', [f2(cx), f2(cy - r)]),
        PathCommand('Q', [...c, f2(cx + r), f2(cy)]),
        PathCommand('Q', [...c, f2(cx), f2(cy + r)]),
        PathCommand('Q', [...c, f2(cx - r), f2(cy)]),
        PathCommand('Q', [...c, f2(cx), f2(cy - r)]),
        const PathCommand('Z', []),
      ], fill: col),
    );
  }

  // ---------- мотивы сезонов (S) ----------

  void sSnow(double cx, double cy, double r, DecorInk col) {
    final d = <PathCommand>[];
    for (var j = 0; j < 6; j++) {
      final a = j * math.pi / 3 - math.pi / 2;
      d
        ..add(PathCommand('M', [f2(cx), f2(cy)]))
        ..add(
          PathCommand('L', [
            f2(cx + r * math.cos(a)),
            f2(cy + r * math.sin(a)),
          ]),
        );
      final bx = cx + 0.55 * r * math.cos(a);
      final by = cy + 0.55 * r * math.sin(a);
      for (final s in const [-1, 1]) {
        final b = a + s * 0.8;
        d
          ..add(PathCommand('M', [f2(bx), f2(by)]))
          ..add(
            PathCommand('L', [
              f2(bx + 0.34 * r * math.cos(b)),
              f2(by + 0.34 * r * math.sin(b)),
            ]),
          );
      }
    }
    _out.add(
      DecorElement.path(
        d,
        stroke: col,
        strokeWidth: f2(math.max(1, r * 0.17)),
        roundCap: true,
        explicitNoFill: true,
      ),
    );
  }

  void sLeaf(double cx, double cy, double s, double ang, DecorInk col) {
    final pts =
        [
          [0.0, 0.9 * s],
          [0.78 * s, 0.45 * s],
          [0.72 * s, -0.5 * s],
          [0.0, -s],
          [-0.72 * s, -0.5 * s],
          [-0.78 * s, 0.45 * s],
        ].map((p) {
          final (rx, ry) = rot(p[0], p[1], ang);
          return [f2(cx + rx), f2(cy + ry)];
        }).toList();
    final [b, c1, c2, t, c3, c4] = pts;
    final (stx, sty) = rot(0, 1.4 * s, ang);
    _out
      ..add(
        DecorElement.path([
          PathCommand('M', b),
          PathCommand('C', [...c1, ...c2, ...t]),
          PathCommand('C', [...c3, ...c4, ...b]),
          const PathCommand('Z', []),
        ], fill: col),
      )
      ..add(
        DecorElement.path(
          [
            PathCommand('M', b),
            PathCommand('L', [f2(cx + stx), f2(cy + sty)]),
          ],
          stroke: col,
          strokeWidth: f2(math.max(0.9, s * 0.15)),
          roundCap: true,
        ),
      );
  }

  void sFlower(double cx, double cy, double r, DecorInk pc, DecorInk cc) {
    for (var j = 0; j < 5; j++) {
      final a = j * 2 * math.pi / 5 - math.pi / 2;
      dot(
        cx + 0.52 * r * math.cos(a),
        cy + 0.52 * r * math.sin(a),
        0.42 * r,
        pc,
      );
    }
    dot(cx, cy, 0.3 * r, cc);
  }

  void sSun(double cx, double cy, double r, DecorInk col) {
    final d = <PathCommand>[];
    for (var j = 0; j < 8; j++) {
      final a = j * math.pi / 4;
      d
        ..add(
          PathCommand('M', [
            f2(cx + 0.72 * r * math.cos(a)),
            f2(cy + 0.72 * r * math.sin(a)),
          ]),
        )
        ..add(
          PathCommand('L', [
            f2(cx + r * math.cos(a)),
            f2(cy + r * math.sin(a)),
          ]),
        );
    }
    dot(cx, cy, 0.46 * r, col);
    _out.add(
      DecorElement.path(
        d,
        stroke: col,
        strokeWidth: f2(math.max(1, 0.16 * r)),
        roundCap: true,
      ),
    );
  }

  void sMelon(double cx, double cy, double r, double ang) {
    List<double> p(double x, double y) {
      final (a, b) = rot(x, y, ang);
      return [f2(cx + a), f2(cy + b)];
    }

    _out
      ..add(
        DecorElement.path([
          PathCommand('M', p(-r, 0)),
          PathCommand('A', [f2(r), f2(r), 0, 0, 0, ...p(r, 0)]),
          const PathCommand('Z', []),
        ], fill: DecorInk.c3),
      )
      ..add(
        DecorElement.path([
          PathCommand('M', p(-0.76 * r, 0)),
          PathCommand('A', [
            f2(0.76 * r),
            f2(0.76 * r),
            0,
            0,
            0,
            ...p(0.76 * r, 0),
          ]),
          const PathCommand('Z', []),
        ], fill: DecorInk.c2),
      );
  }

  /// `SEASON_MOTIF[season]`.
  void motif(double cx, double cy, double s, int i, bool big) {
    switch (layer) {
      case DecorLayer.winter:
        if (i % 3 == 2 && big) {
          sparkle(cx, cy, s * 0.7, DecorInk.c2);
        } else {
          sSnow(cx, cy, s, i.isOdd ? DecorInk.c3 : DecorInk.c1);
        }
      case DecorLayer.spring:
        if (i % 3 == 2) {
          sLeaf(cx, cy, s * 0.7, rnd() * math.pi * 2, DecorInk.c2);
        } else {
          sFlower(cx, cy, s, DecorInk.c1, DecorInk.c3);
        }
      case DecorLayer.summer:
        if (i % 3 == 1) {
          sMelon(cx, cy, s * 0.95, (rnd() - 0.5) * 1.4);
        } else if (i % 3 == 2 && big) {
          sparkle(cx, cy, s * 0.7, DecorInk.c3);
        } else {
          sSun(cx, cy, s, DecorInk.c1);
        }
      case DecorLayer.autumn:
        sLeaf(
          cx,
          cy,
          s * 0.78,
          rnd() * math.pi * 2,
          const [DecorInk.c1, DecorInk.c2, DecorInk.c3][i % 3],
        );
      default:
        throw StateError('${layer.key} is not a season');
    }
  }

  void _season(
    List<DecorElement> top,
    List<DecorElement> left,
    List<DecorElement> right,
    List<DecorElement> bottom,
  ) {
    final sd = layer == DecorLayer.spring ? DecorInk.c1 : DecorInk.c2;
    into(top, () {
      for (final (i, x) in const [
        12.0,
        50.0,
        90.0,
        130.0,
        170.0,
        208.0,
        246.0,
        286.0,
        324.0,
      ].indexed) {
        // Порядок как в Figma: сначала размер, потом сдвиг по x и y.
        final s = 7 + rnd() * 3;
        motif(sx(x) + (rnd() - 0.5) * 8, 3 + rnd() * 5, s, i, true);
      }
      shifted(() {
        motif(204, 36, 10.5, 0, true);
        motif(232, 18, 6, 1, true);
        motif(186, 52, 4.5, 2, false);
        dot(226, 46, 1.8, sd);
      });
      dot(sx(160), 54, 1.6, sd);
      shifted(() => dot(244, 52, 1.5, DecorInk.c1));
      dot(sx(70), 16, 1.6, sd);
      dot(sx(300), 18, 1.6, sd);
      motif(6, 46, 4.4, 3, false);
      motif(w - 6, 54, 4.4, 4, false);
    });
    final sideH = h - decorTop - decorSide;
    var i = 0;
    for (double y = 10; y < sideH - 4; y += 22, i++) {
      into(left, () {
        if (i.isEven) {
          motif(6 + (rnd() - 0.5) * 1.5, y, 4.4, i, false);
        } else {
          dot(6, y, 1.5, sd);
        }
      });
      into(right, () {
        if (i.isOdd) {
          motif(6 + (rnd() - 0.5) * 1.5, y, 4.4, i + 1, false);
        } else {
          dot(6, y, 1.5, sd);
        }
      });
    }
    i = 0;
    into(bottom, () {
      for (double x = 34; x <= w - 34; x += 24, i++) {
        if (i.isEven) {
          motif(x, 6, 4.4, i, false);
        } else {
          dot(x, 6, 1.5, sd);
        }
      }
    });
  }

  // ---------- мотивы праздников (H) ----------

  void hLeaf(double cx, double cy, double s, double a, DecorInk col) {
    List<double> q(double x, double y) => pt(cx, cy, x * s, y * s, a);
    _out.add(
      DecorElement.path([
        PathCommand('M', q(0, 0.9)),
        PathCommand('C', [...q(0.78, 0.45), ...q(0.72, -0.5), ...q(0, -1)]),
        PathCommand('C', [...q(-0.72, -0.5), ...q(-0.78, 0.45), ...q(0, 0.9)]),
        const PathCommand('Z', []),
      ], fill: col),
    );
    ln(cx, cy, 0, 0.9 * s, 0, 1.35 * s, a, col, math.max(0.8, s * 0.15));
  }

  void hSun(double cx, double cy, double r, DecorInk col) {
    dot(cx, cy, 0.46 * r, col);
    for (var j = 0; j < 8; j++) {
      final g = j * math.pi / 4;
      ln(
        cx,
        cy,
        0.7 * r * math.cos(g),
        0.7 * r * math.sin(g),
        r * math.cos(g),
        r * math.sin(g),
        0,
        col,
        math.max(1, 0.16 * r),
      );
    }
  }

  void hTree(double cx, double cy, double s) {
    poly(
      cx,
      cy,
      [
        for (final p in const [
          [0.0, -1.0],
          [0.55, -0.15],
          [0.3, -0.15],
          [0.75, 0.6],
          [-0.75, 0.6],
          [-0.3, -0.15],
          [-0.55, -0.15],
        ])
          [p[0] * s, p[1] * s],
      ],
      0,
      DecorInk.c1,
    );
    star5(cx, cy - 1.05 * s, 0.32 * s, DecorInk.c4);
  }

  void hBall(double cx, double cy, double r, DecorInk col) {
    dot(cx, cy, r, col);
    rect(cx, cy - r - 0.15 * r, 0.7 * r, 0.45 * r, DecorInk.c4);
  }

  void hTangerine(double cx, double cy, double r) {
    dot(cx, cy, r, DecorInk.c3);
    hLeaf(cx + 0.45 * r, cy - 1.05 * r, 0.45 * r, 0.8, DecorInk.c1);
  }

  void hEnvelope(double cx, double cy, double wd, double a) {
    final ht = 0.66 * wd;
    List<double> q(double x, double y) => pt(cx, cy, x, y, a);
    rect(cx, cy, wd, ht, DecorInk.c4, a);
    _out
      ..add(
        DecorElement.path(
          [
            PathCommand('M', q(-wd / 2, -ht / 2)),
            PathCommand('L', q(wd / 2, -ht / 2)),
            PathCommand('L', q(wd / 2, ht / 2)),
            PathCommand('L', q(-wd / 2, ht / 2)),
            const PathCommand('Z', []),
          ],
          stroke: DecorInk.c1,
          strokeWidth: f2(math.max(0.8, wd * 0.05)),
          roundJoin: true,
          explicitNoFill: true,
        ),
      )
      ..add(
        DecorElement.path(
          [
            PathCommand('M', q(-wd / 2, -ht / 2)),
            PathCommand('L', q(0, ht * 0.12)),
            PathCommand('L', q(wd / 2, -ht / 2)),
          ],
          stroke: DecorInk.c1,
          strokeWidth: f2(math.max(0.8, wd * 0.05)),
          roundJoin: true,
          explicitNoFill: true,
        ),
      );
    final (hx, hy) = at(cx, cy, 0, ht * 0.08, a);
    heart(hx, hy, 0.17 * wd, DecorInk.c3, a);
  }

  void hRibbon(
    double cx,
    double cy,
    double wd,
    double ht,
    double a,
    DecorInk col,
  ) => poly(
    cx,
    cy,
    [
      [-wd / 2, -ht / 2],
      [wd / 2, -ht / 2],
      [wd / 2 - ht * 0.45, 0],
      [wd / 2, ht / 2],
      [-wd / 2, ht / 2],
      [-wd / 2 + ht * 0.45, 0],
    ],
    a,
    col,
  );

  void hPancake(double cx, double cy, double r) {
    dot(cx, cy, r, DecorInk.c4);
    ring(cx, cy, r * 0.94, DecorInk.c2, r * 0.12);
    dot(cx - 0.35 * r, cy - 0.2 * r, 0.13 * r, DecorInk.c2);
    dot(cx + 0.3 * r, cy + 0.25 * r, 0.11 * r, DecorInk.c2);
    dot(cx + 0.2 * r, cy - 0.4 * r, 0.09 * r, DecorInk.c2);
  }

  void hDiamond(double cx, double cy, double s, DecorInk col) =>
      rect(cx, cy, s, s, col, math.pi / 4);

  void hTulipHead(
    double cx,
    double cy,
    double s,
    DecorInk col, [
    double a = 0,
  ]) {
    List<double> q(double x, double y) => pt(cx, cy, x * s, y * s, a);
    _out.add(
      DecorElement.path([
        PathCommand('M', q(-0.5, -0.4)),
        PathCommand('L', q(-0.22, -0.08)),
        PathCommand('L', q(0, -0.5)),
        PathCommand('L', q(0.22, -0.08)),
        PathCommand('L', q(0.5, -0.4)),
        PathCommand('L', q(0.5, 0.05)),
        PathCommand('C', [...q(0.5, 0.55), ...q(-0.5, 0.55), ...q(-0.5, 0.05)]),
        const PathCommand('Z', []),
      ], fill: col),
    );
  }

  void hTulip(double cx, double cy, double s, DecorInk col, [double a = 0]) {
    ln(
      cx,
      cy,
      0,
      0.42 * s,
      0,
      1.3 * s,
      a,
      DecorInk.c2,
      math.max(0.9, 0.12 * s),
    );
    final (lx, ly) = at(cx, cy, 0.28 * s, 1.0 * s, a);
    hLeaf(lx, ly, 0.32 * s, a + 0.7, DecorInk.c2);
    hTulipHead(cx, cy, s, col, a);
  }

  void hMimosa(double cx, double cy, double s) {
    for (final p in const [
      [0.0, 0.0],
      [0.5, -0.3],
      [-0.45, -0.35],
      [0.15, -0.7],
      [-0.1, 0.45],
      [0.55, 0.35],
      [-0.55, 0.3],
    ]) {
      dot(cx + p[0] * s, cy + p[1] * s, 0.27 * s, DecorInk.c4);
    }
    hLeaf(cx + 0.35 * s, cy + 0.95 * s, 0.35 * s, 0.9, DecorInk.c2);
  }

  void hPlank(double cx, double cy, double wd, double ht, double a) {
    rect(cx, cy, wd, ht, DecorInk.c4, a);
    ln(
      cx,
      cy,
      -0.42 * wd,
      -0.18 * ht,
      0.3 * wd,
      -0.18 * ht,
      a,
      DecorInk.c3,
      math.max(0.5, ht * 0.08),
    );
    ln(
      cx,
      cy,
      -0.25 * wd,
      0.2 * ht,
      0.42 * wd,
      0.2 * ht,
      a,
      DecorInk.c3,
      math.max(0.5, ht * 0.08),
    );
    final (ax, ay) = at(cx, cy, -0.4 * wd, 0, a);
    dot(ax, ay, math.max(0.6, 0.13 * ht), DecorInk.c2);
    final (bx, by) = at(cx, cy, 0.4 * wd, 0, a);
    dot(bx, by, math.max(0.6, 0.13 * ht), DecorInk.c2);
  }

  void hHammer(double cx, double cy, double s, double a) {
    rect(cx, cy, 0.2 * s, 1.1 * s, DecorInk.c3, a, 0, 0.2 * s);
    rect(cx, cy, 0.26 * s, 0.36 * s, DecorInk.c1, a, 0, 0.6 * s);
    rect(cx, cy, 0.85 * s, 0.3 * s, DecorInk.c2, a, 0, -0.42 * s);
  }

  void hNail(double cx, double cy, double s, double a) {
    ln(
      cx,
      cy,
      0,
      -0.45 * s,
      0,
      0.5 * s,
      a,
      DecorInk.c2,
      math.max(0.7, 0.12 * s),
    );
    rect(cx, cy, 0.45 * s, 0.13 * s, DecorInk.c2, a, 0, -0.5 * s);
  }

  void hCarnHead(double cx, double cy, double s) {
    dot(cx, cy - 0.12 * s, 0.42 * s, DecorInk.c1);
    dot(cx - 0.32 * s, cy - 0.02 * s, 0.3 * s, DecorInk.c1);
    dot(cx + 0.32 * s, cy - 0.02 * s, 0.3 * s, DecorInk.c1);
    dot(cx - 0.2 * s, cy - 0.5 * s, 0.19 * s, DecorInk.c1);
    dot(cx, cy - 0.56 * s, 0.19 * s, DecorInk.c1);
    dot(cx + 0.2 * s, cy - 0.5 * s, 0.19 * s, DecorInk.c1);
  }

  void hCarnation(double cx, double cy, double s, double a) {
    final (hx, hy) = at(cx, cy, 0, 0, a);
    ln(cx, cy, 0, 0.4 * s, 0, 1.5 * s, a, DecorInk.c2, math.max(0.9, 0.11 * s));
    final (lx, ly) = at(cx, cy, 0.22 * s, 1.0 * s, a);
    hLeaf(lx, ly, 0.28 * s, a + 0.8, DecorInk.c2);
    poly(
      cx,
      cy,
      [
        [-0.2 * s, 0.18 * s],
        [0.2 * s, 0.18 * s],
        [0.09 * s, 0.48 * s],
        [-0.09 * s, 0.48 * s],
      ],
      a,
      DecorInk.c2,
    );
    hCarnHead(hx, hy, s);
  }

  void hSalute(double cx, double cy, double r, DecorInk col) {
    for (var j = 0; j < 10; j++) {
      final g = j * math.pi / 5;
      ln(
        cx,
        cy,
        0.3 * r * math.cos(g),
        0.3 * r * math.sin(g),
        0.85 * r * math.cos(g),
        0.85 * r * math.sin(g),
        0,
        col,
        math.max(0.8, 0.09 * r),
      );
      dot(
        cx + r * math.cos(g),
        cy + r * math.sin(g),
        math.max(0.6, 0.09 * r),
        col,
      );
    }
  }

  void hBalloon(double cx, double cy, double s, DecorInk col, [double a = 0]) {
    ell(cx, cy, 0.72 * s, 0.92 * s, col, a);
    poly(
      cx,
      cy,
      [
        [-0.14 * s, 1.0 * s],
        [0.14 * s, 1.0 * s],
        [0, 0.86 * s],
      ],
      a,
      col,
    );
    _out.add(
      DecorElement.path(
        [
          PathCommand('M', pt(cx, cy, 0, s, a)),
          PathCommand('Q', [
            ...pt(cx, cy, 0.3 * s, 1.5 * s, a),
            ...pt(cx, cy, 0, 2.0 * s, a),
          ]),
        ],
        stroke: col,
        strokeWidth: f2(math.max(0.5, 0.08 * s)),
        roundCap: true,
        explicitNoFill: true,
      ),
    );
  }

  void hConfetti(double cx, double cy, double s, DecorInk col, double a) =>
      rect(cx, cy, s, s * 0.45, col, a);

  void hPencil(double cx, double cy, double len, double a) {
    rect(cx, cy, len * 0.72, len * 0.18, DecorInk.c4, a, -0.03 * len, 0);
    poly(
      cx,
      cy,
      [
        [0.33 * len, -0.09 * len],
        [0.5 * len, 0],
        [0.33 * len, 0.09 * len],
      ],
      a,
      DecorInk.c1,
    );
    rect(cx, cy, 0.1 * len, 0.18 * len, DecorInk.c2, a, -0.44 * len, 0);
  }

  void hNotebook(double cx, double cy, double wd, double a) {
    rect(cx, cy, wd, 1.3 * wd, DecorInk.c3, a);
    rect(cx, cy, 0.56 * wd, 0.24 * wd, DecorInk.c4, a, 0.06 * wd, -0.2 * wd);
    for (final y in const [-0.42, -0.14, 0.14, 0.42]) {
      final (px, py) = at(cx, cy, -0.38 * wd, y * wd, a);
      dot(px, py, math.max(0.5, 0.07 * wd), DecorInk.c4);
    }
  }

  void hBell(double cx, double cy, double s) {
    List<double> q(double x, double y) => pt(cx, cy, x * s, y * s, 0);
    _out.add(
      DecorElement.path([
        PathCommand('M', q(-0.6, 0.45)),
        PathCommand('C', [...q(-0.6, -0.1), ...q(-0.45, -0.7), ...q(0, -0.7)]),
        PathCommand('C', [...q(0.45, -0.7), ...q(0.6, -0.1), ...q(0.6, 0.45)]),
        PathCommand('L', q(0.78, 0.62)),
        PathCommand('L', q(-0.78, 0.62)),
        const PathCommand('Z', []),
      ], fill: DecorInk.c4),
    );
    dot(cx, cy + 0.74 * s, 0.16 * s, DecorInk.c4);
    poly(
      cx,
      cy,
      [
        [0, -0.72 * s],
        [-0.42 * s, -0.98 * s],
        [-0.42 * s, -0.5 * s],
      ],
      0,
      DecorInk.c1,
    );
    poly(
      cx,
      cy,
      [
        [0, -0.72 * s],
        [0.42 * s, -0.98 * s],
        [0.42 * s, -0.5 * s],
      ],
      0,
      DecorInk.c1,
    );
  }

  void hPumpkin(double cx, double cy, double s) {
    ell(cx - 0.32 * s, cy, 0.42 * s, 0.5 * s, DecorInk.c1);
    ell(cx + 0.32 * s, cy, 0.42 * s, 0.5 * s, DecorInk.c1);
    ell(cx, cy, 0.46 * s, 0.56 * s, DecorInk.c1);
    rect(cx, cy - 0.62 * s, 0.15 * s, 0.3 * s, DecorInk.c2);
    hLeaf(cx + 0.26 * s, cy - 0.66 * s, 0.18 * s, 1.2, DecorInk.c2);
  }

  void hCandy(double cx, double cy, double s, double a) {
    ell(cx, cy, 0.5 * s, 0.34 * s, DecorInk.c3, a);
    poly(
      cx,
      cy,
      [
        [-0.42 * s, 0],
        [-0.85 * s, -0.32 * s],
        [-0.85 * s, 0.32 * s],
      ],
      a,
      DecorInk.c3,
    );
    poly(
      cx,
      cy,
      [
        [0.42 * s, 0],
        [0.85 * s, -0.32 * s],
        [0.85 * s, 0.32 * s],
      ],
      a,
      DecorInk.c3,
    );
    ln(
      cx,
      cy,
      -0.1 * s,
      -0.3 * s,
      0.1 * s,
      0.3 * s,
      a,
      DecorInk.c4,
      math.max(0.6, 0.1 * s),
    );
  }

  void hLollipop(double cx, double cy, double s) {
    ln(cx, cy, 0, 0.3 * s, 0, 1.3 * s, 0, DecorInk.c3, math.max(0.7, 0.12 * s));
    dot(cx, cy, 0.5 * s, DecorInk.c3);
    ring(cx, cy, 0.26 * s, DecorInk.c4, math.max(0.6, 0.1 * s));
  }

  void hGhost(double cx, double cy, double s) {
    List<double> q(double x, double y) => pt(cx, cy, x * s, y * s, 0);
    _out.add(
      DecorElement.path(
        [
          PathCommand('M', q(-0.6, 0.7)),
          PathCommand('L', q(-0.6, -0.1)),
          PathCommand('C', [
            ...q(-0.6, -0.9),
            ...q(0.6, -0.9),
            ...q(0.6, -0.1),
          ]),
          PathCommand('L', q(0.6, 0.7)),
          PathCommand('L', q(0.3, 0.5)),
          PathCommand('L', q(0, 0.7)),
          PathCommand('L', q(-0.3, 0.5)),
          const PathCommand('Z', []),
        ],
        fill: DecorInk.c4,
        stroke: DecorInk.c3,
        strokeWidth: f2(math.max(0.7, 0.06 * s)),
        roundJoin: true,
      ),
    );
    dot(cx - 0.2 * s, cy - 0.15 * s, 0.09 * s, DecorInk.c3);
    dot(cx + 0.2 * s, cy - 0.15 * s, 0.09 * s, DecorInk.c3);
    ell(cx, cy + 0.12 * s, 0.08 * s, 0.11 * s, DecorInk.c3);
  }

  void hWeb(double ox, double oy, double radius, double sxSign, double sySign) {
    final ang = [
      for (final t in const [0.0, 0.22, 0.45, 0.68, 0.9]) t * math.pi / 2,
    ];
    for (final g in ang) {
      _out.add(
        DecorElement.path(
          [
            PathCommand('M', [f2(ox), f2(oy)]),
            PathCommand('L', [
              f2(ox + sxSign * radius * math.cos(g)),
              f2(oy + sySign * radius * math.sin(g)),
            ]),
          ],
          stroke: DecorInk.c1,
          strokeWidth: 0.8,
          roundCap: true,
        ),
      );
    }
    for (final rr in [
      for (final t in const [0.35, 0.62, 0.88]) t * radius,
    ]) {
      final d = <PathCommand>[];
      for (var j = 0; j < ang.length - 1; j++) {
        final a1 = ang[j], a2 = ang[j + 1], am = (a1 + a2) / 2;
        final p1 = [
          ox + sxSign * rr * math.cos(a1),
          oy + sySign * rr * math.sin(a1),
        ];
        final p2 = [
          ox + sxSign * rr * math.cos(a2),
          oy + sySign * rr * math.sin(a2),
        ];
        final c = [
          ox + sxSign * rr * 0.8 * math.cos(am),
          oy + sySign * rr * 0.8 * math.sin(am),
        ];
        if (j == 0) d.add(PathCommand('M', [f2(p1[0]), f2(p1[1])]));
        d.add(PathCommand('Q', [f2(c[0]), f2(c[1]), f2(p2[0]), f2(p2[1])]));
      }
      _out.add(
        DecorElement.path(
          d,
          stroke: DecorInk.c1,
          strokeWidth: 0.7,
          explicitNoFill: true,
        ),
      );
    }
  }

  void hSpider(double cx, double cy, double s, double top) {
    _out.add(
      DecorElement.path(
        [
          PathCommand('M', [f2(cx), f2(top)]),
          PathCommand('L', [f2(cx), f2(cy - 0.5 * s)]),
        ],
        stroke: DecorInk.c1,
        strokeWidth: 0.6,
      ),
    );
    for (final sd in const [-1, 1]) {
      for (var j = 0; j < 4; j++) {
        pl(
          0,
          0,
          [
            [cx + sd * 0.3 * s, cy - 0.2 * s + j * 0.15 * s],
            [cx + sd * 0.8 * s, cy - 0.6 * s + j * 0.32 * s],
            [cx + sd * 1.1 * s, cy + 0.05 * s + j * 0.25 * s],
          ],
          0,
          DecorInk.c2,
          math.max(0.6, 0.12 * s),
        );
      }
    }
    dot(cx, cy, 0.5 * s, DecorInk.c2);
    dot(cx, cy - 0.55 * s, 0.32 * s, DecorInk.c2);
    dot(cx - 0.12 * s, cy - 0.6 * s, 0.08 * s, DecorInk.c3);
    dot(cx + 0.12 * s, cy - 0.6 * s, 0.08 * s, DecorInk.c3);
  }

  void hBat(double cx, double cy, double s, double a) {
    const wing = [
      [0.12, -0.1],
      [0.5, -0.45],
      [1.05, -0.25],
      [0.92, 0.02],
      [0.72, -0.04],
      [0.6, 0.18],
      [0.42, 0.04],
      [0.2, 0.14],
    ];
    poly(
      cx,
      cy,
      [
        for (final p in wing) [p[0] * s, p[1] * s],
      ],
      a,
      DecorInk.c2,
    );
    poly(
      cx,
      cy,
      [
        for (final p in wing) [-p[0] * s, p[1] * s],
      ],
      a,
      DecorInk.c2,
    );
    ell(cx, cy, 0.18 * s, 0.26 * s, DecorInk.c2, a);
    poly(
      cx,
      cy,
      [
        [-0.13 * s, -0.18 * s],
        [-0.08 * s, -0.42 * s],
        [0, -0.2 * s],
      ],
      a,
      DecorInk.c2,
    );
    poly(
      cx,
      cy,
      [
        [0.13 * s, -0.18 * s],
        [0.08 * s, -0.42 * s],
        [0, -0.2 * s],
      ],
      a,
      DecorInk.c2,
    );
    final (ex1, ey1) = at(cx, cy, -0.07 * s, -0.1 * s, a);
    dot(ex1, ey1, math.max(0.35, 0.045 * s), DecorInk.c3);
    final (ex2, ey2) = at(cx, cy, 0.07 * s, -0.1 * s, a);
    dot(ex2, ey2, math.max(0.35, 0.045 * s), DecorInk.c3);
  }

  void hMoon(double cx, double cy, double r) {
    dot(cx, cy, r, DecorInk.c4);
    dot(cx - 0.3 * r, cy - 0.2 * r, 0.15 * r, DecorInk.c1);
    dot(cx + 0.28 * r, cy + 0.3 * r, 0.12 * r, DecorInk.c1);
    dot(cx + 0.35 * r, cy - 0.35 * r, 0.09 * r, DecorInk.c1);
  }

  void hEyes(double cx, double cy, double s) {
    dot(cx - 0.42 * s, cy, 0.32 * s, DecorInk.c3);
    dot(cx + 0.42 * s, cy, 0.32 * s, DecorInk.c3);
  }

  void hHat(double cx, double cy, double s, double a) {
    poly(
      cx,
      cy,
      [
        [0, -0.8 * s],
        [0.45 * s, 0.5 * s],
        [-0.45 * s, 0.5 * s],
      ],
      a,
      DecorInk.c3,
    );
    ln(
      cx,
      cy,
      -0.24 * s,
      -0.1 * s,
      0.24 * s,
      -0.1 * s,
      a,
      DecorInk.c4,
      math.max(0.6, 0.11 * s),
    );
    ln(
      cx,
      cy,
      -0.36 * s,
      0.25 * s,
      0.36 * s,
      0.25 * s,
      a,
      DecorInk.c4,
      math.max(0.6, 0.11 * s),
    );
    final (px, py) = at(cx, cy, 0, -0.86 * s, a);
    dot(px, py, 0.16 * s, DecorInk.c1);
  }

  void hCake(double cx, double cy, double s) {
    rect(cx, cy, 1.8 * s, 0.7 * s, DecorInk.c1, 0, 0, 0.3 * s);
    rect(cx, cy, 1.3 * s, 0.55 * s, DecorInk.c3, 0, 0, -0.32 * s);
    for (final x in const [-0.35, 0.0, 0.35]) {
      ln(
        cx,
        cy,
        x * s,
        -0.62 * s,
        x * s,
        -0.95 * s,
        0,
        DecorInk.c2,
        math.max(0.7, 0.11 * s),
      );
      ell(cx + x * s, cy - 1.07 * s, 0.08 * s, 0.13 * s, DecorInk.c4);
    }
    for (final x in const [-0.6, -0.2, 0.2, 0.6]) {
      dot(cx + x * s, cy - 0.04 * s, 0.09 * s, DecorInk.c4);
    }
  }

  static const _cols = [DecorInk.c1, DecorInk.c2, DecorInk.c3, DecorInk.c4];

  // ---------- праздники: top / edge / gap / side ----------

  bool get _hasEdge => layer != DecorLayer.newyear;

  void hTop() {
    switch (layer) {
      case DecorLayer.newyear:
        double wy(double x) => 8 + 3.5 * math.sin(x / 26);
        final d = <PathCommand>[
          for (double x = -6; x <= 342; x += 6)
            PathCommand(x == -6 ? 'M' : 'L', [f2(sx(x)), f2(wy(x))]),
        ];
        _out.add(
          DecorElement.path(
            d,
            stroke: DecorInk.c1,
            strokeWidth: 1.3,
            roundCap: true,
            explicitNoFill: true,
          ),
        );
        var j = 0;
        for (double x = 10; x < 336; x += 21, j++) {
          final y = wy(x) + 4.6;
          rect(sx(x), y - 3.4, 2.4, 1.8, DecorInk.c1);
          ell(
            sx(x),
            y,
            2.6,
            3.6,
            const [DecorInk.c2, DecorInk.c4, DecorInk.c3][j % 3],
            (rnd() - 0.5) * 0.5,
          );
        }
      case DecorLayer.halloweenSpooky:
        hWeb(0, 0, 32, 1, 1);
        hWeb(w, 0, 32, -1, 1);
      default:
        break;
    }
  }

  void hEdge(double x, double y, double s, int i) {
    switch (layer) {
      case DecorLayer.valentine:
        if (i % 3 == 1) {
          hEnvelope(x, y + 3, s * 1.7, (rnd() - 0.5) * 0.5);
        } else {
          heart(
            x,
            y,
            s * 0.85,
            const [DecorInk.c1, DecorInk.c2, DecorInk.c3][i % 3],
            (rnd() - 0.5) * 0.6,
          );
        }
      case DecorLayer.defender:
        if (i.isOdd) {
          hRibbon(
            x,
            y + 2,
            s * 2.4,
            s * 0.9,
            (rnd() - 0.5) * 0.6,
            const [DecorInk.c1, DecorInk.c3][(i ~/ 2) % 2],
          );
        } else {
          star5(
            x,
            y,
            s * 0.95,
            const [DecorInk.c4, DecorInk.c2][(i ~/ 2) % 2],
            rnd() * 0.6,
          );
        }
      case DecorLayer.maslenitsa:
        if (i.isOdd) {
          hSun(x, y, s, DecorInk.c4);
        } else {
          hPancake(x, y + 1, s * 0.85);
          hDiamond(x + 19, y + 6, 3, DecorInk.c1);
        }
      case DecorLayer.women:
        if (i.isOdd) {
          hMimosa(x, y + 1, s * 0.75);
        } else {
          hTulipHead(
            x,
            y + 1,
            s * 0.95,
            const [DecorInk.c1, DecorInk.c3][(i ~/ 2) % 2],
            (rnd() - 0.5) * 0.4,
          );
        }
      case DecorLayer.labour:
        if (i.isOdd) {
          hHammer(x, y + 2, s * 1.05, (rnd() - 0.5) * 1.2);
        } else {
          hPlank(x, y + 1, s * 2.6, s * 0.75, (rnd() - 0.5) * 0.5);
        }
      case DecorLayer.victory:
        if (i.isOdd) {
          star5(x, y, s * 0.7, DecorInk.c3, rnd());
        } else {
          hSalute(
            x,
            y + 2,
            s * 1.1,
            const [DecorInk.c4, DecorInk.c1][(i ~/ 2) % 2],
          );
        }
      case DecorLayer.children:
        if (i.isOdd) {
          hConfetti(x, y + 5, s * 0.55, _cols[i % 4], rnd() * 3);
          hConfetti(x + 8, y + 2, s * 0.45, _cols[(i + 1) % 4], rnd() * 3);
        } else {
          hBalloon(x, y, s * 0.85, _cols[(i ~/ 2) % 4], (rnd() - 0.5) * 0.4);
        }
      case DecorLayer.knowledge:
        if (i % 3 == 0) {
          hPencil(x, y + 2, s * 2.6, (rnd() - 0.5) * 1.0);
        } else if (i % 3 == 1) {
          hLeaf(
            x,
            y + 2,
            s * 0.75,
            rnd() * 6.28,
            const [DecorInk.c1, DecorInk.c2][i % 2],
          );
        } else {
          hNotebook(x, y + 2, s * 1.1, (rnd() - 0.5) * 0.6);
        }
      case DecorLayer.halloweenCute:
        if (i % 3 == 0) {
          hPumpkin(x, y + 2, s * 0.95);
        } else if (i % 3 == 1) {
          hCandy(x, y + 2, s * 0.8, (rnd() - 0.5) * 0.8);
        } else {
          hLollipop(x, y, s * 0.6);
        }
      case DecorLayer.halloweenSpooky:
        if (i == 0 || i == 8) return;
        if (i.isOdd) {
          hBat(x, y + 5, s * 0.95, (rnd() - 0.5) * 0.5);
        } else {
          hEyes(x, y + 7, s * 0.42);
        }
      case DecorLayer.birthday:
        if (i % 3 == 0) {
          hBalloon(x, y, s * 0.85, _cols[(i ~/ 3) % 4], (rnd() - 0.5) * 0.4);
        } else if (i % 3 == 1) {
          hConfetti(x, y + 4, s * 0.55, _cols[i % 4], rnd() * 3);
          hConfetti(x + 9, y + 1, s * 0.45, _cols[(i + 2) % 4], rnd() * 3);
        } else {
          hHat(x, y + 3, s * 0.85, (rnd() - 0.5) * 0.6);
        }
      default:
        throw StateError('${layer.key} has no edge motif');
    }
  }

  void hGap() {
    switch (layer) {
      case DecorLayer.newyear:
        hTree(212, 40, 12);
        hBall(240, 27, 4.2, DecorInk.c2);
        hTangerine(188, 50, 4);
        sparkle(232, 47, 3, DecorInk.c4);
        sparkle(196, 24, 2.4, DecorInk.c4);
      case DecorLayer.valentine:
        hEnvelope(212, 37, 24, -0.15);
        heart(238, 21, 5.5, DecorInk.c3, 0.3);
        heart(190, 50, 3.6, DecorInk.c2, -0.3);
        heart(228, 53, 2.6, DecorInk.c1, 0.2);
      case DecorLayer.defender:
        star5(212, 36, 13, DecorInk.c4);
        star5(212, 37, 5.5, DecorInk.c2);
        hRibbon(240, 21, 18, 6, -0.3, DecorInk.c1);
        star5(188, 50, 4, DecorInk.c2, 0.3);
      case DecorLayer.maslenitsa:
        for (var j = 0; j < 4; j++) {
          ell(212, 47 - j * 4.2, 14, 3.6, j.isOdd ? DecorInk.c2 : DecorInk.c4);
        }
        dot(212, 30, 2.8, DecorInk.c1);
        hSun(240, 20, 7.5, DecorInk.c4);
        hDiamond(188, 50, 3.4, DecorInk.c1);
      case DecorLayer.women:
        hTulip(204, 30, 10, DecorInk.c1, -0.18);
        hTulip(220, 34, 8.5, DecorInk.c3, 0.2);
        hMimosa(241, 21, 5);
        hMimosa(187, 50, 3.4);
      case DecorLayer.labour:
        hHammer(213, 35, 17, -0.6);
        hPlank(239, 22, 18, 5.5, 0.25);
        hNail(188, 48, 7, 0.4);
        hNail(232, 51, 6, -0.3);
      case DecorLayer.victory:
        hCarnation(203, 33, 8.5, -0.3);
        hCarnation(216, 31, 9, 0.02);
        hCarnation(229, 34, 8.5, 0.32);
        hSalute(188, 47, 5, DecorInk.c4);
      case DecorLayer.children:
        hBalloon(203, 30, 8, DecorInk.c1, -0.25);
        hBalloon(217, 25, 9, DecorInk.c4, 0);
        hBalloon(231, 31, 8, DecorInk.c3, 0.25);
        hConfetti(190, 50, 3.4, DecorInk.c2, 0.6);
        hConfetti(242, 50, 3, DecorInk.c1, 1.2);
      case DecorLayer.knowledge:
        hBell(212, 35, 12);
        hLeaf(239, 22, 6, 0.8, DecorInk.c1);
        hLeaf(189, 49, 4, 2.1, DecorInk.c2);
        hPencil(236, 50, 12, -0.4);
      case DecorLayer.halloweenCute:
        hGhost(212, 34, 13);
        hPumpkin(240, 24, 6.5);
        hCandy(189, 50, 4.2, 0.4);
        hCandy(234, 50, 3.4, -0.5);
      case DecorLayer.halloweenSpooky:
        hMoon(214, 30, 11);
        hBat(243, 19, 8, -0.25);
        hSpider(188, 42, 4.6, 0);
        hEyes(230, 51, 3);
        hBat(198, 52, 4.5, 0.3);
      case DecorLayer.birthday:
        hCake(212, 39, 11);
        hBalloon(240, 21, 7, DecorInk.c1, 0.15);
        hConfetti(190, 48, 3.4, DecorInk.c4, 0.5);
        hConfetti(198, 26, 3, DecorInk.c2, 1.1);
        hConfetti(236, 50, 3, DecorInk.c3, 2.0);
      default:
        throw StateError('${layer.key} has no gap composition');
    }
  }

  void hSide(double cx, double cy, int i) {
    switch (layer) {
      case DecorLayer.newyear:
        if (i % 3 == 0) {
          hBall(cx, cy, 3.3, const [DecorInk.c2, DecorInk.c4][(i ~/ 3) % 2]);
        } else if (i % 3 == 1) {
          dot(cx, cy, 1.4, DecorInk.c4);
        } else {
          hTree(cx, cy + 1, 4.3);
        }
      case DecorLayer.valentine:
        if (i.isOdd) {
          dot(cx, cy, 1.4, DecorInk.c2);
        } else {
          heart(
            cx,
            cy,
            3.5,
            const [DecorInk.c1, DecorInk.c3][(i ~/ 2) % 2],
            (rnd() - 0.5) * 0.5,
          );
        }
      case DecorLayer.defender:
        if (i.isOdd) {
          dot(cx, cy, 1.4, DecorInk.c3);
        } else {
          star5(cx, cy, 3.9, const [DecorInk.c4, DecorInk.c2][(i ~/ 2) % 2]);
        }
      case DecorLayer.maslenitsa:
        if (i % 3 == 0) {
          hPancake(cx, cy, 4);
        } else if (i % 3 == 1) {
          hDiamond(cx, cy, 2.4, DecorInk.c1);
        } else {
          hSun(cx, cy, 4.4, DecorInk.c4);
        }
      case DecorLayer.women:
        if (i.isOdd) {
          dot(cx, cy, 1.5, DecorInk.c4);
        } else {
          hTulipHead(
            cx,
            cy,
            3.9,
            const [DecorInk.c1, DecorInk.c3][(i ~/ 2) % 2],
          );
        }
      case DecorLayer.labour:
        if (i % 3 == 0) {
          hHammer(cx, cy, 5, rnd() - 0.5);
        } else if (i % 3 == 1) {
          dot(cx, cy, 1.4, DecorInk.c4);
        } else {
          hNail(cx, cy, 6.5, (rnd() - 0.5) * 0.6);
        }
      case DecorLayer.victory:
        if (i.isOdd) {
          dot(cx, cy, 1.3, DecorInk.c4);
        } else {
          star5(cx, cy, 3.6, DecorInk.c3);
        }
      case DecorLayer.children:
        if (i.isOdd) {
          hConfetti(cx, cy, 3.2, _cols[i % 4], rnd() * 3);
        } else {
          hBalloon(cx, cy - 2, 3.4, _cols[(i ~/ 2) % 4]);
        }
      case DecorLayer.knowledge:
        if (i.isOdd) {
          dot(cx, cy, 1.4, DecorInk.c4);
        } else {
          hLeaf(
            cx,
            cy,
            3.4,
            rnd() * 6.28,
            const [DecorInk.c1, DecorInk.c2][(i ~/ 2) % 2],
          );
        }
      case DecorLayer.halloweenCute:
        if (i % 3 == 0) {
          hPumpkin(cx, cy, 4.4);
        } else if (i % 3 == 1) {
          dot(cx, cy, 1.4, DecorInk.c3);
        } else {
          hCandy(cx, cy, 3.8, rnd() - 0.5);
        }
      case DecorLayer.halloweenSpooky:
        if (i % 3 == 0) {
          hBat(cx, cy, 3.6, (rnd() - 0.5) * 0.5);
        } else if (i % 3 == 1) {
          hEyes(cx, cy, 2.6);
        } else {
          dot(cx, cy, 0.9, DecorInk.c1);
        }
      case DecorLayer.birthday:
        if (i.isOdd) {
          hConfetti(cx, cy, 3.2, _cols[i % 4], rnd() * 3);
        } else {
          hBalloon(cx, cy - 2, 3.4, _cols[(i ~/ 2) % 4]);
        }
      default:
        throw StateError('${layer.key} has no side motif');
    }
  }

  void _holiday(
    List<DecorElement> top,
    List<DecorElement> left,
    List<DecorElement> right,
    List<DecorElement> bottom,
  ) {
    into(top, () {
      hTop();
      if (_hasEdge) {
        for (final (i, x) in const [
          12.0,
          50.0,
          90.0,
          130.0,
          170.0,
          208.0,
          246.0,
          286.0,
          324.0,
        ].indexed) {
          // Порядок аргументов как в JS: сдвиг x, y, размер.
          final ex = sx(x) + (rnd() - 0.5) * 8;
          final ey = 3 + rnd() * 5;
          final es = 7 + rnd() * 2.5;
          hEdge(ex, ey, es, i);
        }
      }
      shifted(hGap);
    });
    final sideH = h - decorTop - decorSide;
    var i = 0;
    for (double y = 10; y < sideH - 4; y += 22, i++) {
      final lx = 6 + (rnd() - 0.5) * 1.2;
      into(left, () => hSide(lx, y, i));
      final rx = 6 + (rnd() - 0.5) * 1.2;
      into(right, () => hSide(rx, y, i + 1));
    }
    i = 0;
    into(bottom, () {
      for (double x = 34; x <= w - 34; x += 24, i++) {
        hSide(x, 6, i);
      }
    });
  }

  static DecorElement _translate(DecorElement e, double dx) {
    if (e.isCircle) {
      return DecorElement.circle(
        e.cx + dx,
        e.cy,
        e.r,
        fill: e.fill,
        stroke: e.stroke,
        strokeWidth: e.strokeWidth,
        explicitNoFill: e.explicitNoFill,
      );
    }
    final cmds = [
      for (final c in e.commands!)
        if (c.op == 'A')
          PathCommand('A', [...c.args.sublist(0, 5), c.args[5] + dx, c.args[6]])
        else
          PathCommand(c.op, [
            for (final (i, v) in c.args.indexed) i.isEven ? v + dx : v,
          ]),
    ];
    return DecorElement.path(
      cmds,
      fill: e.fill,
      stroke: e.stroke,
      strokeWidth: e.strokeWidth,
      roundCap: e.roundCap,
      roundJoin: e.roundJoin,
      explicitNoFill: e.explicitNoFill,
    );
  }
}

/// Выбор узора для настроения и темы: Хеллоуин в светлой теме — милый,
/// в тёмной — жуткий.
DecorLayer decorLayerOf(String moodKey, {required bool dark}) {
  if (moodKey == 'halloween') {
    return dark ? DecorLayer.halloweenSpooky : DecorLayer.halloweenCute;
  }
  return DecorLayer.values.firstWhere((l) => l.key == moodKey);
}
