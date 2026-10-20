import '../money/money.dart';

final RegExp _amountQuery = RegExp(r'^(\d+)(?:[,.](\d{0,2}))?$');
final RegExp _spaces = RegExp(r'\s');
final RegExp _leadingZeros = RegExp(r'^0+(?=\d)');

/// Текст для поиска: нижний регистр, «ё» = «е», без пробелов по краям
/// (00-spec §12 п.12). Им же нормализуется поле для поиска в БД.
String normalizeSearchText(String text) =>
    text.trim().toLowerCase().replaceAll('ё', 'е');

/// Есть ли нормализованный [query] в нормализованном [text]. Пустой запрос
/// совпадает со всем.
bool textMatches(String query, String text) =>
    normalizeSearchText(text).contains(normalizeSearchText(query));

/// Запрос суммы: целые рубли и, если введена запятая, начало копеек.
final class AmountQuery {
  const AmountQuery({required this.rubles, this.kopecks});

  /// Цифры рублей без ведущих нулей («0640» → «640»).
  final String rubles;

  /// Цифры после запятой (0–2) или `null`, если запятой не было.
  final String? kopecks;

  @override
  bool operator ==(Object other) =>
      other is AmountQuery &&
      other.rubles == rubles &&
      other.kopecks == kopecks;

  @override
  int get hashCode => Object.hash(rubles, kopecks);

  @override
  String toString() => 'AmountQuery($rubles,${kopecks ?? '-'})';
}

/// Разбор запроса как суммы: цифры (пробелы внутри не важны) и, возможно,
/// `,` или `.` с 0–2 цифрами. Не сумма — `null`.
AmountQuery? parseAmountQuery(String query) {
  final match = _amountQuery.firstMatch(query.replaceAll(_spaces, ''));
  if (match == null) return null;
  return AmountQuery(
    rubles: match.group(1)!.replaceFirst(_leadingZeros, ''),
    kopecks: match.group(2),
  );
}

/// Совпадает ли сумма [amount] с запросом [query]: начало записи суммы в
/// рублях — «640» находит 640 ₽, 640,50 ₽ и 6 400 ₽. С запятой рубли
/// совпадают точно, а копейки — по началу: «149,9» находит 149,90 ₽.
bool amountMatches(String query, Money amount) {
  final parsed = parseAmountQuery(query);
  if (parsed == null) return false;
  final rubles = '${amount.kopecks.abs() ~/ 100}';
  final kopecks = parsed.kopecks;
  if (kopecks == null) return rubles.startsWith(parsed.rubles);
  // Сравнение строками: длинный ввод не переполняет int.
  if (parsed.rubles != rubles) return false;
  return amount.kopecksPart.toString().padLeft(2, '0').startsWith(kopecks);
}

/// Совпадение траты с запросом: комментарий, название категории или сумма.
bool expenseMatches({
  required String query,
  required String comment,
  required String categoryName,
  required Money amount,
}) =>
    textMatches(query, comment) ||
    textMatches(query, categoryName) ||
    amountMatches(query, amount);
