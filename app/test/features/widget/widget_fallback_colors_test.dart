import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/features/widget/home_widget_data.dart';
import 'package:milionchik/ui/tokens/tokens.g.dart';

const _res = 'android/app/src/main/res';

Map<String, String> _colors(String file) {
  final xml = File(file).readAsStringSync();
  return {
    for (final m in RegExp(
      r'<color name="([^"]+)">([^<]+)</color>',
    ).allMatches(xml))
      m.group(1)!: m.group(2)!.trim().toUpperCase(),
  };
}

void main() {
  test('цвета виджета до первых данных в светлой теме - bg/surface и '
      'text/primary из neutralLight', () {
    expect(_colors('$_res/values/widget_colors.xml'), {
      'widget_fallback_surface': homeWidgetColor(neutralLight.bgSurface),
      'widget_fallback_text': homeWidgetColor(neutralLight.textPrimary),
    });
  });

  test('цвета виджета до первых данных в тёмной теме - bg/surface и '
      'text/primary из neutralDark', () {
    expect(_colors('$_res/values-night/widget_colors.xml'), {
      'widget_fallback_surface': homeWidgetColor(neutralDark.bgSurface),
      'widget_fallback_text': homeWidgetColor(neutralDark.textPrimary),
    });
  });
}
