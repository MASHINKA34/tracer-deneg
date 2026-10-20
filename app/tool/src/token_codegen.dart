/// Генерация `lib/ui/tokens/tokens.g.dart` из `tool/design-tokens.json`
/// (выгрузка переменных Figma). Чистая логика без `dart:io` — её
/// проверяют тесты (`test/tool/token_codegen_test.dart`), а запускает
/// `tool/gen_tokens.dart`.
library;

import 'package:shared/shared.dart' show CategoryColor, Mood;

/// Ошибка формата токена: [path] — путь ключа в JSON (`mood.autumn.heat-1`).
final class TokenFormatError {
  const TokenFormatError(this.path, this.message);

  final String path;
  final String message;

  @override
  String toString() => '$path: $message';
}

/// Все ошибки формата сразу — чтобы поправить JSON за один проход.
final class TokenFormatException implements Exception {
  const TokenFormatException(this.errors);

  final List<TokenFormatError> errors;

  @override
  String toString() =>
      'TokenFormatException: ${errors.length} error(s): ${errors.join('; ')}';
}

final RegExp _hexColor = RegExp(r'^#([0-9A-Fa-f]{6})([0-9A-Fa-f]{2})?$');

/// Цвет из JSON (`#RRGGBB` или `#RRGGBBAA`, альфа В КОНЦЕ) → значение
/// Flutter `Color(0xAARRGGBB)` (альфа В НАЧАЛЕ). Без альфы — `FF`.
///
/// `hexToArgb('#1E1A1573')` → `0x731E1A15`.
int hexToArgb(String hex) {
  final match = _hexColor.firstMatch(hex);
  if (match == null) {
    throw FormatException('expected #RRGGBB or #RRGGBBAA', hex);
  }
  final rgb = int.parse(match.group(1)!, radix: 16);
  final alpha = match.group(2) == null
      ? 0xFF
      : int.parse(match.group(2)!, radix: 16);
  return (alpha << 24) | rgb;
}

/// `0x731E1A15` → `Color(0x731E1A15)`.
String colorLiteral(int argb) =>
    'Color(0x${argb.toRadixString(16).toUpperCase().padLeft(8, '0')})';

/// Имя ключа Figma → имя поля Dart: `bg/surface-2` → `bgSurface2`,
/// `Display/XL` → `displayXl`, `on-accent` → `onAccent`.
String dartName(String key) {
  final parts = key
      .split(RegExp(r'[/\- ]+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) throw FormatException('empty token name', key);
  final buffer = StringBuffer(parts.first.toLowerCase());
  for (final part in parts.skip(1)) {
    buffer
      ..write(part[0].toUpperCase())
      ..write(part.substring(1).toLowerCase());
  }
  return buffer.toString();
}

/// Сколько чего прочитано и сгенерировано — для лога генератора.
final class TokenStats {
  int neutral = 0;
  int categories = 0;
  int moods = 0;
  int colors = 0;
  int radii = 0;
  int spaces = 0;
  int textStyles = 0;
  int shadows = 0;
  final List<String> skipped = [];

  @override
  String toString() =>
      'neutral=$neutral categories=$categories moods=$moods colors=$colors '
      'radii=$radii spaces=$spaces textStyles=$textStyles shadows=$shadows '
      'skipped=${skipped.length}';
}

/// Результат генерации: исходник `tokens.g.dart` и статистика.
final class TokenCodegenResult {
  const TokenCodegenResult(this.source, this.stats);

  final String source;
  final TokenStats stats;
}

/// Ключи с подчёркиванием (`_about`) — комментарии выгрузки, не токены.
bool _isComment(String key) => key.startsWith('_');

/// Строит исходник `tokens.g.dart` из разобранного JSON [json].
/// Бросает [TokenFormatException] со всеми найденными ошибками.
/// Пропущенные ключи (тексты, неизвестные разделы) — в [TokenStats.skipped].
TokenCodegenResult generateTokens(Map<String, Object?> json) {
  final errors = <TokenFormatError>[];
  final stats = TokenStats();
  final out = StringBuffer();

  int? color(String path, Object? value) {
    if (value is! String) {
      errors.add(
        TokenFormatError(
          path,
          'expected color string, got ${_describe(value)}',
        ),
      );
      return null;
    }
    try {
      stats.colors++;
      return hexToArgb(value);
    } on FormatException catch (e) {
      errors.add(TokenFormatError(path, '${e.message}, got "$value"'));
      return null;
    }
  }

  /// Пара `[светлая, тёмная]`.
  (int, int)? pair(String path, Object? value) {
    if (value is! List || value.length != 2) {
      errors.add(
        TokenFormatError(
          path,
          'expected [light, dark] pair, got ${_describe(value)}',
        ),
      );
      return null;
    }
    final light = color('$path[0]', value[0]);
    final dark = color('$path[1]', value[1]);
    if (light == null || dark == null) return null;
    return (light, dark);
  }

  Map<String, Object?>? section(String path) {
    final value = json[path];
    if (value is Map<String, Object?>) return value;
    errors.add(
      TokenFormatError(path, 'expected object, got ${_describe(value)}'),
    );
    return null;
  }

  out.writeln(_header);

  // ---------- neutral ----------
  final neutral = section('neutral');
  if (neutral != null) {
    final fields = <String, (String key, (int, int)? value)>{};
    neutral.forEach((key, value) {
      if (_isComment(key)) return;
      fields[dartName(key)] = (key, pair('neutral.$key', value));
      stats.neutral++;
    });
    out.write(
      _paletteClass(
        'NeutralTokens',
        'Нейтральные цвета одной темы (`neutral/*`).',
        {for (final e in fields.entries) e.key: e.value.$1},
      ),
    );
    for (final (index, theme) in const ['Light', 'Dark'].indexed) {
      out
        ..writeln()
        ..writeln('/// `neutral/*`, ${index == 0 ? 'светлая' : 'тёмная'} тема.')
        ..writeln('const neutral$theme = NeutralTokens(');
      for (final e in fields.entries) {
        final value = e.value.$2;
        if (value == null) continue;
        out.writeln(
          '  ${e.key}: ${colorLiteral(index == 0 ? value.$1 : value.$2)},',
        );
      }
      out.writeln(');');
    }
  }

  // ---------- category ----------
  final category = section('category');
  if (category != null) {
    out
      ..writeln()
      ..write(
        _paletteClass(
          'CategoryTokens',
          'Цвет категории: `solid` — столбики и диаграммы, `soft` — подложка '
              'под эмодзи (уже с альфой).',
          {'solid': 'solid', 'soft': 'soft'},
        ),
      );
    final entries = <String, ((int, int)?, (int, int)?)>{};
    category.forEach((key, value) {
      if (_isComment(key)) return;
      if (CategoryColor.fromKey(key) == null) {
        errors.add(
          TokenFormatError(
            'category.$key',
            'unknown category color (expected one of ${CategoryColor.values.map((c) => c.name).join(', ')})',
          ),
        );
        return;
      }
      if (value is! Map<String, Object?>) {
        errors.add(
          TokenFormatError(
            'category.$key',
            'expected object, got ${_describe(value)}',
          ),
        );
        return;
      }
      entries[key] = (
        pair('category.$key.solid', value['solid']),
        pair('category.$key.soft', value['soft']),
      );
      stats.categories++;
    });
    for (final missing in CategoryColor.values.where(
      (c) => !entries.containsKey(c.name),
    )) {
      errors.add(
        TokenFormatError(
          'category.${missing.name}',
          'missing (CategoryColor.${missing.name} has no tokens)',
        ),
      );
    }
    for (final (index, theme) in const ['Light', 'Dark'].indexed) {
      out
        ..writeln()
        ..writeln(
          '/// `category/*`, ${index == 0 ? 'светлая' : 'тёмная'} тема.',
        )
        ..writeln(
          'const Map<CategoryColor, CategoryTokens> category$theme = {',
        );
      for (final c in CategoryColor.values) {
        final e = entries[c.name];
        if (e == null || e.$1 == null || e.$2 == null) continue;
        final solid = index == 0 ? e.$1!.$1 : e.$1!.$2;
        final soft = index == 0 ? e.$2!.$1 : e.$2!.$2;
        out
          ..writeln('  CategoryColor.${c.name}: CategoryTokens(')
          ..writeln('    solid: ${colorLiteral(solid)},')
          ..writeln('    soft: ${colorLiteral(soft)},')
          ..writeln('  ),');
      }
      out.writeln('};');
    }
  }

  // ---------- mood ----------
  final mood = section('mood');
  if (mood != null) {
    final entries = <String, Map<String, (int, int)?>>{};
    mood.forEach((moodKey, value) {
      if (_isComment(moodKey)) return;
      final path = 'mood.$moodKey';
      if (!Mood.values.any((m) => m.name == moodKey)) {
        errors.add(
          TokenFormatError(
            path,
            'unknown mood (expected one of ${Mood.values.map((m) => m.name).join(', ')})',
          ),
        );
        return;
      }
      if (value is! Map<String, Object?>) {
        errors.add(
          TokenFormatError(path, 'expected object, got ${_describe(value)}'),
        );
        return;
      }
      final colors = <String, (int, int)?>{};
      value.forEach((key, v) {
        if (_isComment(key)) return;
        // Тексты (подпись плашки Хеллоуина) — не цвета: место им в ARB.
        if (v is List &&
            v.isNotEmpty &&
            v.first is String &&
            !(v.first as String).startsWith('#')) {
          stats.skipped.add('$path.$key (text, not a color)');
          return;
        }
        colors[key] = pair('$path.$key', v);
      });
      entries[moodKey] = colors;
      stats.moods++;
    });
    // Набор ключей у всех настроений одинаковый (00-spec §6.2). Эталон —
    // ключи большинства настроений: тогда опечатка в одном настроении
    // даёт одну ошибку у него, а не по ошибке у всех остальных.
    final keyCounts = <String, int>{};
    for (final colors in entries.values) {
      for (final k in colors.keys) {
        keyCounts[k] = (keyCounts[k] ?? 0) + 1;
      }
    }
    final keys = [
      for (final e in keyCounts.entries)
        if (e.value * 2 > entries.length) e.key,
    ];
    entries.forEach((moodKey, colors) {
      for (final k in keys.where((k) => !colors.containsKey(k))) {
        errors.add(
          TokenFormatError('mood.$moodKey.$k', 'missing (other moods have it)'),
        );
      }
      for (final k in colors.keys.where((k) => !keys.contains(k))) {
        errors.add(
          TokenFormatError(
            'mood.$moodKey.$k',
            'unexpected key (most moods do not have it)',
          ),
        );
      }
    });
    for (final missing in Mood.values.where(
      (m) => !entries.containsKey(m.name),
    )) {
      errors.add(
        TokenFormatError(
          'mood.${missing.name}',
          'missing (Mood.${missing.name} has no palette)',
        ),
      );
    }
    final moodKeys = keys;
    out
      ..writeln()
      ..write(
        _paletteClass(
          'MoodTokens',
          'Палитра «настроения» (сезон или праздник), одна тема: `accent` — '
              'кнопки, «+», сегодня; `soft` — фон карточки месяца; `heat*` — '
              'подсветка дней (с альфой); `decor*` — узор по краям карточки.',
          {for (final k in moodKeys) dartName(k): k},
        ),
      );
    for (final (index, theme) in const ['Light', 'Dark'].indexed) {
      out
        ..writeln()
        ..writeln('/// `mood/*`, ${index == 0 ? 'светлая' : 'тёмная'} тема.')
        ..writeln('const Map<Mood, MoodTokens> mood$theme = {');
      for (final m in Mood.values) {
        final colors = entries[m.name];
        if (colors == null || colors.values.any((v) => v == null)) continue;
        out.writeln('  Mood.${m.name}: MoodTokens(');
        for (final k in moodKeys) {
          final v = colors[k];
          if (v == null) continue;
          out.writeln(
            '    ${dartName(k)}: ${colorLiteral(index == 0 ? v.$1 : v.$2)},',
          );
        }
        out.writeln('  ),');
      }
      out.writeln('};');
    }
  }

  // ---------- radius ----------
  final radius = section('radius');
  if (radius != null) {
    out
      ..writeln()
      ..writeln('/// Радиусы скругления (`radius/*`).')
      ..writeln('abstract final class RadiusTokens {');
    radius.forEach((key, value) {
      if (_isComment(key)) return;
      if (value is! num) {
        errors.add(
          TokenFormatError(
            'radius.$key',
            'expected number, got ${_describe(value)}',
          ),
        );
        return;
      }
      out.writeln('  static const double ${dartName(key)} = ${_num(value)};');
      stats.radii++;
    });
    out.writeln('}');
  }

  // ---------- space ----------
  final space = json['space'];
  if (space is List && space.every((v) => v is num)) {
    out
      ..writeln()
      ..writeln('/// Отступы: сетка 4 (`space`).')
      ..writeln('abstract final class SpaceTokens {');
    for (final v in space.cast<num>()) {
      out.writeln('  static const double s${_num(v)} = ${_num(v)};');
      stats.spaces++;
    }
    out
      ..writeln()
      ..writeln('  /// Вся шкала по возрастанию.')
      ..writeln(
        '  static const List<double> scale = [${space.cast<num>().map(_num).join(', ')}];',
      )
      ..writeln('}');
  } else {
    errors.add(
      TokenFormatError(
        'space',
        'expected list of numbers, got ${_describe(space)}',
      ),
    );
  }

  // ---------- textStyles ----------
  final textStyles = json['textStyles'];
  if (textStyles is List) {
    out
      ..writeln()
      ..writeln(_textStyleTokenClass)
      ..writeln()
      ..writeln('/// Текстовые стили (`textStyles`).')
      ..writeln('abstract final class TextStyleTokens {');
    final names = <String>[];
    for (final (i, raw) in textStyles.indexed) {
      final path = 'textStyles[$i]';
      if (raw is! Map<String, Object?>) {
        errors.add(
          TokenFormatError(path, 'expected object, got ${_describe(raw)}'),
        );
        continue;
      }
      final name = raw['name'];
      final family = raw['family'];
      final weightText = raw['weight'];
      final size = raw['size'];
      final lineHeight = raw['lineHeight'];
      final tracking = raw['letterSpacingPct'];
      final uppercase = raw['uppercase'] ?? false;
      final label = name is String ? '$path ($name)' : path;
      final weight = weightText is String
          ? int.tryParse(
              RegExp(r'(\d{3})\s*$').firstMatch(weightText)?.group(1) ?? '',
            )
          : null;
      if (name is! String ||
          family is! String ||
          weight == null ||
          size is! num ||
          lineHeight is! num ||
          tracking is! num ||
          uppercase is! bool) {
        errors.add(
          TokenFormatError(
            label,
            'expected {name, family, weight "<Name> <100..900>", size, lineHeight, letterSpacingPct, uppercase?}, got $raw',
          ),
        );
        continue;
      }
      final field = dartName(name);
      names.add(field);
      out
        ..writeln(
          '  /// `$name`: $family $weightText, ${_num(size)}/${_num(lineHeight)}'
          '${tracking == 0 ? '' : ', трекинг ${_num(tracking)} %'}${uppercase ? ', прописными' : ''}.',
        )
        ..writeln('  static const $field = TextStyleToken(')
        ..writeln("    name: '$name',")
        ..writeln("    family: '$family',")
        ..writeln('    weight: $weight,')
        ..writeln('    size: ${_num(size)},')
        ..writeln('    lineHeight: ${_num(lineHeight)},')
        ..writeln('    letterSpacingPct: ${_num(tracking)},')
        ..writeln('    uppercase: $uppercase,')
        ..writeln('  );');
      stats.textStyles++;
    }
    out
      ..writeln()
      ..writeln('  /// Все стили в порядке выгрузки.')
      ..writeln(
        '  static const List<TextStyleToken> all = [${names.join(', ')}];',
      )
      ..writeln('}');
  } else {
    errors.add(
      TokenFormatError(
        'textStyles',
        'expected list, got ${_describe(textStyles)}',
      ),
    );
  }

  // ---------- shadows ----------
  final shadows = section('shadows');
  if (shadows != null) {
    out
      ..writeln()
      ..writeln('/// Тени (`shadows/*`), одинаковые в обеих темах.')
      ..writeln('abstract final class ShadowTokens {');
    shadows.forEach((key, value) {
      if (_isComment(key)) return;
      final path = 'shadows.$key';
      if (value is! List) {
        errors.add(
          TokenFormatError(
            path,
            'expected list of layers, got ${_describe(value)}',
          ),
        );
        return;
      }
      out.writeln('  static const List<BoxShadow> ${dartName(key)} = [');
      for (final (i, layer) in value.indexed) {
        final p = '$path[$i]';
        if (layer is! Map<String, Object?>) {
          errors.add(
            TokenFormatError(p, 'expected object, got ${_describe(layer)}'),
          );
          continue;
        }
        final x = layer['x'],
            y = layer['y'],
            blur = layer['blur'],
            spread = layer['spread'];
        final c = color('$p.color', layer['color']);
        if (x is! num || y is! num || blur is! num || spread is! num) {
          errors.add(
            TokenFormatError(
              p,
              'expected numbers x, y, blur, spread, got $layer',
            ),
          );
          continue;
        }
        if (c == null) continue;
        out
          ..writeln('    BoxShadow(')
          ..writeln('      offset: Offset(${_num(x)}, ${_num(y)}),')
          ..writeln('      blurRadius: ${_num(blur)},')
          ..writeln('      spreadRadius: ${_num(spread)},')
          ..writeln('      color: ${colorLiteral(c)},')
          ..writeln('    ),');
      }
      out.writeln('  ];');
      stats.shadows++;
    });
    out.writeln('}');
  }

  for (final key in json.keys) {
    if (_isComment(key)) continue;
    if (!const {
      'neutral',
      'category',
      'mood',
      'radius',
      'space',
      'textStyles',
      'shadows',
    }.contains(key)) {
      stats.skipped.add('$key (unknown section)');
    }
  }

  if (errors.isNotEmpty) throw TokenFormatException(errors);
  return TokenCodegenResult(out.toString(), stats);
}

String _describe(Object? value) => switch (value) {
  null => 'null',
  String() => 'string "$value"',
  num() => 'number $value',
  bool() => 'bool $value',
  List() => 'list of ${value.length}',
  Map() => 'object',
  _ => value.runtimeType.toString(),
};

/// `8` → `8`, `-0.5` → `-0.5` (без лишнего `.0`, как пишут в Dart).
String _num(num v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

/// Класс палитры с полями-цветами и `lerp` (плавная смена темы).
String _paletteClass(String name, String doc, Map<String, String> fields) {
  final b = StringBuffer()
    ..writeln('/// $doc')
    ..writeln('final class $name {')
    ..writeln('  const $name({');
  for (final f in fields.keys) {
    b.writeln('    required this.$f,');
  }
  b.writeln('  });');
  for (final e in fields.entries) {
    b
      ..writeln()
      ..writeln('  /// `${e.value}`')
      ..writeln('  final Color ${e.key};');
  }
  b
    ..writeln()
    ..writeln(
      '  /// Плавный переход между палитрами (смена темы и настроения).',
    )
    ..writeln('  static $name lerp($name a, $name b, double t) => $name(');
  for (final f in fields.keys) {
    b.writeln('    $f: Color.lerp(a.$f, b.$f, t)!,');
  }
  b.writeln('  );');
  b.writeln('}');
  return b.toString();
}

const String _header = '''
// GENERATED CODE - DO NOT MODIFY BY HAND.
// Источник: tool/design-tokens.json (переменные Figma kaggd9sqW9jdeRA6MOMZ80).
// Перегенерировать из папки app: dart run tool/gen_tokens.dart

import 'package:flutter/painting.dart';
import 'package:shared/shared.dart' show CategoryColor, Mood;
''';

const String _textStyleTokenClass = '''
/// Текстовый стиль из Figma: семейство, жирность, кегль и межстрочный
/// интервал в пикселях, трекинг в процентах кегля.
final class TextStyleToken {
  const TextStyleToken({
    required this.name,
    required this.family,
    required this.weight,
    required this.size,
    required this.lineHeight,
    required this.letterSpacingPct,
    required this.uppercase,
  });

  /// Имя стиля в Figma (`Display/XL`).
  final String name;
  final String family;

  /// 100…900.
  final int weight;
  final double size;
  final double lineHeight;
  final double letterSpacingPct;

  /// Текст пишется прописными (месяц).
  final bool uppercase;
}''';
