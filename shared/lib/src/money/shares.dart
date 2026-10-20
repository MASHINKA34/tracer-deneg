/// Целые проценты долей [amounts] с суммой ровно 100 — метод наибольших
/// остатков (00-spec §7.1).
///
/// Каждой доле — целая часть процента, оставшиеся проценты по одному
/// получают доли с наибольшим остатком; при равных остатках — бо́льшая сумма,
/// затем та, что раньше в списке. Все суммы нулевые (или список пуст) — все
/// доли 0. Отрицательные суммы — [ArgumentError].
List<int> percentShares(List<int> amounts) {
  for (final amount in amounts) {
    if (amount < 0) {
      throw ArgumentError.value(amounts, 'amounts', 'must not be negative');
    }
  }
  final total = amounts.fold(0, (sum, a) => sum + a);
  if (total == 0) return List.filled(amounts.length, 0);

  final shares = [for (final a in amounts) a * 100 ~/ total];
  final remainders = [for (final a in amounts) a * 100 % total];
  var left = 100 - shares.fold(0, (sum, s) => sum + s);

  final order = List.generate(amounts.length, (i) => i)
    ..sort((a, b) {
      final byRemainder = remainders[b].compareTo(remainders[a]);
      if (byRemainder != 0) return byRemainder;
      final byAmount = amounts[b].compareTo(amounts[a]);
      if (byAmount != 0) return byAmount;
      return a.compareTo(b);
    });
  for (final i in order) {
    if (left == 0) break;
    shares[i]++;
    left--;
  }
  return shares;
}
