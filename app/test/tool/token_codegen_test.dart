import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/ui/tokens/tokens.g.dart';
import 'package:shared/shared.dart';

import '../../tool/src/token_codegen.dart';

Map<String, Object?> _realTokens() =>
    jsonDecode(File('tool/design-tokens.json').readAsStringSync())
        as Map<String, Object?>;

void main() {
  group('hexToArgb: #RRGGBBAA (альфа в конце) → 0xAARRGGBB', () {
    test('альфа переставляется в начало', () {
      expect(hexToArgb('#1E1A1573'), 0x731E1A15);
      expect(hexToArgb('#3BA55C2E'), 0x2E3BA55C);
      expect(hexToArgb('#0000009E'), 0x9E000000);
    });

    test('без альфы — непрозрачный', () {
      expect(hexToArgb('#FFFFFF'), 0xFFFFFFFF);
      expect(hexToArgb('#c2541c'), 0xFFC2541C);
    });

    test('неверный формат — FormatException', () {
      for (final bad in ['#12', 'FFFFFF', '#GGGGGG', '#FFFFFFF', '']) {
        expect(() => hexToArgb(bad), throwsFormatException, reason: bad);
      }
    });

    test('литерал Color', () {
      expect(colorLiteral(0x731E1A15), 'Color(0x731E1A15)');
      expect(colorLiteral(0x0D1E1A15), 'Color(0x0D1E1A15)');
    });
  });

  test('имена ключей Figma → поля Dart', () {
    expect(dartName('bg/surface-2'), 'bgSurface2');
    expect(dartName('on-accent'), 'onAccent');
    expect(dartName('accent-strong'), 'accentStrong');
    expect(dartName('Display/XL'), 'displayXl');
    expect(dartName('Cell/Amount'), 'cellAmount');
    expect(dartName('scrim'), 'scrim');
  });

  group('сгенерированный tokens.g.dart', () {
    test('альфа из JSON стоит в старшем байте Color', () {
      // scrim: «#1E1A1573» / «#0000009E».
      expect(neutralLight.scrim, const Color(0x731E1A15));
      expect(neutralDark.scrim, const Color(0x9E000000));
      expect(neutralLight.scrim.a, closeTo(0x73 / 255, 1e-9));
      // category/green/soft: «#3BA55C2E».
      expect(categoryLight[CategoryColor.green]!.soft, const Color(0x2E3BA55C));
      // mood/knowledge/heat-3: «#F2B83A8C».
      expect(moodLight[Mood.knowledge]!.heat3, const Color(0x8CF2B83A));
    });

    test('все 15 настроений и 10 цветов категорий в обеих темах', () {
      for (final palette in [moodLight, moodDark]) {
        expect(palette.keys.toSet(), Mood.values.toSet());
      }
      for (final palette in [categoryLight, categoryDark]) {
        expect(palette.keys.toSet(), CategoryColor.values.toSet());
      }
      expect(TextStyleTokens.all, hasLength(19));
    });

    test('совпадает с тем, что генерирует tool/design-tokens.json', () {
      final result = generateTokens(_realTokens());
      expect(result.source, contains('heat3: Color(0x8CF2B83A)'));
      expect(result.stats.moods, 15);
      expect(result.stats.categories, 10);
      expect(result.stats.textStyles, 19);
      expect(
        result.stats.skipped,
        contains(startsWith('mood.halloween.banner-subtitle')),
      );
    });
  });

  group('ошибки формата — с путём ключа', () {
    TokenFormatException errorsOf(void Function(Map<String, Object?>) edit) {
      final json = _realTokens();
      edit(json);
      try {
        generateTokens(json);
      } on TokenFormatException catch (e) {
        return e;
      }
      fail('ожидалась TokenFormatException');
    }

    Map<String, Object?> obj(Object? v) => v! as Map<String, Object?>;

    test('битый цвет', () {
      final e = errorsOf((j) {
        obj(obj(j['mood'])['autumn'])['heat-1'] = ['#12', '#F0884A29'];
      });
      expect(e.errors.single.path, 'mood.autumn.heat-1[0]');
      expect(e.errors.single.message, contains('#RRGGBB'));
    });

    test('не пара [светлая, тёмная]', () {
      final e = errorsOf((j) => obj(j['neutral'])['scrim'] = '#000000');
      expect(e.errors.single.path, 'neutral.scrim');
    });

    test('нет настроения и лишний ключ у другого', () {
      final e = errorsOf((j) {
        obj(j['mood']).remove('summer');
        obj(obj(j['mood'])['winter'])['glow'] = ['#FFFFFF', '#000000'];
      });
      expect(
        e.errors.map((x) => x.path),
        containsAll(['mood.summer', 'mood.winter.glow']),
      );
    });

    test('неизвестный цвет категории', () {
      final e = errorsOf((j) {
        obj(j['category'])['brown'] = {
          'solid': ['#000000', '#000000'],
          'soft': ['#000000', '#000000'],
        };
      });
      expect(e.errors.single.path, 'category.brown');
    });

    test('стиль без жирности', () {
      final e = errorsOf((j) {
        obj((j['textStyles']! as List)[0])['weight'] = 'SemiBold';
      });
      expect(e.errors.single.path, 'textStyles[0] (Display/XL)');
    });
  });
}
