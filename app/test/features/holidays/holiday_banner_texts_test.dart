import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milionchik/features/holidays/holiday_banner_texts.dart';
import 'package:milionchik/l10n/app_localizations.dart';
import 'package:milionchik/ui/components/holiday_banner.dart';
import 'package:shared/shared.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  final l10n = lookupAppLocalizations(const Locale('ru'));
  final birthday = MonthDay(11, 14);

  HolidayPhase phaseOn(HolidayKey key, String date) {
    final today = LocalDate.parse(date);
    final phase = holidaysOn(
      today,
      birthday: birthday,
    ).where((o) => o.key == key).single.phaseOn(today);
    return phase!;
  }

  HolidayBannerText textOn(
    HolidayKey key,
    String date, {
    Brightness brightness = Brightness.light,
    String? name = 'Аня',
  }) => holidayBannerText(
    l10n,
    phaseOn(key, date),
    brightness: brightness,
    name: name,
  );

  void expectBanner(
    HolidayBannerText text,
    HolidayBannerType type,
    String title,
    String subtitle,
  ) {
    expect(text.type, type, reason: title);
    expect(text.title, title);
    expect(text.subtitle, subtitle);
  }

  const countdown = HolidayBannerType.countdown;
  const greeting = HolidayBannerType.greeting;

  group('тексты 00-spec §7.6.4 по праздникам и стадиям', () {
    final cases = <(HolidayKey, String, HolidayBannerType, String, String)>[
      (
        HolidayKey.newyear,
        '2026-12-29',
        countdown,
        'До Нового года 3 дня',
        'Не забудь записать подарки 🎁',
      ),
      (
        HolidayKey.newyear,
        '2027-01-01',
        greeting,
        'С Новым годом!',
        'Пусть копится легко 🎄',
      ),
      (
        HolidayKey.newyear,
        '2027-01-08',
        greeting,
        'С Новым годом!',
        'Пусть копится легко 🎄',
      ),
      (
        HolidayKey.valentine,
        '2026-02-11',
        countdown,
        'До Дня влюблённых 3 дня',
        'Самое время для открыток',
      ),
      (
        HolidayKey.valentine,
        '2026-02-14',
        greeting,
        'С Днём святого Валентина!',
        'Любви и тёплых трат 💌',
      ),
      (
        HolidayKey.defender,
        '2027-02-17',
        countdown,
        'До 23 Февраля 6 дней',
        'Время выбрать подарки',
      ),
      (
        HolidayKey.defender,
        '2026-02-23',
        greeting,
        'С Днём защитника Отечества!',
        'Хорошего праздника',
      ),
      (
        HolidayKey.maslenitsa,
        '2026-02-19',
        countdown,
        'Масленица! Ещё 3 дня блинов',
        'Прощёное воскресенье — 22 февраля',
      ),
      (
        HolidayKey.maslenitsa,
        '2026-02-22',
        greeting,
        'Прощёное воскресенье',
        'С Масленицей! 🥞',
      ),
      (
        HolidayKey.women,
        '2027-03-05',
        countdown,
        'До 8 Марта 3 дня',
        'Пора подумать о цветах',
      ),
      (
        HolidayKey.women,
        '2027-03-08',
        greeting,
        'С 8 Марта!',
        'Весеннего настроения 🌷',
      ),
      (
        HolidayKey.labour,
        '2026-05-01',
        greeting,
        'С Праздником Весны и Труда!',
        'Неделя труда началась 🔨',
      ),
      (
        HolidayKey.labour,
        '2026-05-04',
        greeting,
        'Неделя труда — ещё 3 дня',
        'С Праздником Весны и Труда!',
      ),
      (
        HolidayKey.victory,
        '2026-05-08',
        countdown,
        'Завтра — День Победы',
        'Помним и гордимся',
      ),
      (
        HolidayKey.victory,
        '2026-05-09',
        greeting,
        'С Днём Победы!',
        'Помним и гордимся',
      ),
      (
        HolidayKey.children,
        '2026-05-27',
        countdown,
        'До Дня защиты детей 5 дней',
        'Скоро лето ☀️',
      ),
      (
        HolidayKey.children,
        '2026-06-01',
        greeting,
        'С Днём защиты детей!',
        'Лето началось ☀️',
      ),
      (
        HolidayKey.knowledge,
        '2026-08-31',
        countdown,
        'До 1 сентября 1 день',
        'Готовимся к учёбе 📚',
      ),
      (
        HolidayKey.knowledge,
        '2026-09-01',
        greeting,
        'С Днём знаний!',
        'Удачного учебного года',
      ),
      (
        HolidayKey.halloween,
        '2026-10-28',
        countdown,
        'До Хеллоуина 3 дня',
        'Запасайся конфетами 🍬',
      ),
      (
        HolidayKey.halloween,
        '2026-10-31',
        greeting,
        'С Хеллоуином!',
        'Сладость или гадость? 🍬',
      ),
      (
        HolidayKey.birthday,
        '2026-11-11',
        countdown,
        'До твоего дня рождения 3 дня',
        'Аня, готовься к поздравлениям',
      ),
      (
        HolidayKey.birthday,
        '2026-11-14',
        greeting,
        'С днём рождения, Аня!',
        'Пусть миллион копится сам 🎂',
      ),
    ];
    for (final (key, date, type, title, subtitle) in cases) {
      test('${key.name} $date: ${type.name} «$title / $subtitle»', () {
        final text = textOn(key, date);
        expectBanner(text, type, title, subtitle);
        expect(text.emoji, key.emoji);
      });
    }

    test('у каждого праздника есть текст и в «день», и до «дня» (кроме '
        'Недели труда - период начинается в «день»)', () {
      final checked = {for (final c in cases) c.$1};
      expect(checked, HolidayKey.values.toSet());
    });
  });

  group('«N дн.» - правильное окончание', () {
    for (final (date, days) in [
      ('2026-12-20', '12 дней'),
      ('2026-12-21', '11 дней'),
      ('2026-12-27', '5 дней'),
      ('2026-12-28', '4 дня'),
      ('2026-12-30', '2 дня'),
      ('2026-12-31', '1 день'),
    ]) {
      test('Новый год $date → $days', () {
        expect(textOn(HolidayKey.newyear, date).title, 'До Нового года $days');
      });
    }

    for (final (date, days) in [
      ('2026-02-16', '6 дней'),
      ('2026-02-20', '2 дня'),
      ('2026-02-21', '1 день'),
    ]) {
      test('Масленица $date → «Ещё $days блинов»', () {
        expect(
          textOn(HolidayKey.maslenitsa, date).title,
          'Масленица! Ещё $days блинов',
        );
      });
    }
  });

  group('Масленица: подпись - дата Прощёного воскресенья этого года', () {
    for (final (date, sunday) in [
      ('2026-02-16', '22 февраля'),
      ('2027-03-09', '14 марта'),
      ('2033-03-01', '6 марта'),
    ]) {
      test('$date → $sunday', () {
        expect(
          textOn(HolidayKey.maslenitsa, date).subtitle,
          'Прощёное воскресенье — $sunday',
        );
      });
    }
  });

  group('Неделя труда: 1 мая - поздравление, 2-7 мая - сколько осталось', () {
    for (final (date, title) in [
      ('2026-05-02', 'Неделя труда — ещё 5 дней'),
      ('2026-05-03', 'Неделя труда — ещё 4 дня'),
      ('2026-05-05', 'Неделя труда — ещё 2 дня'),
      ('2026-05-06', 'Неделя труда — ещё 1 день'),
      ('2026-05-07', 'Неделя труда — последний день'),
    ]) {
      test('$date → «$title»', () {
        expectBanner(
          textOn(HolidayKey.labour, date),
          greeting,
          title,
          'С Праздником Весны и Труда!',
        );
      });
    }
  });

  group('Хеллоуин: подпись зависит от темы', () {
    test('тёмная тема до «дня» - «Ночь всё ближе…»', () {
      expectBanner(
        textOn(HolidayKey.halloween, '2026-10-25', brightness: Brightness.dark),
        countdown,
        'До Хеллоуина 6 дней',
        'Ночь всё ближе… \u{1F578}️',
      );
    });

    test('тёмная тема 31 октября - «Не выключай свет…»', () {
      expectBanner(
        textOn(HolidayKey.halloween, '2026-10-31', brightness: Brightness.dark),
        greeting,
        'С Хеллоуином!',
        'Не выключай свет… \u{1F56F}️',
      );
    });

    test('светлая тема 30 октября - «Запасайся конфетами»', () {
      expectBanner(
        textOn(HolidayKey.halloween, '2026-10-30'),
        countdown,
        'До Хеллоуина 1 день',
        'Запасайся конфетами 🍬',
      );
    });
  });

  group('день рождения без имени на телефоне', () {
    for (final name in [null, '', '  ']) {
      test('имя «$name» - тексты без имени', () {
        expect(
          textOn(HolidayKey.birthday, '2026-11-10', name: name).subtitle,
          'Готовься к поздравлениям',
        );
        expect(
          textOn(HolidayKey.birthday, '2026-11-14', name: name).title,
          'С днём рождения!',
        );
      });
    }
  });
}
