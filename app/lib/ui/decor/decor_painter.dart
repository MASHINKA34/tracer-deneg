import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart' show Mood;

import '../tokens/tokens.g.dart';
import 'decor_generator.dart';
import 'decor_shapes.dart';

final _log = Logger('decor');

/// Узор по краям карточки месяца — первый слой карточки, под содержимым
/// (00-spec §6.3). Цвета — `decor-1…4` настроения [mood] в теме
/// [brightness]; Хеллоуин в тёмной теме — жуткий слой.
///
/// Готовая картинка кэшируется по (настроение, тема, размер): узор
/// генерируется один раз, дальше только рисуется.
/// [phase] (0…1) — фаза анимации декора, её используют анимации этапа 13;
/// сейчас узор статичный и от фазы не зависит.
class DecorPainter extends CustomPainter {
  DecorPainter({
    required this.mood,
    required this.brightness,
    this.phase = 0,
    this.cornerRadius = 28,
  });

  final Mood mood;
  final ui.Brightness brightness;
  final double phase;

  /// Скругление карточки — узор обрезается по нему.
  final double cornerRadius;

  /// Сколько картинок держим (15 настроений × 2 темы × пара размеров).
  static const int cacheCapacity = 48;
  static final LinkedHashMap<String, ui.Picture> _cache = LinkedHashMap();

  /// Сколько картинок в кэше (для тестов и каталога).
  static int get cachedPictures => _cache.length;

  /// Очистить кэш (тесты).
  static void clearCache() {
    for (final picture in _cache.values) {
      picture.dispose();
    }
    _cache.clear();
  }

  DecorLayer get layer =>
      decorLayerOf(mood.name, dark: brightness == ui.Brightness.dark);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final key =
        '${mood.name}|${brightness.name}|'
        '${size.width.toStringAsFixed(1)}x${size.height.toStringAsFixed(1)}';
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
    paintDecorRegions(canvas, regions, palette);
    final picture = recorder.endRecording();
    _log.fine(
      'decor cache miss → generated layer=${layer.key} '
      'size=${size.width.toStringAsFixed(1)}x${size.height.toStringAsFixed(1)} '
      'shapes=${regions.elementCount} in ${sw.elapsedMilliseconds}ms',
    );
    return picture;
  }

  @override
  bool shouldRepaint(DecorPainter oldDelegate) =>
      oldDelegate.mood != mood ||
      oldDelegate.brightness != brightness ||
      oldDelegate.phase != phase ||
      oldDelegate.cornerRadius != cornerRadius;
}

/// Рисует области узора, как их собирает SVG генератора: верх — от угла,
/// левая полоса — от (0, 60), правая — от (W − 12, 60), низ — от (0, H − 12).
void paintDecorRegions(
  Canvas canvas,
  DecorRegions regions,
  MoodTokens palette,
) {
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

  draw(regions.top, Offset.zero);
  draw(regions.left, const Offset(0, decorTop));
  draw(regions.right, Offset(regions.width - decorSide, decorTop));
  draw(regions.bottom, Offset(0, regions.height - decorSide));
}
