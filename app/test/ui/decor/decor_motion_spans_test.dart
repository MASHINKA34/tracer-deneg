import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/ui/decor/decor_generator.dart';

Map<DecorMotion, int> _counts(DecorRegions regions) {
  final counts = <DecorMotion, int>{};
  for (final s in regions.motions) {
    counts[s.motion] = (counts[s.motion] ?? 0) + 1;
  }
  return counts;
}

void main() {
  const width = 336.0;
  const height = 423.0;

  test('сезоны - без анимаций: ни одного движущегося элемента', () {
    for (final layer in DecorLayer.values.where((l) => l.isSeason)) {
      expect(
        generateDecor(layer, width: width, height: height).motions,
        isEmpty,
        reason: layer.key,
      );
    }
  });

  test('у каждого праздника свои движения из 00-spec §7.6.6 и макета '
      '31:4010, чужих нет', () {
    final expected = <DecorLayer, Set<DecorMotion>>{
      DecorLayer.newyear: {DecorMotion.blink, DecorMotion.swing},
      DecorLayer.valentine: {DecorMotion.beat},
      DecorLayer.defender: {DecorMotion.twinkle, DecorMotion.flutter},
      DecorLayer.maslenitsa: {DecorMotion.spin, DecorMotion.hop},
      DecorLayer.women: {DecorMotion.sway},
      DecorLayer.labour: {DecorMotion.knock},
      DecorLayer.victory: {DecorMotion.flash},
      DecorLayer.children: {DecorMotion.rise, DecorMotion.string},
      DecorLayer.knowledge: {DecorMotion.ring, DecorMotion.fall},
      DecorLayer.halloweenCute: {DecorMotion.bob},
      DecorLayer.halloweenSpooky: {
        DecorMotion.descend,
        DecorMotion.thread,
        DecorMotion.flapLeft,
        DecorMotion.flapRight,
      },
      DecorLayer.birthday: {DecorMotion.swing, DecorMotion.confetti},
    };
    for (final MapEntry(key: layer, value: motions) in expected.entries) {
      final regions = generateDecor(layer, width: width, height: height);
      expect(_counts(regions).keys.toSet(), motions, reason: layer.key);
    }
  });

  test('сколько элементов движется: 16 огоньков гирлянды, одна стопка '
      'блинов, один колокольчик, шесть салютов, один призрачок и один паук; '
      'у каждого шарика 1 июня - ниточка, у летучей мыши - два крыла', () {
    Map<DecorMotion, int> of(DecorLayer layer) =>
        _counts(generateDecor(layer, width: width, height: height));

    expect(of(DecorLayer.newyear)[DecorMotion.blink], 16);
    expect(of(DecorLayer.maslenitsa)[DecorMotion.hop], 1);
    expect(of(DecorLayer.knowledge)[DecorMotion.ring], 1);
    expect(of(DecorLayer.victory)[DecorMotion.flash], 6);
    expect(of(DecorLayer.halloweenCute)[DecorMotion.bob], 1);
    final spooky = of(DecorLayer.halloweenSpooky);
    expect(spooky[DecorMotion.descend], 1);
    expect(spooky[DecorMotion.thread], 1);
    expect(spooky[DecorMotion.flapLeft], spooky[DecorMotion.flapRight]);
    expect(spooky[DecorMotion.flapLeft], greaterThanOrEqualTo(6));
    final children = of(DecorLayer.children);
    expect(children[DecorMotion.string], children[DecorMotion.rise]);
  });

  test('разметка ссылается на настоящие элементы своей области, а '
      'вложенные движения лежат внутри внешних (ниточка внутри шарика)', () {
    for (final layer in DecorLayer.values.where((l) => !l.isSeason)) {
      for (final h in const [373.0, 423.0, 473.0]) {
        for (final w in const [296.0, 336.0, 388.0]) {
          final regions = generateDecor(layer, width: w, height: h);
          for (final s in regions.motions) {
            final elements = regions.of(s.region);
            expect(s.start, lessThan(s.end), reason: '$layer $s');
            expect(s.start, greaterThanOrEqualTo(0), reason: '$layer $s');
            expect(s.end, lessThanOrEqualTo(elements.length), reason: '$s');
            for (final other in regions.motions) {
              if (identical(other, s) || other.region != s.region) continue;
              final overlap = s.start < other.end && other.start < s.end;
              if (!overlap) continue;
              final inside = s.start >= other.start && s.end <= other.end;
              final outside = other.start >= s.start && other.end <= s.end;
              expect(inside || outside, isTrue, reason: '$layer $s / $other');
            }
          }
        }
      }
    }
  });

  test('точки опоры у композиции возле стрелок сдвигаются вместе с ней на '
      'широкой карточке', () {
    final base = generateDecor(DecorLayer.knowledge, width: 336, height: 423);
    final wide = generateDecor(DecorLayer.knowledge, width: 388, height: 423);
    final bell = base.motions.singleWhere((s) => s.motion == DecorMotion.ring);
    final wideBell = wide.motions.singleWhere(
      (s) => s.motion == DecorMotion.ring,
    );
    expect(bell.pivotX, 212);
    expect(bell.pivotY, closeTo(35 - 0.72 * 12, 1e-9));
    expect(wideBell.pivotX, 212 + 52);
    expect(wideBell.pivotY, bell.pivotY);
  });

  test('огоньки и кубики конфетти по краям: по порядку слева направо, '
      'конфетти по бокам падает на 22 px, сверху на 10, снизу на 6', () {
    final newyear = generateDecor(DecorLayer.newyear, width: 336, height: 423);
    final lights = [
      for (final s in newyear.motions)
        if (s.motion == DecorMotion.blink) s,
    ];
    expect([for (final s in lights) s.order], List.generate(16, (i) => i));
    for (var i = 1; i < lights.length; i++) {
      expect(lights[i].pivotX, greaterThan(lights[i - 1].pivotX));
    }

    final birthday = generateDecor(
      DecorLayer.birthday,
      width: 336,
      height: 423,
    );
    final fall = {
      for (final s in birthday.motions)
        if (s.motion == DecorMotion.confetti) s.region: s.amount,
    };
    expect(fall, {
      DecorRegion.top: 10,
      DecorRegion.left: 22,
      DecorRegion.right: 22,
      DecorRegion.bottom: 6,
    });
  });
}
