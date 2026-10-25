import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _reader =
    'android/app/src/main/kotlin/ru/milionchik/app/widget/'
    'WidgetData.kt';

const _allowedInterpolations = {
  'WIDGET_DATA_KEY',
  'WIDGET_DATA_VERSION',
  'bytes',
  'character',
  'path',
  'version',
  'key',
  'position(e)',
  'typeName(stored)',
  'typeName(value)',
};

void main() {
  late String source;

  setUpAll(() => source = File(_reader).readAsStringSync());

  test('в строки WidgetData.kt подставляются только имена полей, размер, '
      'версия, тип значения и номер символа - не сами данные', () {
    final literals = RegExp(r'"((?:[^"\\]|\\.)*)"').allMatches(source);
    final used = <String>{};
    for (final literal in literals) {
      final text = literal.group(1)!;
      for (final m in RegExp(
        r'\$\{([^}]*)\}|\$([A-Za-z_][A-Za-z0-9_]*)',
      ).allMatches(text)) {
        final name = m.group(1) ?? m.group(2)!;
        used.add(name);
        expect(_allowedInterpolations, contains(name), reason: text);
      }
    }
    expect(used, containsAll(['path', 'bytes', 'position(e)']));
  });

  test('WidgetDataException без причины: текст исключения org.json и '
      'Color.parseColor не уходит в лог через cause и стек', () {
    expect(
      source,
      contains(
        'internal class WidgetDataException(message: String) : '
        'Exception(message)',
      ),
    );
    expect(source, isNot(contains('initCause')));
    expect(
      RegExp(r'WidgetDataException\([^)]*,\s*e\)').hasMatch(source),
      isFalse,
    );
  });

  test('текст исключения читается только ради номера символа', () {
    final lines = source
        .split('\n')
        .where((line) => line.contains('.message'))
        .toList();
    expect(lines, hasLength(1));
    expect(lines.single, contains('atCharacter.find(e.message'));
  });

  test('сырые данные не подставляются ни в одну строку', () {
    expect(source, isNot(contains(r'$raw')));
    expect(source, isNot(contains(r'${raw')));
    expect(source, isNot(contains(r'${json')));
    expect(source, isNot(contains(r'$json')));
  });
}
