/// 10 цветов категорий и аватаров (`category/*` в `design-tokens.json`).
/// Имя значения — ключ в JSON и БД.
enum CategoryColor {
  green,
  orange,
  yellow,
  blue,
  red,
  purple,
  pink,
  teal,
  indigo,
  rose;

  /// Цвет по ключу или `null`, если ключ неизвестен.
  static CategoryColor? fromKey(String key) => values.asNameMap()[key];
}
