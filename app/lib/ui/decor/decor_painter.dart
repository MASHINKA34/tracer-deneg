import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/animation.dart';
import 'package:flutter/rendering.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart' show Mood, describeError;

import '../tokens/tokens.g.dart';
import 'decor_generator.dart';
import 'decor_motion.dart';
import 'decor_shapes.dart';

final _log = Logger('decor');

/// Узор по краям карточки месяца — первый слой карточки, под содержимым
/// (00-spec §6.3). Цвета — `decor-1…4` настроения [mood] в теме
/// [brightness]; Хеллоуин в тёмной теме — жуткий слой.
///
/// Готовая картинка кэшируется по (настроение, тема, размер): узор
/// генерируется один раз, дальше только рисуется.
/// [phase] (0…1) — сдвиг фазы анимации декора; без [animation] узор
/// статичный и от фазы не зависит.
class DecorPainter extends CustomPainter {
  DecorPainter({
    required this.mood,
    required this.brightness,
    this.phase = 0,
    this.cornerRadius = 28,
    this.animation,
    this.opening = false,
    this.keepClear,
  }) : super(repaint: animation);

  final Mood mood;
  final ui.Brightness brightness;
  final double phase;
  final Animation<double>? animation;
  final bool opening;
  final DecorKeepClear? keepClear;

  /// Скругление карточки — узор обрезается по нему.
  final double cornerRadius;

  /// Сколько картинок держим (15 настроений × 2 темы × пара размеров).
  static const int cacheCapacity = 48;
  static final LinkedHashMap<String, ui.Picture> _cache = LinkedHashMap();

  /// Сколько картинок в кэше (для тестов и каталога).
  static int get cachedPictures => _cache.length;

  static const int animationCacheCapacity = 12;
  static final LinkedHashMap<String, _DecorFrames> _frames = LinkedHashMap();
  static final Set<String> _failedFrames = {};

  static int get cachedAnimations => _frames.length;

  static const int topDecisionCapacity = 64;
  static final LinkedHashMap<String, bool> _topHidden = LinkedHashMap();

  /// Очистить кэш (тесты).
  static void clearCache() {
    for (final picture in _cache.values) {
      picture.dispose();
    }
    _cache.clear();
    for (final frames in _frames.values) {
      frames.dispose();
    }
    _frames.clear();
    _failedFrames.clear();
    _topHidden.clear();
  }

  DecorLayer get layer =>
      decorLayerOf(mood.name, dark: brightness == ui.Brightness.dark);

  String _key(Size size) =>
      '${mood.name}|${brightness.name}|'
      '${size.width.toStringAsFixed(1)}x${size.height.toStringAsFixed(1)}'
      '${_hidesTop(size) ? '|no-top' : ''}';

  bool _hidesTop(Size size) {
    final clear = keepClear;
    if (clear == null) return false;
    final area = clear.area;
    final design = clear.designArea;
    final key =
        '${layer.key}|${size.width.toStringAsFixed(1)}x'
        '${size.height.toStringAsFixed(1)}|${_rectText(area)}|'
        '${_rectText(design)}';
    final known = _topHidden.remove(key);
    if (known != null) {
      _topHidden[key] = known;
      return known;
    }
    final regions = generateDecor(
      layer,
      width: size.width,
      height: size.height,
    );
    final hits = decorTopOverlaps(regions, area, beyond: design);
    final hidden = hits > 0;
    if (_topHidden.length >= topDecisionCapacity) {
      _topHidden.remove(_topHidden.keys.first);
    }
    _topHidden[key] = hidden;
    _log.fine(
      hidden
          ? 'decor top strip hidden layer=${layer.key} '
                'size=${size.width.toStringAsFixed(1)}x'
                '${size.height.toStringAsFixed(1)}: $hits of '
                '${regions.top.length} top shapes overlap the month title '
                'area ${_rectText(area)} beyond its font 1.0 area '
                '${_rectText(design)} → sides and bottom only'
          : 'decor top strip kept layer=${layer.key} '
                'size=${size.width.toStringAsFixed(1)}x'
                '${size.height.toStringAsFixed(1)}: none of '
                '${regions.top.length} top shapes overlap the month title '
                'area ${_rectText(area)} beyond its font 1.0 area '
                '${_rectText(design)}',
    );
    return hidden;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final animation = this.animation;
    final cycle = decorCycleOf(layer);
    if (animation != null && cycle != null) {
      final frames = _framesFor(size);
      if (frames != null) {
        _paintFrame(canvas, size, frames, animation.value, cycle);
        return;
      }
    }
    final key = _key(size);
    var picture = _cache.remove(key);
    if (picture == null) {
      picture = _record(size);
      if (_cache.length >= cacheCapacity) {
        final oldest = _cache.keys.first;
        _cache.remove(oldest)!.dispose();
        _log.fine('decor cache full ($cacheCapacity), evicted $oldest');
      }
    }
    _cache[key] = picture; // в конец — недавно использованная
    canvas.drawPicture(picture);
  }

  ui.Picture _record(Size size) {
    final sw = Stopwatch()..start();
    final regions = generateDecor(
      layer,
      width: size.width,
      height: size.height,
    );
    final palette = (brightness == ui.Brightness.light
        ? moodLight
        : moodDark)[mood]!;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..clipRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(cornerRadius),
        ),
      );
    paintDecorRegions(canvas, regions, palette, top: !_hidesTop(size));
    final picture = recorder.endRecording();
    _log.fine(
      'decor picture cached layer=${layer.key} theme=${brightness.name} '
      'size=${size.width.toStringAsFixed(1)}x${size.height.toStringAsFixed(1)} '
      'shapes=${regions.elementCount} in ${sw.elapsedMilliseconds}ms '
      '(cache miss)',
    );
    return picture;
  }

  _DecorFrames? _framesFor(Size size) {
    final key = _key(size);
    if (_failedFrames.contains(key)) return null;
    var frames = _frames.remove(key);
    if (frames == null) {
      try {
        frames = _buildFrames(size);
      } catch (e, st) {
        _failedFrames.add(key);
        _log.severe(
          'decor animation frames failed layer=${layer.key} '
          'theme=${brightness.name} '
          'size=${size.width.toStringAsFixed(1)}x'
          '${size.height.toStringAsFixed(1)} → static picture: '
          '${describeError(e)}',
          e,
          st,
        );
        return null;
      }
      if (_frames.length >= animationCacheCapacity) {
        final oldest = _frames.keys.first;
        _frames.remove(oldest)!.dispose();
        _log.fine(
          'decor animation cache full ($animationCacheCapacity), '
          'evicted $oldest',
        );
      }
    }
    _frames[key] = frames;
    return frames;
  }

  _DecorFrames _buildFrames(Size size) {
    final sw = Stopwatch()..start();
    final regions = generateDecor(
      layer,
      width: size.width,
      height: size.height,
    );
    final palette = (brightness == ui.Brightness.light
        ? moodLight
        : moodDark)[mood]!;
    final units = <_DecorUnit>[];
    var still = 0;
    var moving = 0;
    final hideTop = _hidesTop(size);
    for (final region in DecorRegion.values) {
      if (hideTop && region == DecorRegion.top) continue;
      final offset = switch (region) {
        DecorRegion.top => Offset.zero,
        DecorRegion.left => const Offset(0, decorTop),
        DecorRegion.right => Offset(regions.width - decorSide, decorTop),
        DecorRegion.bottom => Offset(0, regions.height - decorSide),
      };
      final elements = regions.of(region);
      final spans =
          [
            for (final s in regions.motions)
              if (s.region == region) s,
          ]..sort(
            (a, b) => a.start != b.start
                ? a.start.compareTo(b.start)
                : b.end.compareTo(a.end),
          );
      var current = const <DecorMotionSpan>[];
      final run = <DecorElement>[];
      void flush() {
        if (run.isEmpty) return;
        if (current.isEmpty) {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder)..translate(offset.dx, offset.dy);
          for (final e in run) {
            _paintElement(canvas, e, palette);
          }
          units.add(_StillUnit(recorder.endRecording()));
          still++;
        } else {
          units.add(
            _MovingUnit(offset, current, [
              for (final e in run) _Shape(e, palette),
            ]),
          );
          moving++;
        }
        run.clear();
      }

      for (var i = 0; i < elements.length; i++) {
        final active = [
          for (final s in spans)
            if (s.covers(region, i)) s,
        ];
        if (!_sameSpans(active, current)) {
          flush();
          current = active;
        }
        run.add(elements[i]);
      }
      flush();
    }
    _log.fine(
      'decor animation frames cached layer=${layer.key} '
      'theme=${brightness.name} '
      'size=${size.width.toStringAsFixed(1)}x${size.height.toStringAsFixed(1)} '
      'motions=${regions.motions.length} moving=$moving still=$still '
      'in ${sw.elapsedMilliseconds}ms (cache miss)',
    );
    return _DecorFrames(units);
  }

  void _paintFrame(
    Canvas canvas,
    Size size,
    _DecorFrames frames,
    double value,
    Duration cycle,
  ) {
    final seconds = cycle.inMicroseconds / Duration.microsecondsPerSecond;
    final t = ((phase + value) % 1.0) * seconds;
    final since = opening ? value * seconds : double.infinity;
    canvas
      ..save()
      ..clipRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(cornerRadius),
        ),
      );
    for (final unit in frames.units) {
      unit.paint(canvas, t, since);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(DecorPainter oldDelegate) =>
      oldDelegate.mood != mood ||
      oldDelegate.brightness != brightness ||
      oldDelegate.phase != phase ||
      oldDelegate.cornerRadius != cornerRadius ||
      oldDelegate.animation != animation ||
      oldDelegate.opening != opening ||
      oldDelegate.keepClear != keepClear;
}

String _rectText(Rect r) =>
    '(${r.left.toStringAsFixed(1)},${r.top.toStringAsFixed(1)})-'
    '(${r.right.toStringAsFixed(1)},${r.bottom.toStringAsFixed(1)})';

final class DecorKeepClear {
  const DecorKeepClear({required this.area, required this.designArea});

  final Rect area;
  final Rect designArea;

  @override
  bool operator ==(Object other) =>
      other is DecorKeepClear &&
      other.area == area &&
      other.designArea == designArea;

  @override
  int get hashCode => Object.hash(area, designArea);

  @override
  String toString() =>
      'DecorKeepClear(${_rectText(area)} font 1.0 ${_rectText(designArea)})';
}

int decorTopOverlaps(DecorRegions regions, Rect area, {Rect? beyond}) {
  var hits = 0;
  for (final e in regions.top) {
    final stroke = e.stroke == null ? 0.0 : (e.strokeWidth ?? 1) / 2;
    final bounds = e.isCircle
        ? Rect.fromCircle(center: Offset(e.cx, e.cy), radius: e.r + stroke)
        : e.toPath().getBounds().inflate(stroke);
    if (bounds.overlaps(area) && !(beyond?.overlaps(bounds) ?? false)) {
      hits++;
    }
  }
  return hits;
}

bool _sameSpans(List<DecorMotionSpan> a, List<DecorMotionSpan> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!identical(a[i], b[i])) return false;
  }
  return true;
}

final class _DecorFrames {
  _DecorFrames(this.units);

  final List<_DecorUnit> units;

  void dispose() {
    for (final unit in units) {
      unit.dispose();
    }
  }
}

sealed class _DecorUnit {
  void paint(Canvas canvas, double t, double since);

  void dispose() {}
}

final class _StillUnit extends _DecorUnit {
  _StillUnit(this.picture);

  final ui.Picture picture;

  @override
  void paint(Canvas canvas, double t, double since) =>
      canvas.drawPicture(picture);

  @override
  void dispose() => picture.dispose();
}

final class _MovingUnit extends _DecorUnit {
  _MovingUnit(this.offset, this.spans, this.shapes);

  final Offset offset;
  final List<DecorMotionSpan> spans;
  final List<_Shape> shapes;

  @override
  void paint(Canvas canvas, double t, double since) {
    var opacity = 1.0;
    canvas
      ..save()
      ..translate(offset.dx, offset.dy);
    for (final s in spans) {
      final pose = decorPose(s, t: t, sinceStart: since);
      opacity *= pose.opacity;
      if (!pose.moves) continue;
      canvas.translate(s.pivotX + pose.dx, s.pivotY + pose.dy);
      if (pose.angle != 0) canvas.rotate(pose.angle);
      if (pose.scale != 1 || pose.scaleY != 1) {
        canvas.scale(pose.scale, pose.scale * pose.scaleY);
      }
      canvas.translate(-s.pivotX, -s.pivotY);
    }
    if (opacity > 0.004) {
      for (final shape in shapes) {
        shape.paint(canvas, opacity);
      }
    }
    canvas.restore();
  }
}

final class _Shape {
  _Shape(this.element, MoodTokens palette)
    : path = element.isCircle ? null : element.toPath(),
      fillColor = element.fill == null ? null : _ink(palette, element.fill!),
      strokeColor = element.stroke == null
          ? null
          : _ink(palette, element.stroke!),
      fillPaint = element.fill == null ? null : Paint(),
      strokePaint = element.stroke == null
          ? null
          : (Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = element.strokeWidth ?? 1
              ..strokeCap = element.roundCap ? StrokeCap.round : StrokeCap.butt
              ..strokeJoin = element.roundJoin
                  ? StrokeJoin.round
                  : StrokeJoin.miter);

  final DecorElement element;
  final Path? path;
  final Color? fillColor;
  final Color? strokeColor;
  final Paint? fillPaint;
  final Paint? strokePaint;

  void paint(Canvas canvas, double opacity) {
    final fill = fillPaint;
    if (fill != null) {
      fill.color = _faded(fillColor!, opacity);
      _draw(canvas, fill);
    }
    final stroke = strokePaint;
    if (stroke != null) {
      stroke.color = _faded(strokeColor!, opacity);
      _draw(canvas, stroke);
    }
  }

  void _draw(Canvas canvas, Paint paint) {
    final path = this.path;
    if (path == null) {
      canvas.drawCircle(Offset(element.cx, element.cy), element.r, paint);
    } else {
      canvas.drawPath(path, paint);
    }
  }

  static Color _faded(Color color, double opacity) =>
      opacity >= 1 ? color : color.withValues(alpha: color.a * opacity);
}

Color _ink(MoodTokens palette, DecorInk i) => switch (i) {
  DecorInk.c1 => palette.decor1,
  DecorInk.c2 => palette.decor2,
  DecorInk.c3 => palette.decor3,
  DecorInk.c4 => palette.decor4,
};

void _paintElement(Canvas canvas, DecorElement e, MoodTokens palette) {
  final fill = e.fill;
  final stroke = e.stroke;
  if (e.isCircle) {
    final center = Offset(e.cx, e.cy);
    if (fill != null) {
      canvas.drawCircle(center, e.r, Paint()..color = _ink(palette, fill));
    }
    if (stroke != null) {
      canvas.drawCircle(
        center,
        e.r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = e.strokeWidth ?? 1
          ..color = _ink(palette, stroke),
      );
    }
    return;
  }
  final path = e.toPath();
  if (fill != null) canvas.drawPath(path, Paint()..color = _ink(palette, fill));
  if (stroke != null) {
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = e.strokeWidth ?? 1
        ..strokeCap = e.roundCap ? StrokeCap.round : StrokeCap.butt
        ..strokeJoin = e.roundJoin ? StrokeJoin.round : StrokeJoin.miter
        ..color = _ink(palette, stroke),
    );
  }
}

/// Рисует области узора, как их собирает SVG генератора: верх — от угла,
/// левая полоса — от (0, 60), правая — от (W − 12, 60), низ — от (0, H − 12).
void paintDecorRegions(
  Canvas canvas,
  DecorRegions regions,
  MoodTokens palette, {
  bool top = true,
}) {
  Color ink(DecorInk i) => switch (i) {
    DecorInk.c1 => palette.decor1,
    DecorInk.c2 => palette.decor2,
    DecorInk.c3 => palette.decor3,
    DecorInk.c4 => palette.decor4,
  };

  void draw(List<DecorElement> elements, Offset offset) {
    canvas
      ..save()
      ..translate(offset.dx, offset.dy);
    for (final e in elements) {
      final fill = e.fill;
      final stroke = e.stroke;
      if (e.isCircle) {
        final center = Offset(e.cx, e.cy);
        if (fill != null) {
          canvas.drawCircle(center, e.r, Paint()..color = ink(fill));
        }
        if (stroke != null) {
          canvas.drawCircle(
            center,
            e.r,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = e.strokeWidth ?? 1
              ..color = ink(stroke),
          );
        }
        continue;
      }
      final path = e.toPath();
      if (fill != null) canvas.drawPath(path, Paint()..color = ink(fill));
      if (stroke != null) {
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = e.strokeWidth ?? 1
            ..strokeCap = e.roundCap ? StrokeCap.round : StrokeCap.butt
            ..strokeJoin = e.roundJoin ? StrokeJoin.round : StrokeJoin.miter
            ..color = ink(stroke),
        );
      }
    }
    canvas.restore();
  }

  if (top) draw(regions.top, Offset.zero);
  draw(regions.left, const Offset(0, decorTop));
  draw(regions.right, Offset(regions.width - decorSide, decorTop));
  draw(regions.bottom, Offset(0, regions.height - decorSide));
}
