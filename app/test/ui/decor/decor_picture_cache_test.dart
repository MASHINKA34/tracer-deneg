import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/ui/decor/decor_painter.dart';
import 'package:shared/shared.dart' show Mood;

import '../../data/api/fake_api_adapter.dart' show LogCapture;

final RegExp _cachedLine = RegExp(
  r'^decor picture cached layer=(\S+) theme=(\S+) size=(\S+) shapes=(\d+) '
  r'in \d+ms \(cache miss\)$',
);

void _paint(DecorPainter painter, Size size) {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), size);
  recorder.endRecording().dispose();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LogCapture logs;

  setUp(() {
    DecorPainter.clearCache();
    logs = LogCapture();
  });

  tearDown(() async {
    await logs.dispose();
    DecorPainter.clearCache();
  });

  List<String> generated() => [
    for (final r in logs.records)
      if (r.loggerName == 'decor' &&
          r.message.startsWith('decor picture cached'))
        r.message,
  ];

  List<String> keys() => [
    for (final line in generated())
      _cachedLine.firstMatch(line)!.groups([1, 2, 3]).join(' '),
  ];

  test('фаза анимации меняется каждый кадр (2 с при 60 кадрах) - узор не '
      'пересчитывается: одна картинка на слой, тему и размер', () {
    const size = Size(336, 423);
    for (var frame = 0; frame <= 120; frame++) {
      final painter = DecorPainter(
        mood: Mood.newyear,
        brightness: ui.Brightness.light,
        phase: frame / 120,
      );
      if (frame > 0) {
        expect(
          painter.shouldRepaint(
            DecorPainter(
              mood: Mood.newyear,
              brightness: ui.Brightness.light,
              phase: (frame - 1) / 120,
            ),
          ),
          isTrue,
        );
      }
      _paint(painter, size);
    }

    expect(keys(), ['newyear light 336.0x423.0']);
    final shapes = int.parse(_cachedLine.firstMatch(generated().single)![4]!);
    expect(shapes, greaterThan(0));
    expect(DecorPainter.cachedPictures, 1);
    expect(logs.records.where((r) => r.loggerName == 'decor'), hasLength(1));
  });

  test('Хеллоуин: светлая и тёмная - разные слои, каждый генерируется один '
      'раз при любом числе переключений; карточка выше (6 недель) - своя '
      'картинка', () {
    const fiveWeeks = Size(336, 423);
    const sixWeeks = Size(336, 473);
    for (var i = 0; i < 5; i++) {
      _paint(
        DecorPainter(mood: Mood.halloween, brightness: ui.Brightness.light),
        fiveWeeks,
      );
      _paint(
        DecorPainter(mood: Mood.halloween, brightness: ui.Brightness.dark),
        fiveWeeks,
      );
    }
    _paint(
      DecorPainter(mood: Mood.halloween, brightness: ui.Brightness.dark),
      sixWeeks,
    );

    expect(keys(), [
      'halloween-cute light 336.0x423.0',
      'halloween-spooky dark 336.0x423.0',
      'halloween-spooky dark 336.0x473.0',
    ]);
    expect(DecorPainter.cachedPictures, 3);
  });
}
