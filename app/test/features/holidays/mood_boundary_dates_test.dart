import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/features/holidays/mood_controller.dart';
import 'package:shared/shared.dart';

LocalDate d(String text) => LocalDate.parse(text);

typedef Boundary = ({
  HolidayKey key,
  String before,
  String start,
  String day,
  String end,
  String after,
  Mood beforeMood,
  Mood afterMood,
});

void main() {
  const allOn = HolidaySettings();

  MoodToday at(String date, [HolidaySettings settings = allOn]) =>
      moodTodayFor(d(date), settings);

  void expectHoliday(
    MoodToday today,
    HolidayKey key,
    HolidayStage stage, {
    int? daysUntilDay,
  }) {
    final reason = '${today.date}';
    expect(today.mood, Mood.ofHoliday(key), reason: reason);
    expect(
      today.reason,
      key == HolidayKey.birthday ? MoodReason.birthday : MoodReason.holiday,
      reason: reason,
    );
    expect(today.holiday?.key, key, reason: reason);
    expect(today.holiday?.stage, stage, reason: reason);
    if (daysUntilDay != null) {
      expect(today.holiday?.daysUntilDay, daysUntilDay, reason: reason);
    }
  }

  void expectSeason(MoodToday today, Mood season) {
    expect(today.mood, season, reason: '${today.date}');
    expect(today.reason, MoodReason.season, reason: '${today.date}');
    expect(today.holiday, isNull, reason: '${today.date}');
  }

  group('границы периода каждого праздника: день до, первый день, «день», '
      'последний день, день после', () {
    final List<Boundary> table = [
      (
        key: HolidayKey.newyear,
        before: '2026-12-19',
        start: '2026-12-20',
        day: '2027-01-01',
        end: '2027-01-08',
        after: '2027-01-09',
        beforeMood: Mood.winter,
        afterMood: Mood.winter,
      ),
      (
        key: HolidayKey.valentine,
        before: '2026-02-07',
        start: '2026-02-08',
        day: '2026-02-14',
        end: '2026-02-14',
        after: '2026-02-15',
        beforeMood: Mood.winter,
        afterMood: Mood.winter,
      ),
      (
        key: HolidayKey.defender,
        before: '2027-02-16',
        start: '2027-02-17',
        day: '2027-02-23',
        end: '2027-02-23',
        after: '2027-02-24',
        beforeMood: Mood.winter,
        afterMood: Mood.winter,
      ),
      (
        key: HolidayKey.maslenitsa,
        before: '2026-02-15',
        start: '2026-02-16',
        day: '2026-02-22',
        end: '2026-02-22',
        after: '2026-02-23',
        beforeMood: Mood.winter,
        afterMood: Mood.defender,
      ),
      (
        key: HolidayKey.women,
        before: '2026-03-01',
        start: '2026-03-02',
        day: '2026-03-08',
        end: '2026-03-08',
        after: '2026-03-09',
        beforeMood: Mood.spring,
        afterMood: Mood.spring,
      ),
      (
        key: HolidayKey.labour,
        before: '2026-04-30',
        start: '2026-05-01',
        day: '2026-05-01',
        end: '2026-05-07',
        after: '2026-05-08',
        beforeMood: Mood.spring,
        afterMood: Mood.victory,
      ),
      (
        key: HolidayKey.victory,
        before: '2026-05-07',
        start: '2026-05-08',
        day: '2026-05-09',
        end: '2026-05-09',
        after: '2026-05-10',
        beforeMood: Mood.labour,
        afterMood: Mood.spring,
      ),
      (
        key: HolidayKey.children,
        before: '2026-05-25',
        start: '2026-05-26',
        day: '2026-06-01',
        end: '2026-06-01',
        after: '2026-06-02',
        beforeMood: Mood.spring,
        afterMood: Mood.summer,
      ),
      (
        key: HolidayKey.knowledge,
        before: '2026-08-25',
        start: '2026-08-26',
        day: '2026-09-01',
        end: '2026-09-01',
        after: '2026-09-02',
        beforeMood: Mood.summer,
        afterMood: Mood.autumn,
      ),
      (
        key: HolidayKey.halloween,
        before: '2026-10-24',
        start: '2026-10-25',
        day: '2026-10-31',
        end: '2026-10-31',
        after: '2026-11-01',
        beforeMood: Mood.autumn,
        afterMood: Mood.autumn,
      ),
    ];

    for (final b in table) {
      test('${b.key.name}: ${b.before} → ${b.start} … ${b.day} … ${b.end} '
          '→ ${b.after}', () {
        final before = at(b.before);
        expect(before.mood, b.beforeMood, reason: b.before);
        expect(before.holiday?.key, isNot(b.key), reason: b.before);

        final start = at(b.start);
        final startStage = b.start == b.day
            ? HolidayStage.day
            : HolidayStage.before;
        expectHoliday(
          start,
          b.key,
          startStage,
          daysUntilDay: d(b.start).daysUntil(d(b.day)),
        );

        expectHoliday(at(b.day), b.key, HolidayStage.day, daysUntilDay: 0);

        final endStage = b.end == b.day ? HolidayStage.day : HolidayStage.after;
        expectHoliday(at(b.end), b.key, endStage);

        final after = at(b.after);
        expect(after.mood, b.afterMood, reason: b.after);
        expect(after.holiday?.key, isNot(b.key), reason: b.after);
      });
    }

    test('свой день рождения 15 июля: 6 дней до и сам день, вне - лето', () {
      final settings = HolidaySettings(birthday: MonthDay(7, 15));
      expectSeason(at('2026-07-08', settings), Mood.summer);
      expectHoliday(
        at('2026-07-09', settings),
        HolidayKey.birthday,
        HolidayStage.before,
        daysUntilDay: 6,
      );
      expectHoliday(
        at('2026-07-15', settings),
        HolidayKey.birthday,
        HolidayStage.day,
        daysUntilDay: 0,
      );
      expectSeason(at('2026-07-16', settings), Mood.summer);
    });
  });

  group('приоритеты §7.6.3', () {
    test('Масленица 2026 (16–22.02) и 23 Февраля (17–23.02): с 17 по 22 - '
        'Масленица (ближе «день»), 23-го - 23 Февраля', () {
      expectHoliday(
        at('2026-02-16'),
        HolidayKey.maslenitsa,
        HolidayStage.before,
      );
      for (var day = 17; day <= 21; day++) {
        expectHoliday(
          at('2026-02-$day'),
          HolidayKey.maslenitsa,
          HolidayStage.before,
          daysUntilDay: 22 - day,
        );
      }
      expectHoliday(at('2026-02-22'), HolidayKey.maslenitsa, HolidayStage.day);
      expectHoliday(at('2026-02-23'), HolidayKey.defender, HolidayStage.day);
      expectSeason(at('2026-02-24'), Mood.winter);
    });

    test('день рождения в Хеллоуин: ДР побеждает весь период, кроме дней до '
        'него; выключенные «Дни рождения» - снова Хеллоуин', () {
      final settings = HolidaySettings(birthday: MonthDay(10, 28));
      expectHoliday(
        at('2026-10-25', settings),
        HolidayKey.birthday,
        HolidayStage.before,
        daysUntilDay: 3,
      );
      expectHoliday(
        at('2026-10-28', settings),
        HolidayKey.birthday,
        HolidayStage.day,
      );
      expectHoliday(
        at('2026-10-29', settings),
        HolidayKey.halloween,
        HolidayStage.before,
      );
      expectHoliday(
        at('2026-10-31', settings),
        HolidayKey.halloween,
        HolidayStage.day,
      );

      final onHalloween = HolidaySettings(birthday: MonthDay(10, 31));
      for (var day = 25; day <= 31; day++) {
        expectHoliday(
          at('2026-10-$day', onHalloween),
          HolidayKey.birthday,
          day == 31 ? HolidayStage.day : HolidayStage.before,
        );
      }

      final birthdaysOff = HolidaySettings(
        birthday: MonthDay(10, 31),
        disabled: {HolidayKey.birthday},
      );
      final today = at('2026-10-31', birthdaysOff);
      expectHoliday(today, HolidayKey.halloween, HolidayStage.day);
      expect(today.skipped, [HolidayKey.birthday]);
    });

    test('ДР 1 января важнее Нового года', () {
      final settings = HolidaySettings(birthday: MonthDay(1, 1));
      expectHoliday(
        at('2027-01-01', settings),
        HolidayKey.birthday,
        HolidayStage.day,
      );
      expectHoliday(
        at('2026-12-25', settings),
        HolidayKey.newyear,
        HolidayStage.before,
      );
    });

    test('8 Марта 2027 и Масленица 8–14.03: 8-го - 8 Марта, с 9-го - '
        'Масленица', () {
      expectHoliday(at('2027-03-07'), HolidayKey.women, HolidayStage.before);
      expectHoliday(at('2027-03-08'), HolidayKey.women, HolidayStage.day);
      expectHoliday(
        at('2027-03-09'),
        HolidayKey.maslenitsa,
        HolidayStage.before,
      );
      expectHoliday(at('2027-03-14'), HolidayKey.maslenitsa, HolidayStage.day);
    });

    test('равное расстояние до «дня» - выше в таблице: 2031, 20.02 - '
        '23 Февраля, а не Масленица', () {
      expectHoliday(at('2031-02-20'), HolidayKey.defender, HolidayStage.before);
    });
  });

  group('выключенные праздники', () {
    test('выключен Хеллоуин: 31 октября - осень, в логе skipped', () {
      const settings = HolidaySettings(disabled: {HolidayKey.halloween});
      final today = at('2026-10-31', settings);
      expectSeason(today, Mood.autumn);
      expect(today.skipped, [HolidayKey.halloween]);
    });

    test('выключена Масленица 2026: 18.02 - 23 Февраля, 16.02 - зима', () {
      const settings = HolidaySettings(disabled: {HolidayKey.maslenitsa});
      expectHoliday(
        at('2026-02-18', settings),
        HolidayKey.defender,
        HolidayStage.before,
      );
      final first = at('2026-02-16', settings);
      expectSeason(first, Mood.winter);
      expect(first.skipped, [HolidayKey.maslenitsa]);
    });

    test('праздники выключены целиком: сезон, причина off, ДР тоже не '
        'считается', () {
      final settings = HolidaySettings(
        enabled: false,
        birthday: MonthDay(10, 31),
      );
      final today = at('2026-10-31', settings);
      expect(today.mood, Mood.autumn);
      expect(today.reason, MoodReason.off);
      expect(today.holiday, isNull);
      expect(today.skipped, [HolidayKey.halloween, HolidayKey.birthday]);
      expect(at('2027-01-01', settings).mood, Mood.winter);
      expect(at('2027-01-01', settings).reason, MoodReason.off);
    });

    test('нет праздника - сезон без skipped', () {
      final today = at('2026-07-20');
      expectSeason(today, Mood.summer);
      expect(today.skipped, isEmpty);
    });
  });

  group('переход года', () {
    test('31.12 → 1.01: Новый год «до» за 1 день, потом «день»; ключ '
        'плашки newyear:2027 у обоих', () {
      final eve = at('2026-12-31');
      expectHoliday(
        eve,
        HolidayKey.newyear,
        HolidayStage.before,
        daysUntilDay: 1,
      );
      final day = at('2027-01-01');
      expectHoliday(day, HolidayKey.newyear, HolidayStage.day, daysUntilDay: 0);
      expect(eve.holiday!.occurrence.id, 'newyear:2027');
      expect(day.holiday!.occurrence.id, 'newyear:2027');
    });

    test('20.12.2026 и 8.01.2027 - один и тот же Новый год, 9.01 - зима', () {
      expect(
        at('2026-12-20').holiday!.occurrence,
        at('2027-01-08').holiday!.occurrence,
      );
      expectHoliday(at('2027-01-08'), HolidayKey.newyear, HolidayStage.after);
      expectSeason(at('2027-01-09'), Mood.winter);
    });
  });

  group('високосный год', () {
    test('ДР 29 февраля: в 2027 «день» 28.02, в 2028 - 29.02 (28.02 - «до» '
        'за 1 день), 1.03 - весна', () {
      final settings = HolidaySettings(birthday: MonthDay(2, 29));
      expectHoliday(
        at('2027-02-28', settings),
        HolidayKey.birthday,
        HolidayStage.day,
      );
      expectSeason(at('2027-03-01', settings), Mood.spring);
      expectHoliday(
        at('2028-02-28', settings),
        HolidayKey.birthday,
        HolidayStage.before,
        daysUntilDay: 1,
      );
      expectHoliday(
        at('2028-02-29', settings),
        HolidayKey.birthday,
        HolidayStage.day,
      );
      expectHoliday(
        at('2028-02-23', settings),
        HolidayKey.birthday,
        HolidayStage.before,
        daysUntilDay: 6,
      );
      expectSeason(at('2028-03-01', settings), Mood.spring);
    });

    test('2028 без ДР: 29 февраля - зима (Масленица 21–27.02 кончилась)', () {
      expectHoliday(at('2028-02-27'), HolidayKey.maslenitsa, HolidayStage.day);
      expectSeason(at('2028-02-28'), Mood.winter);
      expectSeason(at('2028-02-29'), Mood.winter);
    });
  });

  group('праздники на стыке месяцев: карточка текущего месяца - праздник, '
      'соседний месяц - его сезон', () {
    void expectCards(
      String today,
      Map<YearMonth, Mood> cards, [
      HolidaySettings settings = allOn,
    ]) {
      final mood = at(today, settings);
      for (final MapEntry(key: month, value: expected) in cards.entries) {
        expect(
          monthCardMood(month, mood),
          expected,
          reason: 'today=$today month=$month',
        );
      }
    }

    test('1 июня (26.05–01.06): 30 мая - карточка мая праздничная, апреля - '
        'весна; 1 июня - июнь праздничный, май - весна', () {
      expectCards('2026-05-30', {
        YearMonth(2026, 5): Mood.children,
        YearMonth(2026, 4): Mood.spring,
      });
      expectCards('2026-06-01', {
        YearMonth(2026, 6): Mood.children,
        YearMonth(2026, 5): Mood.spring,
      });
    });

    test('1 сентября (26.08–01.09): 31 августа - август праздничный, 1 '
        'сентября - сентябрь, август - лето', () {
      expectCards('2026-08-31', {
        YearMonth(2026, 8): Mood.knowledge,
        YearMonth(2026, 7): Mood.summer,
      });
      expectCards('2026-09-01', {
        YearMonth(2026, 9): Mood.knowledge,
        YearMonth(2026, 8): Mood.summer,
      });
    });

    test('Новый год (20.12–08.01): 3 января - январь праздничный, декабрь - '
        'зима; 31 декабря - декабрь праздничный', () {
      expectCards('2027-01-03', {
        YearMonth(2027, 1): Mood.newyear,
        YearMonth(2026, 12): Mood.winter,
      });
      expectCards('2026-12-31', {
        YearMonth(2026, 12): Mood.newyear,
        YearMonth(2026, 11): Mood.autumn,
      });
    });

    test('Масленица 2033 (28.02–06.03): 28 февраля - февраль, 3 марта - '
        'март, февраль - зима', () {
      expectCards('2033-02-28', {YearMonth(2033, 2): Mood.maslenitsa});
      expectCards('2033-03-03', {
        YearMonth(2033, 3): Mood.maslenitsa,
        YearMonth(2033, 2): Mood.winter,
      });
      expectHoliday(at('2033-03-06'), HolidayKey.maslenitsa, HolidayStage.day);
      expectHoliday(at('2033-03-07'), HolidayKey.women, HolidayStage.before);
    });

    test('без праздника и при выключенных - у текущего месяца его сезон', () {
      expectCards('2026-10-15', {
        YearMonth(2026, 10): Mood.autumn,
        YearMonth(2026, 1): Mood.winter,
        YearMonth(2026, 7): Mood.summer,
      });
      expectCards('2026-10-31', {
        YearMonth(2026, 10): Mood.autumn,
      }, const HolidaySettings(enabled: false));
    });
  });
}
