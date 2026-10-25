import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/ui/decor/decor_painter.dart';
import 'package:shared/shared.dart' show Mood;

import '../../data/api/fake_api_adapter.dart' show LogCapture;

const Size _size = Size(336, 423);

final List<Mood> _holidays = Mood.values
    .where(
      (m) => !const {
        Mood.winter,
        Mood.spring,
        Mood.summer,
        Mood.autumn,
      }.contains(m),
    )
    .toList();

Future<Uint8List> _pixels(DecorPainter painter) async {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), _size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    _size.width.toInt(),
    _size.height.toInt(),
  );
  picture.dispose();
  final bytes = await image.toByteData();
  image.dispose();
  return bytes!.buffer.asUint8List();
}

int _differentPixels(Uint8List a, Uint8List b) {
  var count = 0;
  for (var i = 0; i < a.length; i += 4) {
    if (a[i] != b[i] ||
        a[i + 1] != b[i + 1] ||
        a[i + 2] != b[i + 2] ||
        a[i + 3] != b[i + 3]) {
      count++;
    }
  }
  return count;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(DecorPainter.clearCache);
  tearDown(DecorPainter.clearCache);

  for (final brightness in ui.Brightness.values) {
    test('${brightness.name}: первый кадр анимации каждого праздника '
        'пиксель в пиксель как статичная картинка, а кадр посреди цикла '
        'отличается', () async {
      for (final mood in _holidays) {
        final still = await _pixels(
          DecorPainter(mood: mood, brightness: brightness),
        );
        final first = await _pixels(
          DecorPainter(
            mood: mood,
            brightness: brightness,
            opening: true,
            animation: const AlwaysStoppedAnimation(0),
          ),
        );
        final middle = await _pixels(
          DecorPainter(
            mood: mood,
            brightness: brightness,
            animation: const AlwaysStoppedAnimation(0.37),
          ),
        );
        expect(_differentPixels(first, still), 0, reason: mood.name);
        expect(
          _differentPixels(middle, still),
          greaterThan(20),
          reason: mood.name,
        );
      }
    });
  }

  test('сезон с анимацией рисуется статично: кадров не строит', () async {
    final still = await _pixels(
      DecorPainter(mood: Mood.autumn, brightness: ui.Brightness.light),
    );
    final animated = await _pixels(
      DecorPainter(
        mood: Mood.autumn,
        brightness: ui.Brightness.light,
        animation: const AlwaysStoppedAnimation(0.5),
      ),
    );
    expect(_differentPixels(animated, still), 0);
    expect(DecorPainter.cachedAnimations, 0);
  });

  test('2 с анимации при 60 кадрах: статичные части узора записаны один '
      'раз, полная статичная картинка не строится, а каждый кадр только '
      'двигает готовые элементы', () {
    final logs = LogCapture();
    addTearDown(logs.dispose);
    final controller = AnimationController(
      vsync: const TestVSync(),
      duration: const Duration(seconds: 6),
    );
    addTearDown(controller.dispose);
    final painter = DecorPainter(
      mood: Mood.newyear,
      brightness: ui.Brightness.light,
      animation: controller,
    );
    for (var frame = 0; frame <= 120; frame++) {
      controller.value = frame / 360;
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), _size);
      recorder.endRecording().dispose();
    }

    final decor = logs.records.where((r) => r.loggerName == 'decor').toList();
    expect(decor, hasLength(1));
    expect(
      decor.single.message,
      matches(
        RegExp(
          r'^decor animation frames cached layer=newyear theme=light '
          r'size=336\.0x423\.0 motions=\d+ moving=\d+ still=\d+ in \d+ms '
          r'\(cache miss\)$',
        ),
      ),
    );
    expect(DecorPainter.cachedAnimations, 1);
    expect(DecorPainter.cachedPictures, 0);
  });
}
