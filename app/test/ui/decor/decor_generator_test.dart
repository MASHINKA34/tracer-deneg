import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/ui/decor/decor_generator.dart';
import 'package:milionchik/ui/decor/decor_shapes.dart';
import 'package:milionchik/ui/decor/mulberry32.dart';

/// Эталон `fixtures/decor_reference.json` — вывод JS-генератора декора,
/// которым нарисован декор в Figma (функции `seasonRegions` /
/// `holidayRegions`, ширина 336), для 16 слоёв и высот 373 / 423 / 473.
/// Перенос в Dart должен дать те же фигуры в том же порядке: тот же
/// mulberry32, сиды и порядок вызовов случайных чисел.
void main() {
  final reference = jsonDecode(
    File('test/ui/decor/fixtures/decor_reference.json').readAsStringSync(),
  ) as Map<String, Object?>;

  test('mulberry32 — те же числа, что в JS (посчитаны в node)', () {
    for (final (seed, key) in [(11, 'mulberry11'), (-5, 'mulberryMinus5')]) {
      final expected = (reference[key]! as List<Object?>).cast<num>();
      final r = Mulberry32(seed);
      for (final value in expected) {
        expect(r.next(), value.toDouble(), reason: 'seed $seed');
      }
    }
  });

  final cases = (reference['cases']! as List<Object?>)
      .cast<Map<String, Object?>>();
  for (final c in cases) {
    final key = c['key']! as String;
    final height = (c['height']! as num).toDouble();
    test('$key, высота ${height.toInt()}: как в JS-генераторе', () {
      final layer = DecorLayer.values.firstWhere((l) => l.key == key);
      final regions = generateDecor(layer, width: 336, height: height);
      for (final (name, actual) in [
        ('top', regions.top),
        ('left', regions.left),
        ('right', regions.right),
        ('bottom', regions.bottom),
      ]) {
        _expectSameShapes(c[name]! as String, actual, '$key/$height/$name');
      }
    });
  }

  test('другая ширина: стрелочная композиция сдвигается, слоты тянутся', () {
    final base = generateDecor(DecorLayer.newyear, width: 336, height: 423);
    final wide = generateDecor(DecorLayer.newyear, width: 388, height: 423);
    // Боковые полосы от ширины не зависят (тот же порядок случайных чисел).
    expect(
      wide.left.map((e) => e.svgAttributes()).toList(),
      base.left.map((e) => e.svgAttributes()).toList(),
    );
    // Нижняя полоса — циклом по фактической ширине: элементов больше.
    expect(wide.bottom.length, greaterThan(base.bottom.length));
  });
}

final RegExp _element = RegExp(r'<(path|circle) ([^>]*?)/>');
final RegExp _attribute = RegExp(r'([a-z-]+)="([^"]*)"');
final RegExp _pathToken = RegExp(r'[MLCQAZ]|-?\d+(?:\.\d+)?(?:e-?\d+)?');

void _expectSameShapes(String svg, List<DecorElement> actual, String where) {
  final expected = _element.allMatches(svg).toList();
  expect(actual.length, expected.length, reason: '$where: число фигур');
  for (var i = 0; i < expected.length; i++) {
    final m = expected[i];
    final tag = m.group(1)!;
    final attrs = {
      for (final a in _attribute.allMatches(m.group(2)!))
        a.group(1)!: a.group(2)!,
    };
    final e = actual[i];
    final at =
        '$where[$i] ${m.group(0)!.substring(0, m.group(0)!.length.clamp(0, 120))}';
    expect(e.isCircle ? 'circle' : 'path', tag, reason: at);
    final got = e.svgAttributes();
    expect(got.keys.toSet(), attrs.keys.toSet(), reason: '$at\n  got: $got');
    for (final entry in attrs.entries) {
      final value = got[entry.key]!;
      switch (entry.key) {
        case 'd':
          _expectSamePath(value, entry.value, at);
        case 'cx' || 'cy' || 'r' || 'stroke-width':
          expect(
            double.parse(value),
            closeTo(double.parse(entry.value), 0.011),
            reason: '$at ${entry.key}',
          );
        default:
          expect(value, entry.value, reason: '$at ${entry.key}');
      }
    }
  }
}

void _expectSamePath(String actual, String expected, String at) {
  final a = _pathToken.allMatches(actual).map((m) => m.group(0)!).toList();
  final b = _pathToken.allMatches(expected).map((m) => m.group(0)!).toList();
  expect(a.length, b.length, reason: '$at\n  d: $actual\n  js: $expected');
  for (var i = 0; i < a.length; i++) {
    final x = double.tryParse(a[i]);
    final y = double.tryParse(b[i]);
    if (x == null || y == null) {
      expect(a[i], b[i], reason: '$at token $i');
    } else {
      // Координаты округлены до 0,01; разница последнего знака возможна
      // из-за cos/sin разных платформ.
      expect(
        x,
        closeTo(y, 0.011),
        reason: '$at token $i\n  d: $actual\n  js: $expected',
      );
    }
  }
}
