import 'package:shared/shared.dart';
import 'package:test/test.dart';

LocalDate d(String text) => LocalDate.parse(text);

void main() {
  group('seasonOf', () {
    test('декабрь–февраль зима, март–май весна, июнь–август лето, '
        'сентябрь–ноябрь осень', () {
      expect(
        [for (var m = 1; m <= 12; m++) seasonOf(m)],
        [
          Season.winter,
          Season.winter,
          Season.spring,
          Season.spring,
          Season.spring,
          Season.summer,
          Season.summer,
          Season.summer,
          Season.autumn,
          Season.autumn,
          Season.autumn,
          Season.winter,
        ],
      );
      expect(() => seasonOf(0), throwsRangeError);
    });
  });

  group('HolidayKey', () {
    test('11 праздников в порядке таблицы, ключи и эмодзи', () {
      expect(
        [for (final k in HolidayKey.values) '${k.key} ${k.emoji}'],
        [
          'newyear 🎄',
          'valentine 💌',
          'defender ⭐',
          'maslenitsa 🥞',
          'women 🌷',
          'labour 🔨',
          'victory 🎆',
          'children 🎈',
          'knowledge 📚',
          'halloween 🎃',
          'birthday 🎂',
        ],
      );
      expect(HolidayKey.fromKey('halloween'), HolidayKey.halloween);
      expect(HolidayKey.fromKey('xmas'), isNull);
    });
  });

  group('holidayOccurrence: периоды и «день»', () {
    final expected = <HolidayKey, (String, String, String)>{
      HolidayKey.newyear: ('2025-12-20', '2026-01-01', '2026-01-08'),
      HolidayKey.valentine: ('2026-02-08', '2026-02-14', '2026-02-14'),
      HolidayKey.defender: ('2026-02-17', '2026-02-23', '2026-02-23'),
      HolidayKey.maslenitsa: ('2026-02-16', '2026-02-22', '2026-02-22'),
      HolidayKey.women: ('2026-03-02', '2026-03-08', '2026-03-08'),
      HolidayKey.labour: ('2026-05-01', '2026-05-01', '2026-05-07'),
      HolidayKey.victory: ('2026-05-08', '2026-05-09', '2026-05-09'),
      HolidayKey.children: ('2026-05-26', '2026-06-01', '2026-06-01'),
      HolidayKey.knowledge: ('2026-08-26', '2026-09-01', '2026-09-01'),
      HolidayKey.halloween: ('2026-10-25', '2026-10-31', '2026-10-31'),
    };
    expected.forEach((key, dates) {
      final (start, day, end) = dates;
      test('${key.name} 2026: $start … $end, день $day', () {
        final o = holidayOccurrence(key, 2026);
        expect(o.start, d(start));
        expect(o.day, d(day));
        expect(o.end, d(end));
      });
    });

    test('день рождения: 6 дней до + сам день', () {
      final o = holidayOccurrence(
        HolidayKey.birthday,
        2026,
        birthday: MonthDay(11, 14),
      );
      expect(o.start, d('2026-11-08'));
      expect(o.day, d('2026-11-14'));
      expect(o.end, d('2026-11-14'));
      expect(
        () => holidayOccurrence(HolidayKey.birthday, 2026),
        throwsArgumentError,
      );
    });

    test('день рождения 29 февраля в невисокосный год — 28 февраля', () {
      final o = holidayOccurrence(
        HolidayKey.birthday,
        2026,
        birthday: MonthDay(2, 29),
      );
      expect(o.day, d('2026-02-28'));
      expect(o.start, d('2026-02-22'));
      final leap = holidayOccurrence(
        HolidayKey.birthday,
        2028,
        birthday: MonthDay(2, 29),
      );
      expect(leap.day, d('2028-02-29'));
    });

    test('ключ «праздник+год» — по году «дня»', () {
      final newYear = holidayOccurrence(HolidayKey.newyear, 2027);
      expect(newYear.id, 'newyear:2027');
      expect(newYear.contains(d('2026-12-20')), isTrue);
      expect(newYear.contains(d('2027-01-08')), isTrue);
      expect(newYear.contains(d('2027-01-09')), isFalse);
      expect(newYear.contains(d('2026-12-19')), isFalse);
      expect(newYear, holidayOccurrence(HolidayKey.newyear, 2027));
      expect(
        newYear.hashCode,
        holidayOccurrence(HolidayKey.newyear, 2027).hashCode,
      );
      expect(newYear.toString(), contains('newyear'));
    });
  });

  group('HolidayPhase: фаза на дату', () {
    test('Новый год: до, в день, после', () {
      final o = holidayOccurrence(HolidayKey.newyear, 2027);
      final before = o.phaseOn(d('2026-12-25'))!;
      expect(before.stage, HolidayStage.before);
      expect(before.daysUntilDay, 7);
      expect(before.key, HolidayKey.newyear);

      expect(o.phaseOn(d('2027-01-01'))!.stage, HolidayStage.day);

      final after = o.phaseOn(d('2027-01-05'))!;
      expect(after.stage, HolidayStage.after);
      expect(after.daysUntilDay, -4);
      expect(after.daysUntilEnd, 3);

      expect(o.phaseOn(d('2027-01-09')), isNull);
    });

    test('Масленица 19.02.2026: «Ещё 3 дня блинов» (макет)', () {
      final phase = holidayOccurrence(
        HolidayKey.maslenitsa,
        2026,
      ).phaseOn(d('2026-02-19'))!;
      expect(phase.stage, HolidayStage.before);
      expect(phase.daysUntilDay, 3);
      expect(phase.occurrence.day, d('2026-02-22'));
    });

    test('Неделя труда: 1 мая — день, 4 мая — «ещё 3 дня» (макет)', () {
      final labour = holidayOccurrence(HolidayKey.labour, 2026);
      expect(labour.phaseOn(d('2026-05-01'))!.stage, HolidayStage.day);
      final phase = labour.phaseOn(d('2026-05-04'))!;
      expect(phase.stage, HolidayStage.after);
      expect(phase.daysUntilEnd, 3);
      expect(labour.phaseOn(d('2026-05-07'))!.daysUntilEnd, 0);
    });

    test('9 мая: 8-го — «Завтра — День Победы»', () {
      final phase = holidayOccurrence(
        HolidayKey.victory,
        2026,
      ).phaseOn(d('2026-05-08'))!;
      expect(phase.stage, HolidayStage.before);
      expect(phase.daysUntilDay, 1);
    });

    test('равенство и текст', () {
      final o = holidayOccurrence(HolidayKey.halloween, 2026);
      expect(o.phaseOn(d('2026-10-28')), o.phaseOn(d('2026-10-28')));
      expect(
        o.phaseOn(d('2026-10-28')).hashCode,
        o.phaseOn(d('2026-10-28')).hashCode,
      );
      expect(
        o.phaseOn(d('2026-10-28')).toString(),
        'HolidayPhase(halloween before on 2026-10-28)',
      );
    });
  });

  group('holidaysOn', () {
    test('праздники на дату без учёта настроек, в порядке таблицы', () {
      expect(holidaysOn(d('2026-02-17')).map((o) => o.key), [
        HolidayKey.defender,
        HolidayKey.maslenitsa,
      ]);
      expect(holidaysOn(d('2026-12-25')).single.id, 'newyear:2027');
      expect(holidaysOn(d('2027-01-05')).single.id, 'newyear:2027');
      expect(holidaysOn(d('2026-07-15')), isEmpty);
    });

    test('день рождения в начале января виден в конце декабря', () {
      final keys = holidaysOn(
        d('2026-12-28'),
        birthday: MonthDay(1, 2),
      ).map((o) => o.id);
      expect(keys, ['newyear:2027', 'birthday:2027']);
    });
  });

  group('monthMarks: отметки в календаре', () {
    test('февраль 2026: 14 💌, 22 🥞, 23 ⭐ (макет)', () {
      expect(monthMarkEmojis(YearMonth(2026, 2)), {
        14: '💌',
        22: '🥞',
        23: '⭐',
      });
    });

    test('март 2027: 8 🌷 и 14 🥞 (макет)', () {
      expect(monthMarkEmojis(YearMonth(2027, 3)), {8: '🌷', 14: '🥞'});
    });

    test('Новый год отмечен 31 декабря и 1 января', () {
      expect(monthMarkEmojis(YearMonth(2026, 12)), {31: '🎄'});
      expect(monthMarkEmojis(YearMonth(2027, 1)), {1: '🎄'});
    });

    test('май, июнь, сентябрь, октябрь', () {
      expect(monthMarkEmojis(YearMonth(2026, 5)), {1: '🔨', 9: '🎆'});
      expect(monthMarkEmojis(YearMonth(2026, 6)), {1: '🎈'});
      expect(monthMarkEmojis(YearMonth(2026, 9)), {1: '📚'});
      expect(monthMarkEmojis(YearMonth(2026, 10)), {31: '🎃'});
      expect(monthMarkEmojis(YearMonth(2026, 7)), isEmpty);
    });

    test('2031: 23 февраля и Прощёное воскресенье — одна отметка ⭐', () {
      expect(monthMarks(YearMonth(2031, 2))[23], [
        HolidayKey.defender,
        HolidayKey.maslenitsa,
      ]);
      expect(monthMarkEmojis(YearMonth(2031, 2))[23], '⭐');
    });

    test('свой день рождения — с наибольшим приоритетом', () {
      final birthday = MonthDay(2, 23);
      expect(monthMarks(YearMonth(2026, 2), birthday: birthday)[23], [
        HolidayKey.birthday,
        HolidayKey.defender,
      ]);
      expect(monthMarkEmojis(YearMonth(2026, 11), birthday: MonthDay(11, 14)), {
        14: '🎂',
      });
    });

    test('день рождения 29 февраля отмечается 28-го в невисокосный год', () {
      expect(monthMarks(YearMonth(2026, 2), birthday: MonthDay(2, 29))[28], [
        HolidayKey.birthday,
      ]);
      expect(monthMarks(YearMonth(2028, 2), birthday: MonthDay(2, 29))[29], [
        HolidayKey.birthday,
      ]);
    });
  });
}
