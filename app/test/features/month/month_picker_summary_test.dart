import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milionchik/features/month/month_picker_sheet.dart';
import 'package:shared/shared.dart';

Map<int, Money> _rubles(Map<int, int> days) => {
  for (final MapEntry(key: day, value: rubles) in days.entries)
    day: Money.rubles(rubles),
};

List<Money> _year(List<int> rubles) => [
  for (final r in rubles) Money.rubles(r),
];

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  group('столбики', () {
    test('высота ∝ итог месяца / максимум года: максимум — 64 из 72, '
        'остальные в той же доле, округление до целого', () {
      final heights = monthBarHeights(
        _year([
          21260,
          19740,
          22020,
          17850,
          20880,
          23540,
          24300,
          22780,
          20500,
          18300,
          0,
          0,
        ]),
      );
      expect(heights, [56, 52, 58, 47, 55, 62, 64, 60, 54, 48, 0, 0]);
      expect(heights.reduce((a, b) => a > b ? a : b), monthBarMaxHeight);
      expect(monthBarMaxHeight, lessThanOrEqualTo(monthBarArea));
    });

    test('месяц вдвое дешевле — столбик вдвое ниже', () {
      final heights = monthBarHeights(
        _year([1000, 500, 250, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
      );
      expect(heights.take(3), [64, 32, 16]);
    });

    test('за год трат нет — все столбики нулевые, самого дорогого нет', () {
      final empty = List<Money>.filled(12, Money.zero);
      expect(monthBarHeights(empty), List<double>.filled(12, 0));
      expect(priciestMonth(empty), isNull);
    });

    test(
      'самый дорогой — месяц с наибольшим итогом, при равенстве — ранний',
      () {
        expect(
          priciestMonth(_year([10, 30, 20, 30, 0, 0, 0, 0, 0, 0, 0, 0])),
          2,
        );
        expect(
          priciestMonth(_year([0, 0, 0, 0, 0, 0, 24300, 100, 0, 0, 0, 0])),
          7,
        );
      },
    );
  });

  group('сводка и сравнение (00-spec §2.1, §7.3)', () {
    final october = YearMonth(2026, 10);
    final today = LocalDate(2026, 10, 19);

    test('текущий месяц: 1–19 октября против 1–19 сентября, траты сентября '
        'после 19-го не считаются', () {
      final summary = MonthPickerSummary.of(
        month: october,
        today: today,
        total: Money.rubles(18300),
        days: _rubles({3: 18000, 19: 300}),
        previousDays: _rubles({12: 20400, 20: 5000, 30: 100}),
      );
      expect(
        summary.period,
        ComparisonPeriod(
          currentFrom: LocalDate(2026, 10, 1),
          currentTo: LocalDate(2026, 10, 19),
          previousFrom: LocalDate(2026, 9, 1),
          previousTo: LocalDate(2026, 9, 19),
        ),
      );
      expect(summary.comparison!.difference, Money.rubles(-2100));
      expect(summary.comparison!.isLess, isTrue);
      expect(summary.total, Money.rubles(18300));
      expect(summary.average, Money(96316));
    });

    test('прошедший месяц: полный против полного', () {
      final summary = MonthPickerSummary.of(
        month: YearMonth(2026, 9),
        today: today,
        total: Money.rubles(25500),
        days: _rubles({12: 20400, 20: 5000, 30: 100}),
        previousDays: _rubles({1: 1000, 31: 2000}),
      );
      expect(summary.period.currentTo, LocalDate(2026, 9, 30));
      expect(summary.period.previousTo, LocalDate(2026, 8, 31));
      expect(summary.comparison!.difference, Money.rubles(22500));
      expect(summary.comparison!.isMore, isTrue);
      expect(summary.average, Money.rubles(850));
    });

    test('31 марта: прошлый отрезок — до конца февраля', () {
      final summary = MonthPickerSummary.of(
        month: YearMonth(2026, 3),
        today: LocalDate(2026, 3, 31),
        total: Money.rubles(100),
        days: _rubles({31: 100}),
        previousDays: _rubles({28: 300}),
      );
      expect(summary.period.previousTo, LocalDate(2026, 2, 28));
      expect(summary.comparison!.difference, Money.rubles(-200));
    });

    test('в прошлом месяце трат нет — сравнения нет', () {
      final summary = MonthPickerSummary.of(
        month: october,
        today: today,
        total: Money.rubles(500),
        days: _rubles({1: 500}),
        previousDays: const {},
      );
      expect(summary.comparison, isNull);
    });

    test('траты прошлого месяца только после сегодняшнего числа — для '
        'текущего месяца сравнения нет', () {
      final summary = MonthPickerSummary.of(
        month: october,
        today: today,
        total: Money.rubles(500),
        days: _rubles({1: 500}),
        previousDays: _rubles({25: 900}),
      );
      expect(summary.comparison, isNull);
    });

    test(
      'суммы по дням ещё не пришли — сравнения нет, итог и среднее есть',
      () {
        final summary = MonthPickerSummary.of(
          month: october,
          today: today,
          total: Money.rubles(1900),
          days: null,
          previousDays: _rubles({1: 100}),
        );
        expect(summary.comparison, isNull);
        expect(summary.average, Money.rubles(100));
      },
    );

    test('месяц без трат — среднего нет', () {
      final summary = MonthPickerSummary.of(
        month: YearMonth(2025, 10),
        today: today,
        total: Money.zero,
        days: const {},
        previousDays: const {},
      );
      expect(summary.average, isNull);
      expect(summary.comparison, isNull);
    });

    test('будущий месяц в сводку не попадает — ArgumentError из shared', () {
      expect(
        () => MonthPickerSummary.of(
          month: YearMonth(2026, 11),
          today: today,
          total: Money.zero,
          days: const {},
          previousDays: const {},
        ),
        throwsArgumentError,
      );
    });
  });

  group('подписи', () {
    test('название, заголовок сводки и эмодзи сезона выбранного месяца', () {
      expect(monthName(YearMonth(2026, 9)), 'сентябрь');
      expect(monthTitle(YearMonth(2026, 10)), 'Октябрь 2026');
      expect(monthTitle(YearMonth(2026, 5)), 'Май 2026');
      expect(seasonEmoji(YearMonth(2026, 1)), '❄️');
      expect(seasonEmoji(YearMonth(2026, 4)), '🌷');
      expect(seasonEmoji(YearMonth(2026, 7)), '☀️');
      expect(seasonEmoji(YearMonth(2026, 10)), '🍂');
    });
  });
}
