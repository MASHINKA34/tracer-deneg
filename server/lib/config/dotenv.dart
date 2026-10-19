/// Результат разбора `.env`: значения и предупреждения о строках,
/// которые не удалось разобрать (без содержимого строк — там могут быть секреты).
class DotEnv {
  const DotEnv(this.values, this.warnings);

  final Map<String, String> values;
  final List<String> warnings;
}

final RegExp _key = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

/// Разбирает файл `.env`: строки `KEY=VALUE`, комментарии `#`, пустые строки,
/// необязательный `export `, значения в одинарных или двойных кавычках.
DotEnv parseDotEnv(String content) {
  final values = <String, String>{};
  final warnings = <String>[];
  final text = content.startsWith('﻿') ? content.substring(1) : content;
  final lines = text.split(RegExp(r'\r?\n'));

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    if (line.startsWith('export ')) line = line.substring(7).trimLeft();

    final eq = line.indexOf('=');
    if (eq <= 0) {
      warnings.add('line ${i + 1}: expected KEY=VALUE');
      continue;
    }
    final key = line.substring(0, eq).trim();
    if (!_key.hasMatch(key)) {
      warnings.add('line ${i + 1}: invalid key name');
      continue;
    }
    values[key] = _parseValue(line.substring(eq + 1).trim());
  }
  return DotEnv(values, warnings);
}

String _parseValue(String raw) {
  if (raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')) {
    return raw
        .substring(1, raw.length - 1)
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\"', '"')
        .replaceAll(r'\\', r'\');
  }
  if (raw.length >= 2 && raw.startsWith("'") && raw.endsWith("'")) {
    return raw.substring(1, raw.length - 1);
  }
  final comment = raw.indexOf(' #');
  return (comment >= 0 ? raw.substring(0, comment) : raw).trimRight();
}
