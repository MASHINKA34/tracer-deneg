import '../time/local_date.dart';
import '../time/year_month.dart';

final RegExp _instantWithZone = RegExp(r'(Z|[+-]\d{2}:?\d{2})$');

/// Момент времени в едином виде моделей: UTC, точность — миллисекунды
/// (так он без потерь проходит через JSON и сравнивается в LWW).
DateTime normalizeInstant(DateTime instant) {
  final utc = instant.toUtc();
  return DateTime.fromMillisecondsSinceEpoch(
    utc.millisecondsSinceEpoch,
    isUtc: true,
  );
}

/// Момент для JSON: ISO-8601 UTC с миллисекундами — `2026-10-19T15:40:12.345Z`.
String encodeInstant(DateTime instant) {
  final t = normalizeInstant(instant);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year.toString().padLeft(4, '0')}-${two(t.month)}-${two(t.day)}'
      'T${two(t.hour)}:${two(t.minute)}:${two(t.second)}'
      '.${t.millisecond.toString().padLeft(3, '0')}Z';
}

/// Момент из JSON: ISO-8601 обязательно с зоной (`Z` или `+03:00`);
/// без зоны — [FormatException] (неясно, чьё это локальное время).
DateTime decodeInstant(String text) {
  if (!_instantWithZone.hasMatch(text)) {
    throw FormatException('Expected ISO-8601 instant with time zone', text);
  }
  return normalizeInstant(DateTime.parse(text));
}

/// Чтение полей JSON-объекта с понятной ошибкой: `Expense.amountKopecks:
/// expected int, got String`. Неизвестные поля игнорируются.
final class JsonReader {
  JsonReader(this.json, this.type);

  /// Проверяет, что [value] — JSON-объект.
  factory JsonReader.of(Object? value, String type) {
    if (value is Map<String, Object?>) return JsonReader(value, type);
    throw FormatException(
      '$type: expected JSON object, got ${value.runtimeType}',
    );
  }

  final Map<String, Object?> json;

  /// Имя типа для сообщений об ошибках.
  final String type;

  FormatException _error(String key, String expected) => FormatException(
    '$type.$key: expected $expected, got '
    '${json.containsKey(key) ? json[key].runtimeType : 'nothing'}',
  );

  T _required<T>(String key, String expected) {
    final value = json[key];
    if (value is T) return value;
    throw _error(key, expected);
  }

  T? _optional<T>(String key, String expected) {
    final value = json[key];
    if (value == null || value is T) return value as T?;
    throw _error(key, expected);
  }

  String string(String key) => _required<String>(key, 'string');
  String? optString(String key) => _optional<String>(key, 'string or null');
  int integer(String key) => _required<int>(key, 'int');
  int? optInteger(String key) => _optional<int>(key, 'int or null');
  bool boolean(String key) => _required<bool>(key, 'bool');

  T _parsed<T>(String key, String expected, T Function(String) parse) {
    final text = string(key);
    try {
      return parse(text);
    } on FormatException catch (e) {
      throw FormatException('$type.$key: expected $expected (${e.message})');
    }
  }

  T? _optParsed<T>(String key, String expected, T Function(String) parse) =>
      json[key] == null ? null : _parsed(key, expected, parse);

  LocalDate date(String key) => _parsed(key, 'YYYY-MM-DD', LocalDate.parse);

  YearMonth month(String key) => _parsed(key, 'YYYY-MM', YearMonth.parse);

  YearMonth? optMonth(String key) =>
      _optParsed(key, 'YYYY-MM or null', YearMonth.parse);

  DateTime instant(String key) =>
      _parsed(key, 'ISO-8601 instant', decodeInstant);

  DateTime? optInstant(String key) =>
      _optParsed(key, 'ISO-8601 instant or null', decodeInstant);

  /// Значение перечисления по имени (`personal` → `BudgetKind.personal`).
  E enumByName<E extends Enum>(String key, List<E> values) {
    final name = string(key);
    for (final value in values) {
      if (value.name == name) return value;
    }
    throw FormatException(
      '$type.$key: unknown value "$name", '
      'expected one of ${values.map((v) => v.name).join(', ')}',
    );
  }

  E? optEnumByName<E extends Enum>(String key, List<E> values) =>
      json[key] == null ? null : enumByName(key, values);

  /// Список строк.
  List<String> strings(String key) {
    final list = _required<List<Object?>>(key, 'list of strings');
    return [
      for (final item in list)
        item is String ? item : throw _error(key, 'list of strings'),
    ];
  }

  /// Список объектов, каждый разбирается [parse].
  List<T> objects<T>(String key, T Function(Object? json) parse) {
    final list = _required<List<Object?>>(key, 'list');
    return [for (final item in list) parse(item)];
  }

  /// Вложенный объект или `null`.
  Map<String, Object?>? optObject(String key) =>
      _optional<Map<String, Object?>>(key, 'object or null');
}
