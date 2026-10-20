import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _ = ' ';

void main() {
  group('heatLevel', () {
    test('пороги 499 / 500 / 1500 / 1501', () {
      expect(heatLevel(Money.zero), HeatLevel.zero);
      expect(heatLevel(const Money.rubles(499)), HeatLevel.low);
      expect(heatLevel(const Money.rubles(500)), HeatLevel.medium);
      expect(heatLevel(const Money.rubles(1500)), HeatLevel.medium);
      expect(heatLevel(const Money.rubles(1501)), HeatLevel.high);
    });

    test('по точной сумме в копейках', () {
      expect(heatLevel(const Money(1)), HeatLevel.low);
      expect(heatLevel(const Money(40)), HeatLevel.low);
      expect(heatLevel(const Money(49999)), HeatLevel.low);
      expect(heatLevel(const Money(150001)), HeatLevel.high);
      expect(heatLevel(const Money(-100)), HeatLevel.zero);
    });
  });

  group('averagePerDay', () {
    // Примеры с карточек праздников в Figma (31:4010): «сегодня», итог
    // месяца и «В среднем … / день».
    final figmaExamples = <(LocalDate, int, String)>[
      (LocalDate(2026, 2, 19), 16920, '891'),
      (LocalDate(2026, 12, 29), 22500, '776'),
      (LocalDate(2026, 5, 4), 2770, '693'),
      (LocalDate(2026, 2, 11), 14890, '1${_}354'),
      (LocalDate(2026, 2, 23), 23300, '1${_}013'),
      (LocalDate(2027, 3, 5), 1850, '370'),
      (LocalDate(2026, 5, 8), 7210, '901'),
      (LocalDate(2026, 6, 1), 2000, '2${_}000'),
      (LocalDate(2026, 10, 28), 25910, '925'),
      (LocalDate(2026, 11, 11), 7070, '643'),
    ];
    for (final (today, total, shown) in figmaExamples) {
      test('$today: итог $total ₽ → $shown ₽ / день', () {
        final average = averagePerDay(
          monthTotal: Money.rubles(total),
          month: YearMonth.of(today),
          today: today,
        );
        expect(average!.formatTotal(), '$shown$_₽');
      });
    }

    test('половина копейки округляется вверх', () {
      final average = averagePerDay(
        monthTotal: const Money(5),
        month: YearMonth(2026, 10),
        today: LocalDate(2026, 10, 2),
      );
      expect(average, const Money(3));
    });

    test('прошлый месяц — на все дни', () {
      final average = averagePerDay(
        monthTotal: const Money.rubles(30000),
        month: YearMonth(2026, 9),
        today: LocalDate(2026, 10, 19),
      );
      expect(average, const Money.rubles(1000));
    });

    test('нет трат или будущий месяц — «—»', () {
      final today = LocalDate(2026, 10, 19);
      expect(
        averagePerDay(
          monthTotal: Money.zero,
          month: YearMonth(2026, 10),
          today: today,
        ),
        isNull,
      );
      expect(
        averagePerDay(
          monthTotal: const Money(100),
          month: YearMonth(2026, 11),
          today: today,
        ),
        isNull,
      );
    });

    test('шторка дня: разница со средним', () {
      expect(
        differenceFromAverage(
          daySum: const Money.rubles(1100),
          average: const Money.rubles(925),
        ),
        const Money.rubles(175),
      );
      expect(
        differenceFromAverage(
          daySum: const Money.rubles(500),
          average: const Money.rubles(925),
        ).isNegative,
        isTrue,
      );
    });
  });

  group('comparisonPeriod', () {
    test(
      'текущий месяц — тот же отрезок: 1–19 октября против 1–19 сентября',
      () {
        final period = comparisonPeriod(
          YearMonth(2026, 10),
          LocalDate(2026, 10, 19),
        );
        expect(
          period,
          ComparisonPeriod(
            currentFrom: LocalDate(2026, 10, 1),
            currentTo: LocalDate(2026, 10, 19),
            previousFrom: LocalDate(2026, 9, 1),
            previousTo: LocalDate(2026, 9, 19),
          ),
        );
        expect(period.hashCode, isA<int>());
        expect(period.toString(), contains('2026-10-01..2026-10-19'));
      },
    );

    test('31 марта: в феврале отрезок обрезается по длине месяца', () {
      final period = comparisonPeriod(
        YearMonth(2026, 3),
        LocalDate(2026, 3, 31),
      );
      expect(period.previousTo, LocalDate(2026, 2, 28));
      expect(period.currentTo, LocalDate(2026, 3, 31));
    });

    test('прошедший месяц — полный против полного', () {
      final period = comparisonPeriod(
        YearMonth(2026, 9),
        LocalDate(2026, 10, 19),
      );
      expect(period.currentFrom, LocalDate(2026, 9, 1));
      expect(period.currentTo, LocalDate(2026, 9, 30));
      expect(period.previousFrom, LocalDate(2026, 8, 1));
      expect(period.previousTo, LocalDate(2026, 8, 31));
    });

    test('будущий месяц — ошибка', () {
      expect(
        () => comparisonPeriod(YearMonth(2026, 11), LocalDate(2026, 10, 19)),
        throwsArgumentError,
      );
    });
  });

  group('compareMonths', () {
    test('на 2 100 ₽ меньше, −10 %', () {
      final result = compareMonths(
        current: const Money.rubles(18900),
        previous: const Money.rubles(21000),
      )!;
      expect(result.difference, const Money.rubles(-2100));
      expect(result.difference.abs.formatTotal(), '2${_}100$_₽');
      expect(result.percent, -10);
      expect(result.isLess, isTrue);
      expect(result.isMore, isFalse);
    });

    test('больше — положительные разница и процент', () {
      final result = compareMonths(
        current: const Money(4),
        previous: const Money(3),
      )!;
      expect(result.percent, 33);
      expect(result.isMore, isTrue);
    });

    test('процент округляется от нуля', () {
      expect(
        compareMonths(
          current: const Money(105),
          previous: const Money(200),
        )!.percent,
        -48,
      );
      expect(
        compareMonths(
          current: const Money(1),
          previous: const Money(3),
        )!.percent,
        -67,
      );
      expect(
        compareMonths(
          current: const Money(301),
          previous: const Money(200),
        )!.percent,
        51,
      );
    });

    test('поровну — 0 %', () {
      final result = compareMonths(
        current: const Money(500),
        previous: const Money(500),
      )!;
      expect(result.percent, 0);
      expect(result.isMore || result.isLess, isFalse);
      expect(result, const MonthComparison(difference: Money.zero, percent: 0));
      expect(result.hashCode, isA<int>());
      expect(result.toString(), 'MonthComparison(Money(0), 0%)');
    });

    test('за прошлый отрезок трат нет — строку не показываем', () {
      expect(
        compareMonths(current: const Money(100), previous: Money.zero),
        isNull,
      );
    });
  });
}
