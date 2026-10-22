import 'package:shared/shared.dart';
import 'package:test/test.dart';

void main() {
  final today = LocalDate(2026, 10, 19);

  group('elapsedMonths', () {
    test('текущий год — по текущий месяц включительно', () {
      expect(elapsedMonths(2026, today), 10);
      expect(elapsedMonths(2026, LocalDate(2026, 1, 1)), 1);
      expect(elapsedMonths(2026, LocalDate(2026, 12, 31)), 12);
    });

    test('прошлый год — все 12, будущий — 0', () {
      expect(elapsedMonths(2025, today), 12);
      expect(elapsedMonths(1990, today), 12);
      expect(elapsedMonths(2027, today), 0);
    });
  });

  group('averagePerMonth', () {
    test('как в 46:5398: 211 350 ₽ за январь–октябрь → 21 135 ₽ / мес', () {
      final average = averagePerMonth(
        yearTotal: const Money.rubles(211350),
        year: 2026,
        today: today,
      );
      expect(average, const Money.rubles(21135));
      expect(average!.formatTotal(), '21${nbsp}135$nbsp₽');
    });

    test('месяцы до первой траты тоже делят: трата только в октябре', () {
      expect(
        averagePerMonth(
          yearTotal: const Money.rubles(18300),
          year: 2026,
          today: today,
        ),
        const Money.rubles(1830),
      );
    });

    test('будущие месяцы текущего года не делят', () {
      expect(
        averagePerMonth(
          yearTotal: const Money.rubles(1200),
          year: 2026,
          today: LocalDate(2026, 3, 1),
        ),
        const Money.rubles(400),
      );
    });

    test('прошлый год — на 12 месяцев', () {
      expect(
        averagePerMonth(
          yearTotal: const Money.rubles(120000),
          year: 2025,
          today: today,
        ),
        const Money.rubles(10000),
      );
    });

    test('половина копейки округляется вверх', () {
      expect(
        averagePerMonth(yearTotal: const Money(5), year: 2026, today: today),
        const Money(1),
      );
      expect(
        averagePerMonth(yearTotal: const Money(15), year: 2026, today: today),
        const Money(2),
      );
    });

    test('нет трат или будущий год — «—»', () {
      expect(
        averagePerMonth(yearTotal: Money.zero, year: 2026, today: today),
        isNull,
      );
      expect(
        averagePerMonth(
          yearTotal: const Money(100),
          year: 2027,
          today: today,
        ),
        isNull,
      );
    });
  });
}
