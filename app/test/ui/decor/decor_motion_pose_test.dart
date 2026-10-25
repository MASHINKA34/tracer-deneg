import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/ui/decor/decor_generator.dart';
import 'package:milionchik/ui/decor/decor_motion.dart';

const double _deg = 180 / math.pi;

DecorMotionSpan _span(DecorMotion m, {int order = 0, double amount = 0}) =>
    DecorMotionSpan(
      m,
      DecorRegion.top,
      0,
      1,
      0,
      0,
      order: order,
      amount: amount,
    );

List<DecorPose> _samples(
  DecorMotionSpan span,
  double seconds, {
  int steps = 2400,
  bool opening = false,
}) => [
  for (var i = 0; i <= steps; i++)
    decorPose(
      span,
      t: seconds * i / steps,
      sinceStart: opening ? seconds * i / steps : double.infinity,
    ),
];

double _max(Iterable<double> v) => v.reduce(math.max);
double _min(Iterable<double> v) => v.reduce(math.min);

void main() {
  final holidays = DecorLayer.values.where((l) => !l.isSeason).toList();

  test('у каждого праздника есть цикл анимации, у сезонов - нет', () {
    for (final layer in DecorLayer.values) {
      expect(decorCycleOf(layer) != null, !layer.isSeason, reason: layer.key);
    }
  });

  test('старт анимации - с покоя: в первый кадр каждый элемент стоит, как '
      'на статичной картинке; со сдвигом фазы - все, кроме солнышек, у '
      'которых угол и есть фаза', () {
    for (final layer in holidays) {
      final regions = generateDecor(layer);
      final cycle = decorCycleOf(layer)!.inMilliseconds / 1000;
      for (final s in regions.motions) {
        final first = decorPose(s, t: 0, sinceStart: 0);
        expect(first.isRest, isTrue, reason: '${layer.key} $s: $first');
        if (s.motion == DecorMotion.spin) continue;
        for (final t in [cycle * 0.37, cycle * 0.81]) {
          final pose = decorPose(s, t: t, sinceStart: 0);
          expect(pose.isRest, isTrue, reason: '${layer.key} $s t=$t: $pose');
        }
      }
    }
  });

  test('периоды движений укладываются в цикл слоя: кадр в конце цикла '
      'совпадает с кадром в начале (без рывка на стыке)', () {
    for (final layer in holidays) {
      final cycle = decorCycleOf(layer)!.inMilliseconds / 1000;
      for (final s in generateDecor(layer).motions) {
        final period = decorMotionPeriods[s.motion];
        if (period != null) {
          final turns = cycle / period;
          expect(
            (turns - turns.round()).abs(),
            lessThan(1e-9),
            reason: '${layer.key} ${s.motion.name}: $period s в $cycle s',
          );
        }
        for (final t in [0.0, 0.13, 0.91]) {
          final a = decorPose(s, t: t);
          final b = decorPose(s, t: t + cycle);
          expect(b.dx, closeTo(a.dx, 1e-6), reason: '${layer.key} $s');
          expect(b.dy, closeTo(a.dy, 1e-6), reason: '${layer.key} $s');
          expect(
            math.sin(b.angle - a.angle).abs(),
            lessThan(1e-6),
            reason: '${layer.key} $s',
          );
          expect(b.scale, closeTo(a.scale, 1e-6), reason: '${layer.key} $s');
          expect(b.opacity, closeTo(a.opacity, 1e-6), reason: '$s');
        }
      }
    }
  });

  test('Новый год: огоньки мигают по очереди с циклом 2 с, шары '
      'покачиваются ±4° за 3 с', () {
    final lights = [
      for (var i = 0; i < 4; i++) _span(DecorMotion.blink, order: i),
    ];
    final darkest = [
      for (final s in lights)
        List.generate(200, (i) => i * 0.01).reduce(
          (a, b) =>
              decorPose(s, t: b).opacity < decorPose(s, t: a).opacity ? b : a,
        ),
    ];
    expect(darkest.toSet(), hasLength(4));
    for (final s in lights) {
      final pose = _samples(s, 2);
      expect(_min(pose.map((p) => p.opacity)), closeTo(0.3, 0.01));
      expect(_max(pose.map((p) => p.opacity)), 1);
      expect(
        decorPose(s, t: 0.7).opacity,
        closeTo(decorPose(s, t: 2.7).opacity, 1e-9),
      );
    }

    final ball = _span(DecorMotion.swing, order: 3);
    final angles = _samples(ball, 3).map((p) => p.angle * _deg);
    expect(_max(angles), closeTo(4, 0.01));
    expect(_min(angles), closeTo(-4, 0.01));
    expect(
      decorPose(ball, t: 0.4).angle,
      closeTo(decorPose(ball, t: 3.4).angle, 1e-9),
    );
  });

  test('14 февраля: сердечко бьётся 1 → 1,12 → 1 за 1,2 с, сердечки - '
      'вразнобой', () {
    final hearts = [
      for (var i = 0; i < 3; i++) _span(DecorMotion.beat, order: i),
    ];
    for (final s in hearts) {
      final scales = _samples(s, 1.2).map((p) => p.scale);
      expect(_max(scales), closeTo(1.12, 1e-4));
      expect(_min(scales), closeTo(1, 1e-4));
    }
    final now = {for (final s in hearts) decorPose(s, t: 0.5).scale};
    expect(now, hasLength(3));
  });

  test('23 Февраля: звёзды мерцают 100 → 50 → 100 % за 2 с, ленточки '
      'слегка развеваются', () {
    final star = _span(DecorMotion.twinkle, order: 5);
    final opacity = _samples(star, 2).map((p) => p.opacity);
    expect(_min(opacity), closeTo(0.5, 1e-4));
    expect(_max(opacity), closeTo(1, 1e-4));
    final ribbon = _samples(
      _span(DecorMotion.flutter),
      2,
    ).map((p) => p.angle * _deg);
    expect(_max(ribbon), closeTo(3, 0.01));
  });

  test('Масленица: солнышко делает оборот за 20 с; стопка блинов '
      'подпрыгивает только при открытии', () {
    final sun = _span(DecorMotion.spin);
    expect(decorPose(sun, t: 5).angle, closeTo(math.pi / 2, 1e-9));
    expect(decorPose(sun, t: 10).angle, closeTo(math.pi, 1e-9));
    final hop = _span(DecorMotion.hop);
    final opening = _samples(hop, 2, opening: true).map((p) => p.dy);
    expect(_min(opening), closeTo(-6, 0.01));
    expect(decorPose(hop, t: 0.45, sinceStart: 1.2).dy, 0);
    expect(decorPose(hop, t: 0.45).dy, 0);
  });

  test('8 Марта: тюльпаны ±5° за 3 с; Неделя труда: молоточек 0 → −20° → 0 '
      'за 0,6 с раз в 4 с', () {
    final tulip = _samples(
      _span(DecorMotion.sway),
      3,
    ).map((p) => p.angle * _deg);
    expect(_max(tulip), closeTo(5, 0.01));
    expect(_min(tulip), closeTo(-5, 0.01));

    final hammer = _span(DecorMotion.knock, order: 2);
    final poses = _samples(hammer, 4, steps: 4000);
    final angles = poses.map((p) => p.angle * _deg).toList();
    expect(_min(angles), closeTo(-20, 0.05));
    expect(_max(angles), 0);
    final moving = angles.where((a) => a != 0).length;
    expect(moving / angles.length, closeTo(0.6 / 4, 0.01));
  });

  test('9 мая: салют вырастает из центра и гаснет за 1,5 с, по очереди - '
      'в любой момент горят не все', () {
    final salutes = [
      for (var i = 0; i < 6; i++) _span(DecorMotion.flash, order: i),
    ];
    for (final s in salutes) {
      final poses = _samples(s, 3);
      expect(_min(poses.map((p) => p.scale)), closeTo(0.3, 0.01));
      expect(_max(poses.map((p) => p.opacity)), closeTo(1, 0.01));
      expect(_min(poses.map((p) => p.opacity)), 0);
      final lit = poses.where((p) => p.opacity > 0).length / poses.length;
      expect(lit, closeTo(0.5, 0.01));
    }
    for (final t in [0.2, 1.3, 2.9]) {
      final lit = salutes.where((s) => decorPose(s, t: t).opacity > 0).length;
      expect(lit, inInclusiveRange(2, 4), reason: 't=$t');
    }
  });

  test('1 июня: шарики поднимаются на 6 px (по бокам на 3) за 4 с, '
      'ниточки покачиваются', () {
    final top = _samples(
      _span(DecorMotion.rise, amount: 6),
      4,
    ).map((p) => p.dy);
    expect(_min(top), closeTo(-6, 1e-3));
    expect(_max(top), closeTo(0, 1e-3));
    final side = _samples(
      _span(DecorMotion.rise, amount: 3),
      4,
    ).map((p) => p.dy);
    expect(_min(side), closeTo(-3, 1e-3));
    final string = _samples(_span(DecorMotion.string), 2).map((p) => p.angle);
    expect(_max(string) * _deg, closeTo(8, 0.01));
  });

  test('1 сентября: колокольчик качается до 12° в первую секунду после '
      'открытия и затихает; листочки опадают и тают', () {
    final bell = _span(DecorMotion.ring);
    final first = _samples(bell, 1.1, opening: true).map((p) => p.angle * _deg);
    expect(_max(first), closeTo(12, 0.1));
    expect(_min(first), lessThan(-3));
    expect(decorPose(bell, t: 0.3, sinceStart: 1.2).angle, 0);
    expect(decorPose(bell, t: 0.3).angle, 0);

    final leaf = _span(DecorMotion.fall, amount: 22);
    final poses = _samples(leaf, 6);
    expect(_max(poses.map((p) => p.dy)), closeTo(22, 0.1));
    expect(_min(poses.map((p) => p.opacity)), lessThan(0.01));
  });

  test('Хеллоуин: призрачок на 4 px за 3 с; паук спускается на 10 px за 5 с '
      'и нитка удлиняется на столько же; крылья машут за 0,4 с', () {
    final ghost = _samples(
      _span(DecorMotion.bob, amount: 4),
      3,
    ).map((p) => p.dy);
    expect(_min(ghost), closeTo(-4, 1e-3));

    final body = _span(DecorMotion.descend, amount: 10);
    final thread = _span(DecorMotion.thread, amount: 39.7);
    for (final t in [0.4, 1.3, 2.5, 4.1]) {
      final drop = decorPose(body, t: t).dy;
      final stretch = decorPose(thread, t: t).scaleY;
      expect(39.7 * stretch, closeTo(39.7 + drop, 1e-9));
    }
    expect(decorPose(body, t: 2.5).dy, closeTo(10, 1e-9));

    final right = _span(DecorMotion.flapRight, order: 1);
    final left = _span(DecorMotion.flapLeft, order: 1);
    expect(
      decorPose(right, t: 0.13).angle,
      closeTo(-decorPose(left, t: 0.13).angle, 1e-12),
    );
    expect(
      decorPose(right, t: 0.13).angle,
      closeTo(decorPose(right, t: 0.53).angle, 1e-9),
    );
    final flap = _samples(right, 0.4).map((p) => p.angle * _deg);
    expect(_max(flap), closeTo(25, 0.05));
  });

  test('День рождения: конфетти падает и крутится 6 с по кругу, шарики '
      'покачиваются', () {
    final piece = _span(DecorMotion.confetti, order: 1, amount: 22);
    final poses = _samples(piece, 6);
    expect(_max(poses.map((p) => p.dy)), closeTo(22, 0.1));
    expect(_min(poses.map((p) => p.angle)), lessThan(-3));
    expect(decorPose(piece, t: 1).dy, closeTo(decorPose(piece, t: 7).dy, 1e-9));
    final balloon = _samples(_span(DecorMotion.swing), 3).map((p) => p.angle);
    expect(_max(balloon) * _deg, closeTo(4, 0.01));
  });

  test('плавный старт: за первые 0,6 с размах растёт от нуля до полного', () {
    final ball = _span(DecorMotion.swing, order: 0);
    double amplitude(double since) =>
        decorPose(ball, t: 0.75, sinceStart: since).angle.abs();
    expect(amplitude(0), 0);
    expect(amplitude(0.3), allOf(greaterThan(0), lessThan(amplitude(0.6))));
    expect(amplitude(0.6), closeTo(amplitude(5), 1e-12));
  });
}
