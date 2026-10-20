import 'dart:math';

import 'package:shared/shared.dart';
import 'package:test/test.dart';

int _sum(List<int> values) => values.fold(0, (a, b) => a + b);

void main() {
  group('percentShares', () {
    test('три равные доли: 34 + 33 + 33', () {
      expect(percentShares([1, 1, 1]), [34, 33, 33]);
    });

    test('шесть равных долей', () {
      expect(percentShares([1, 1, 1, 1, 1, 1]), [17, 17, 17, 17, 16, 16]);
    });

    test('наибольший остаток получает лишний процент', () {
      expect(percentShares([1, 2, 3]), [17, 33, 50]);
      expect(percentShares([333, 333, 334]), [33, 33, 34]);
    });

    test('при равных остатках — бо́льшая сумма', () {
      // 12,5 % / 25 % / 62,5 %: у первой и третьей одинаковый остаток.
      expect(percentShares([1, 2, 5]), [12, 25, 63]);
      expect(percentShares([5, 2, 1]), [63, 25, 12]);
    });

    test('пусто и нули', () {
      expect(percentShares([]), <int>[]);
      expect(percentShares([0, 0]), [0, 0]);
      expect(percentShares([5]), [100]);
      expect(percentShares([0, 5]), [0, 100]);
    });

    test('отрицательные суммы — ошибка', () {
      expect(() => percentShares([5, -1]), throwsArgumentError);
    });

    test('неудобные наборы всегда дают ровно 100', () {
      final random = Random(20261020);
      for (var round = 0; round < 500; round++) {
        final amounts = List.generate(
          1 + random.nextInt(12),
          (_) => random.nextInt(4) == 0 ? 0 : random.nextInt(10000000),
        );
        if (_sum(amounts) == 0) amounts[0] = 1;
        final shares = percentShares(amounts);
        expect(_sum(shares), 100, reason: 'amounts=$amounts');
        final total = _sum(amounts);
        for (var i = 0; i < amounts.length; i++) {
          final floor = amounts[i] * 100 ~/ total;
          expect(shares[i], inInclusiveRange(floor, floor + 1));
        }
      }
    });
  });
}
