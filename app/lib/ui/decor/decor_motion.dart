import 'dart:math' as math;

import 'decor_generator.dart';

final class DecorPose {
  const DecorPose({
    this.dx = 0,
    this.dy = 0,
    this.angle = 0,
    this.scale = 1,
    this.scaleY = 1,
    this.opacity = 1,
  });

  static const DecorPose rest = DecorPose();

  final double dx;
  final double dy;
  final double angle;
  final double scale;
  final double scaleY;
  final double opacity;

  bool get moves =>
      dx != 0 || dy != 0 || angle != 0 || scale != 1 || scaleY != 1;

  bool get isRest => !moves && opacity == 1;

  @override
  String toString() =>
      'DecorPose(dx=${dx.toStringAsFixed(2)} dy=${dy.toStringAsFixed(2)} '
      'angle=${(angle * 180 / math.pi).toStringAsFixed(2)}° '
      'scale=${scale.toStringAsFixed(3)} scaleY=${scaleY.toStringAsFixed(3)} '
      'opacity=${opacity.toStringAsFixed(3)})';
}

const Map<DecorLayer, Duration> decorCycles = {
  DecorLayer.newyear: Duration(seconds: 6),
  DecorLayer.valentine: Duration(milliseconds: 1200),
  DecorLayer.defender: Duration(seconds: 2),
  DecorLayer.maslenitsa: Duration(seconds: 20),
  DecorLayer.women: Duration(seconds: 3),
  DecorLayer.labour: Duration(seconds: 4),
  DecorLayer.victory: Duration(seconds: 3),
  DecorLayer.children: Duration(seconds: 4),
  DecorLayer.knowledge: Duration(seconds: 6),
  DecorLayer.halloweenCute: Duration(seconds: 3),
  DecorLayer.halloweenSpooky: Duration(seconds: 10),
  DecorLayer.birthday: Duration(seconds: 6),
};

Duration? decorCycleOf(DecorLayer layer) => decorCycles[layer];

const Map<DecorMotion, double> decorMotionPeriods = {
  DecorMotion.blink: 2,
  DecorMotion.swing: 3,
  DecorMotion.beat: 1.2,
  DecorMotion.twinkle: 2,
  DecorMotion.flutter: 2,
  DecorMotion.spin: 20,
  DecorMotion.sway: 3,
  DecorMotion.knock: 4,
  DecorMotion.flash: 3,
  DecorMotion.rise: 4,
  DecorMotion.string: 2,
  DecorMotion.fall: 6,
  DecorMotion.confetti: 6,
  DecorMotion.bob: 3,
  DecorMotion.descend: 5,
  DecorMotion.thread: 5,
  DecorMotion.flapLeft: 0.4,
  DecorMotion.flapRight: 0.4,
};

const double decorRampSeconds = 0.6;

const double decorSpiderDrop = 10;

const double _deg = math.pi / 180;

double decorEnvelope(double sinceStart) =>
    sinceStart >= decorRampSeconds ? 1 : _smooth(sinceStart / decorRampSeconds);

DecorPose decorPose(
  DecorMotionSpan span, {
  required double t,
  double sinceStart = double.infinity,
}) {
  final e = decorEnvelope(sinceStart);
  final o = _scatter(span.order);
  switch (span.motion) {
    case DecorMotion.blink:
      final u = _frac(t / 2 - (span.order % 4) / 4);
      final dim = u < 0.25 ? _sin2(math.pi * u / 0.25) : 0.0;
      return DecorPose(opacity: 1 - 0.7 * dim * e);
    case DecorMotion.swing:
      return DecorPose(angle: 4 * _deg * _wave(t, 3, o) * e);
    case DecorMotion.beat:
      return DecorPose(scale: 1 + 0.12 * _pulse(t, 1.2, o) * e);
    case DecorMotion.twinkle:
      return DecorPose(opacity: 1 - 0.5 * _pulse(t, 2, o) * e);
    case DecorMotion.flutter:
      return DecorPose(angle: 3 * _deg * _wave(t, 2, o) * e);
    case DecorMotion.spin:
      return DecorPose(angle: 2 * math.pi * _frac(t / 20));
    case DecorMotion.hop:
      return DecorPose(dy: _hop(sinceStart));
    case DecorMotion.sway:
      return DecorPose(angle: 5 * _deg * _wave(t, 3, o) * e);
    case DecorMotion.knock:
      return DecorPose(angle: _knock(_frac(t / 4 - o) * 4) * e);
    case DecorMotion.flash:
      return _flash(_frac(t / 3 - (span.order % 6) / 6) * 3, e);
    case DecorMotion.rise:
      return DecorPose(dy: -span.amount * _pulse(t, 4, o) * e);
    case DecorMotion.string:
      return DecorPose(angle: 8 * _deg * _wave(t, 2, o) * e);
    case DecorMotion.ring:
      return DecorPose(angle: _ring(sinceStart - 0.1));
    case DecorMotion.fall:
      return _fall(span, _frac(t / 6 + o), e, spin: false);
    case DecorMotion.confetti:
      return _fall(span, _frac(t / 6 + o), e, spin: true);
    case DecorMotion.bob:
      return DecorPose(dy: -span.amount * _pulse(t, 3, 0) * e);
    case DecorMotion.descend:
      return DecorPose(dy: span.amount * _pulse(t, 5, 0) * e);
    case DecorMotion.thread:
      final drop = decorSpiderDrop * _pulse(t, 5, 0) * e;
      return DecorPose(scaleY: span.amount <= 0 ? 1 : 1 + drop / span.amount);
    case DecorMotion.flapRight:
      return DecorPose(angle: 25 * _deg * _wave(t, 0.4, o) * e);
    case DecorMotion.flapLeft:
      return DecorPose(angle: -25 * _deg * _wave(t, 0.4, o) * e);
  }
}

double _frac(double x) => x - x.floorToDouble();

double _scatter(int order) => _frac(order * 0.6180339887498949);

double _sin2(double x) {
  final s = math.sin(x);
  return s * s;
}

double _wave(double t, double period, double offset) =>
    math.sin(2 * math.pi * (t / period + offset));

double _pulse(double t, double period, double offset) =>
    _sin2(math.pi * (t / period + offset));

double _smooth(double x) {
  final c = x.clamp(0.0, 1.0);
  return c * c * (3 - 2 * c);
}

double _hop(double s) {
  if (s >= 0.2 && s < 0.7) return -6 * math.sin(math.pi * (s - 0.2) / 0.5);
  if (s >= 0.7 && s < 1.0) return -2 * math.sin(math.pi * (s - 0.7) / 0.3);
  return 0;
}

double _knock(double seconds) {
  if (seconds >= 0.6) return 0;
  final w = seconds / 0.6;
  final lift = w < 0.6
      ? 1 - math.pow(1 - w / 0.6, 2).toDouble()
      : 1 - math.pow((w - 0.6) / 0.4, 2).toDouble();
  return -20 * _deg * lift;
}

DecorPose _flash(double seconds, double e) {
  var scale = 1.0;
  var opacity = 0.0;
  if (seconds < 1.5) {
    final w = seconds / 1.5;
    scale = 0.3 + 0.7 * (1 - math.pow(1 - w, 3).toDouble());
    opacity = w < 0.25 ? _smooth(w / 0.25) : 1 - _smooth((w - 0.25) / 0.75);
  }
  return DecorPose(scale: 1 + (scale - 1) * e, opacity: 1 + (opacity - 1) * e);
}

double _ring(double s) {
  if (s < 0 || s >= 1) return 0;
  return 15.67 * _deg * math.sin(2 * math.pi * s) * (1 - s);
}

DecorPose _fall(
  DecorMotionSpan span,
  double u,
  double e, {
  required bool spin,
}) {
  final fade = math.min(_smooth(u / 0.15), 1 - _smooth((u - 0.7) / 0.3));
  final turn = spin
      ? math.pi * u * (span.order.isEven ? 1 : -1)
      : 0.5 * math.sin(2 * math.pi * u);
  return DecorPose(
    dx: (spin ? 1.5 : 1.2) * math.sin(2 * math.pi * u) * e,
    dy: span.amount * u * e,
    angle: turn * e,
    opacity: 1 + (fade - 1) * e,
  );
}
