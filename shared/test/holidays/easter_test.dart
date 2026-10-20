import 'package:shared/shared.dart';
import 'package:test/test.dart';

void main() {
  // Таблица 00-spec §7.6.2: год → Пасха, Масленица (пн–вс).
  const table = <(int, String, String, String)>[
    (2026, '2026-04-12', '2026-02-16', '2026-02-22'),
    (2027, '2027-05-02', '2027-03-08', '2027-03-14'),
    (2028, '2028-04-16', '2028-02-21', '2028-02-27'),
    (2029, '2029-04-08', '2029-02-12', '2029-02-18'),
    (2030, '2030-04-28', '2030-03-04', '2030-03-10'),
    (2031, '2031-04-13', '2031-02-17', '2031-02-23'),
    (2032, '2032-05-02', '2032-03-08', '2032-03-14'),
    (2033, '2033-04-24', '2033-02-28', '2033-03-06'),
    (2034, '2034-04-09', '2034-02-13', '2034-02-19'),
    (2035, '2035-04-29', '2035-03-05', '2035-03-11'),
  ];

  group('Пасха и Масленица 2026–2035', () {
    for (final (year, easter, start, end) in table) {
      test('$year: Пасха $easter, Масленица $start…$end', () {
        expect(orthodoxEaster(year), LocalDate.parse(easter));
        expect(forgivenessSunday(year), LocalDate.parse(end));
        final maslenitsa = holidayOccurrence(HolidayKey.maslenitsa, year);
        expect(maslenitsa.start, LocalDate.parse(start));
        expect(maslenitsa.end, LocalDate.parse(end));
        expect(maslenitsa.day, LocalDate.parse(end));
        expect(maslenitsa.start.weekday, 1);
        expect(maslenitsa.end.weekday, 7);
      });
    }
  });

  test('известные даты Пасхи: 2024 — 5 мая, 2025 — 20 апреля', () {
    expect(orthodoxEaster(2024), LocalDate(2024, 5, 5));
    expect(orthodoxEaster(2025), LocalDate(2025, 4, 20));
  });

  test('годы до григорианского календаря — ошибка', () {
    expect(() => orthodoxEaster(1500), throwsRangeError);
  });
}
