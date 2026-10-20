import 'package:shared/shared.dart';
import 'package:test/test.dart';

List<List<int?>> _days(YearMonth month) => [
  for (final week in monthGrid(month)) [for (final d in week) d?.day],
];

void main() {
  group('monthGrid', () {
    test('октябрь 2026: 1-е — четверг, 5 недель', () {
      final grid = _days(YearMonth(2026, 10));
      expect(grid, hasLength(5));
      expect(grid.first, [null, null, null, 1, 2, 3, 4]);
      expect(grid.last, [26, 27, 28, 29, 30, 31, null]);
    });

    test('февраль 2026: 1-е — воскресенье (как в макете Масленицы)', () {
      final grid = _days(YearMonth(2026, 2));
      expect(grid, hasLength(5));
      expect(grid.first, [null, null, null, null, null, null, 1]);
      expect(grid.last, [23, 24, 25, 26, 27, 28, null]);
    });

    test('ноябрь 2026 — 6 недель', () {
      final grid = _days(YearMonth(2026, 11));
      expect(grid, hasLength(6));
      expect(grid.last, [30, null, null, null, null, null, null]);
    });

    test('февраль 2021 — ровно 4 недели без пустых ячеек', () {
      final grid = _days(YearMonth(2021, 2));
      expect(grid, hasLength(4));
      expect(grid.first, [1, 2, 3, 4, 5, 6, 7]);
      expect(grid.last, [22, 23, 24, 25, 26, 27, 28]);
    });

    test('каждая неделя — 7 ячеек, дни идут подряд', () {
      final cells = monthGrid(YearMonth(2028, 2)).expand((w) => w).toList();
      expect(cells.length % 7, 0);
      expect(cells.whereType<LocalDate>().map((d) => d.day), [
        for (var i = 1; i <= 29; i++) i,
      ]);
    });
  });

  group('дни и месяцы относительно сегодня', () {
    final today = LocalDate(2026, 10, 19);

    test('прошедший / сегодня / будущий день', () {
      expect(dayKind(LocalDate(2026, 10, 18), today), DayKind.past);
      expect(dayKind(today, today), DayKind.today);
      expect(dayKind(LocalDate(2026, 10, 20), today), DayKind.future);
    });

    test('будущие месяцы недоступны, › на текущем неактивна', () {
      expect(isFutureMonth(YearMonth(2026, 11), today), isTrue);
      expect(isFutureMonth(YearMonth(2026, 10), today), isFalse);
      expect(canOpenMonth(YearMonth(2026, 1), today), isTrue);
      expect(canOpenMonth(YearMonth(2027, 1), today), isFalse);
      expect(canGoToNextMonth(YearMonth(2026, 10), today), isFalse);
      expect(canGoToNextMonth(YearMonth(2026, 9), today), isTrue);
    });

    test('прошедшие дни месяца', () {
      expect(elapsedDays(YearMonth(2026, 10), today), 19);
      expect(elapsedDays(YearMonth(2026, 9), today), 30);
      expect(elapsedDays(YearMonth(2026, 11), today), 0);
    });
  });
}
