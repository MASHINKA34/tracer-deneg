import 'package:shared/shared.dart';
import 'package:test/test.dart';

void main() {
  group('isLeapYear / daysInMonth', () {
    test('високосные годы', () {
      expect(isLeapYear(2028), isTrue);
      expect(isLeapYear(2026), isFalse);
      expect(isLeapYear(2000), isTrue);
      expect(isLeapYear(2100), isFalse);
    });

    test('дни в месяцах', () {
      expect(daysInMonth(2026, 2), 28);
      expect(daysInMonth(2028, 2), 29);
      expect(daysInMonth(2026, 4), 30);
      expect(daysInMonth(2026, 10), 31);
      expect(() => daysInMonth(2026, 13), throwsRangeError);
    });
  });

  group('LocalDate', () {
    test('несуществующие даты — ошибка', () {
      expect(() => LocalDate(2026, 2, 29), throwsRangeError);
      expect(() => LocalDate(2026, 4, 31), throwsRangeError);
      expect(() => LocalDate(2026, 0, 1), throwsRangeError);
      expect(() => LocalDate(0, 1, 1), throwsRangeError);
      expect(LocalDate(2028, 2, 29).day, 29);
    });

    test('разбор и формат YYYY-MM-DD', () {
      final date = LocalDate.parse('2026-10-19');
      expect(date, LocalDate(2026, 10, 19));
      expect(date.toString(), '2026-10-19');
      expect(date.toJson(), '2026-10-19');
      expect(LocalDate(2026, 3, 5).toString(), '2026-03-05');
    });

    test('неверные строки — FormatException', () {
      expect(() => LocalDate.parse('2026-10-1'), throwsFormatException);
      expect(() => LocalDate.parse('19.10.2026'), throwsFormatException);
      expect(() => LocalDate.parse('2026-02-30'), throwsFormatException);
      expect(LocalDate.tryParse('nope'), isNull);
      expect(LocalDate.tryParse('2026-01-31'), LocalDate(2026, 1, 31));
    });

    test('из DateTime берутся поля как на часах', () {
      expect(
        LocalDate.fromDateTime(DateTime(2026, 10, 19, 23, 59)),
        LocalDate(2026, 10, 19),
      );
    });

    test('день недели: 1 — понедельник', () {
      expect(LocalDate(2026, 10, 19).weekday, 1);
      expect(LocalDate(2026, 2, 22).weekday, 7);
    });

    test('арифметика дней через границы месяцев и лет', () {
      expect(LocalDate(2026, 12, 31).addDays(1), LocalDate(2027, 1, 1));
      expect(LocalDate(2026, 3, 1).addDays(-1), LocalDate(2026, 2, 28));
      expect(LocalDate(2026, 12, 25).daysUntil(LocalDate(2027, 1, 1)), 7);
      expect(LocalDate(2027, 1, 5).daysUntil(LocalDate(2027, 1, 1)), -4);
      // Переход на летнее время не влияет: считаем в UTC.
      expect(LocalDate(2026, 3, 1).daysUntil(LocalDate(2026, 4, 1)), 31);
    });

    test('сравнение', () {
      final a = LocalDate(2026, 10, 19);
      final b = LocalDate(2026, 10, 20);
      expect(a < b, isTrue);
      expect(a <= a, isTrue);
      expect(b > a, isTrue);
      expect(b >= b, isTrue);
      expect(a.isBefore(b), isTrue);
      expect(b.isAfter(a), isTrue);
      expect(a.compareTo(LocalDate(2026, 11, 1)), lessThan(0));
      expect(a.compareTo(LocalDate(2025, 12, 31)), greaterThan(0));
      expect(a.hashCode, LocalDate(2026, 10, 19).hashCode);
      expect(a.yearMonth, YearMonth(2026, 10));
    });
  });

  group('YearMonth', () {
    test('разбор и формат YYYY-MM', () {
      expect(YearMonth.parse('2026-10'), YearMonth(2026, 10));
      expect(YearMonth(2026, 3).toString(), '2026-03');
      expect(YearMonth(2026, 3).toJson(), '2026-03');
      expect(() => YearMonth.parse('2026-13'), throwsFormatException);
      expect(() => YearMonth.parse('2026-1'), throwsFormatException);
      expect(YearMonth.tryParse('x'), isNull);
      expect(YearMonth.tryParse('2027-01'), YearMonth(2027, 1));
      expect(() => YearMonth(2026, 0), throwsRangeError);
    });

    test('дни, первый и последний день', () {
      final feb = YearMonth(2028, 2);
      expect(feb.daysInMonth, 29);
      expect(feb.firstDay, LocalDate(2028, 2, 1));
      expect(feb.lastDay, LocalDate(2028, 2, 29));
      expect(feb.dayOf(15), LocalDate(2028, 2, 15));
      expect(feb.contains(LocalDate(2028, 2, 10)), isTrue);
      expect(feb.contains(LocalDate(2028, 3, 1)), isFalse);
      expect(YearMonth.of(LocalDate(2026, 10, 19)), YearMonth(2026, 10));
    });

    test('соседние месяцы через границу года', () {
      expect(YearMonth(2026, 12).next, YearMonth(2027, 1));
      expect(YearMonth(2027, 1).previous, YearMonth(2026, 12));
      expect(YearMonth(2026, 10).addMonths(-10), YearMonth(2025, 12));
      expect(YearMonth(2026, 7).monthsUntil(YearMonth(2027, 2)), 7);
    });

    test('сравнение', () {
      final a = YearMonth(2026, 9);
      final b = YearMonth(2026, 10);
      expect(a < b, isTrue);
      expect(a <= a, isTrue);
      expect(b > a, isTrue);
      expect(b >= b, isTrue);
      expect(a.compareTo(b), lessThan(0));
      expect(a.hashCode, YearMonth(2026, 9).hashCode);
    });
  });

  group('MonthDay', () {
    test('29 февраля → 28 февраля в невисокосный год', () {
      final leapDay = MonthDay(2, 29);
      expect(leapDay.inYear(2026), LocalDate(2026, 2, 28));
      expect(leapDay.inYear(2028), LocalDate(2028, 2, 29));
      expect(MonthDay(11, 14).inYear(2026), LocalDate(2026, 11, 14));
    });

    test('несуществующие дни — ошибка', () {
      expect(() => MonthDay(2, 30), throwsRangeError);
      expect(() => MonthDay(4, 31), throwsRangeError);
      expect(() => MonthDay(13, 1), throwsRangeError);
    });

    test('ближайшая дата не раньше заданной', () {
      final birthday = MonthDay(1, 2);
      expect(
        birthday.nextOnOrAfter(LocalDate(2026, 12, 28)),
        LocalDate(2027, 1, 2),
      );
      expect(
        birthday.nextOnOrAfter(LocalDate(2027, 1, 2)),
        LocalDate(2027, 1, 2),
      );
    });

    test('из частей JSON', () {
      expect(MonthDay.fromParts(null, null), isNull);
      expect(MonthDay.fromParts(2, 29), MonthDay(2, 29));
      expect(() => MonthDay.fromParts(2, null), throwsFormatException);
      expect(() => MonthDay.fromParts(2, 31), throwsFormatException);
    });

    test('сравнение и текст', () {
      expect(MonthDay(1, 31).compareTo(MonthDay(2, 1)), lessThan(0));
      expect(MonthDay(2, 2).compareTo(MonthDay(2, 1)), greaterThan(0));
      expect(MonthDay(2, 1).hashCode, MonthDay(2, 1).hashCode);
      expect(MonthDay(3, 8).toString(), 'MonthDay(08.03)');
    });
  });
}
