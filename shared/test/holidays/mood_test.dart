import 'package:shared/shared.dart';
import 'package:test/test.dart';

LocalDate d(String text) => LocalDate.parse(text);

void main() {
  const allOn = HolidaySettings();

  group('Mood', () {
    test('15 настроений с ключами палитры design-tokens', () {
      expect(Mood.values.map((m) => m.key), [
        'winter',
        'spring',
        'summer',
        'autumn',
        'newyear',
        'valentine',
        'defender',
        'maslenitsa',
        'women',
        'labour',
        'victory',
        'children',
        'knowledge',
        'halloween',
        'birthday',
      ]);
    });

    test('сезон и праздник', () {
      for (final season in Season.values) {
        expect(Mood.ofSeason(season).season, season);
        expect(Mood.ofSeason(season).holiday, isNull);
      }
      for (final key in HolidayKey.values) {
        expect(Mood.ofHoliday(key).holiday, key);
        expect(Mood.ofHoliday(key).season, isNull);
      }
    });
  });

  group('moodOn: приоритеты §7.6.3', () {
    test('день рождения в Хеллоуин — день рождения', () {
      final settings = HolidaySettings(birthday: MonthDay(10, 31));
      expect(moodOn(d('2026-10-28'), settings), Mood.birthday);
      expect(moodOn(d('2026-10-31'), settings), Mood.birthday);
      expect(moodOn(d('2026-10-28'), allOn), Mood.halloween);
    });

    test('Масленица 2026 против 23 Февраля на 17–23.02', () {
      expect(moodOn(d('2026-02-16'), allOn), Mood.maslenitsa);
      for (var day = 17; day <= 22; day++) {
        final date = LocalDate(2026, 2, day);
        expect(moodOn(date, allOn), Mood.maslenitsa, reason: '$date');
      }
      expect(moodOn(d('2026-02-23'), allOn), Mood.defender);
    });

    test('8 Марта 2027 и Масленица 8–14.03', () {
      expect(moodOn(d('2027-03-05'), allOn), Mood.women);
      expect(moodOn(d('2027-03-08'), allOn), Mood.women);
      for (var day = 9; day <= 14; day++) {
        final date = LocalDate(2027, 3, day);
        expect(moodOn(date, allOn), Mood.maslenitsa, reason: '$date');
      }
      expect(moodOn(d('2027-03-15'), allOn), Mood.spring);
    });

    test('равное расстояние до «дня» — выше в таблице (2031: ⭐ и 🥞)', () {
      expect(moodOn(d('2031-02-20'), allOn), Mood.defender);
      expect(moodOn(d('2031-02-23'), allOn), Mood.defender);
    });

    test('выключенный праздник не участвует', () {
      const noMaslenitsa = HolidaySettings(disabled: {HolidayKey.maslenitsa});
      expect(moodOn(d('2026-02-18'), noMaslenitsa), Mood.defender);
      expect(moodOn(d('2026-02-16'), noMaslenitsa), Mood.winter);
    });

    test('праздники выключены целиком — сезон', () {
      final off = HolidaySettings(enabled: false, birthday: MonthDay(10, 31));
      expect(moodOn(d('2026-10-31'), off), Mood.autumn);
      expect(moodOn(d('2026-12-31'), off), Mood.winter);
      expect(activeHoliday(d('2026-10-31'), off), isNull);
    });

    test('выключенные «Дни рождения» — свой ДР не учитывается', () {
      final settings = HolidaySettings(
        birthday: MonthDay(10, 31),
        disabled: {HolidayKey.birthday},
      );
      expect(moodOn(d('2026-10-30'), settings), Mood.halloween);
    });

    test('нет кандидатов — сезон', () {
      expect(moodOn(d('2026-07-15'), allOn), Mood.summer);
      expect(moodOn(d('2026-10-01'), allOn), Mood.autumn);
      expect(moodOn(d('2026-04-15'), allOn), Mood.spring);
    });

    test('день рождения 29 февраля', () {
      final settings = HolidaySettings(birthday: MonthDay(2, 29));
      expect(moodOn(d('2026-02-28'), settings), Mood.birthday);
      expect(moodOn(d('2026-02-22'), settings), Mood.birthday);
      expect(moodOn(d('2026-03-01'), settings), Mood.spring);
      final leap = activeHoliday(d('2028-02-28'), settings)!;
      expect(leap.key, HolidayKey.birthday);
      expect(leap.stage, HolidayStage.before);
      expect(leap.daysUntilDay, 1);
    });

    test('activeHoliday отдаёт фазу для плашки', () {
      final phase = activeHoliday(d('2026-12-25'), allOn)!;
      expect(phase.key, HolidayKey.newyear);
      expect(phase.stage, HolidayStage.before);
      expect(phase.daysUntilDay, 7);
      expect(phase.occurrence.id, 'newyear:2027');
    });
  });

  group('HolidaySettings', () {
    test('равенство без учёта порядка выключенных', () {
      final a = HolidaySettings(
        disabled: {HolidayKey.women, HolidayKey.labour},
        birthday: MonthDay(1, 2),
      );
      final b = HolidaySettings(
        disabled: {HolidayKey.labour, HolidayKey.women},
        birthday: MonthDay(1, 2),
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == const HolidaySettings(), isFalse);
    });

    test('текст для лога без даты рождения', () {
      final text = HolidaySettings(birthday: MonthDay(1, 2)).toString();
      expect(text, contains('birthday: set'));
      expect(text, isNot(contains('02')));
    });
  });
}
