import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared/shared.dart';

import '../../data/api/fake_api_adapter.dart';
import '../auth/session_expired_fixture.dart' show testUnmounting;
import 'holiday_sticker_marks_fixture.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testUnmounting('выключены Хеллоуин и дни рождения или все праздники - '
      'отметки 🎃 31.10 и 🎂 своего дня рождения остаются, наклейки нет', (
    tester,
  ) async {
    for (final settings in [
      HolidaySettings(
        disabled: const {HolidayKey.halloween, HolidayKey.birthday},
        birthday: MonthDay(10, 20),
      ),
      HolidaySettings(enabled: false, birthday: MonthDay(10, 20)),
    ]) {
      await startHolidayApp(
        tester,
        now: () => DateTime(2026, 10, 28, 12),
        settings: settings,
      );
      expect(shownMonth(tester), YearMonth(2026, 10));
      expect(dayMarks(tester), {20: '🎂', 31: '🎃'}, reason: '$settings');
      expect(fabStickerOf(tester), isNull, reason: '$settings');
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testUnmounting('свой день рождения 14.11 - 🎂 в ноябре; в октябре его нет, '
      '🎃 на месте; без даты рождения 🎂 нет', (tester) async {
    final db = await startHolidayApp(
      tester,
      now: () => DateTime(2026, 11, 11, 12),
      settings: HolidaySettings(birthday: MonthDay(11, 14)),
    );
    expect(shownMonth(tester), YearMonth(2026, 11));
    expect(dayMarks(tester), {14: '🎂'});

    await tester.tap(find.bySemanticsLabel('Предыдущий месяц'));
    await tester.pumpAndSettle();
    expect(shownMonth(tester), YearMonth(2026, 10));
    expect(dayMarks(tester), {31: '🎃'});

    await tester.pumpWidget(const SizedBox.shrink());
    await startHolidayApp(
      tester,
      now: () => DateTime(2026, 11, 11, 12),
      database: db,
    );
    expect(shownMonth(tester), YearMonth(2026, 11));
    expect(dayMarks(tester), isEmpty);
  });

  testUnmounting('день рождения в день праздника (31.10) - в ячейке 🎂 '
      'вместо 🎃', (tester) async {
    await startHolidayApp(
      tester,
      now: () => DateTime(2026, 10, 19, 12),
      settings: HolidaySettings(birthday: MonthDay(10, 31)),
    );
    expect(dayMarks(tester), {31: '🎂'});
  });

  testUnmounting('29 февраля: в невисокосном 2027 - 🎂 28 февраля, в 2028 - '
      '29 февраля, рядом отметки праздников', (tester) async {
    final settings = HolidaySettings(birthday: MonthDay(2, 29));
    final db = await startHolidayApp(
      tester,
      now: () => DateTime(2027, 2, 10, 12),
      settings: settings,
    );
    expect(shownMonth(tester), YearMonth(2027, 2));
    expect(dayMarks(tester), {14: '💌', 23: '⭐', 28: '🎂'});

    await tester.pumpWidget(const SizedBox.shrink());
    await startHolidayApp(
      tester,
      now: () => DateTime(2028, 2, 10, 12),
      settings: settings,
      database: db,
    );
    expect(shownMonth(tester), YearMonth(2028, 2));
    expect(dayMarks(tester), {14: '💌', 23: '⭐', 27: '🥞', 29: '🎂'});
  });

  testUnmounting('дату рождения сменили в настройках аккаунта при открытом '
      'приложении - отметка переезжает сразу, очистили - пропадает; даты '
      'рождения в логах нет', (tester) async {
    final logs = LogCapture();
    addTearDown(logs.dispose);
    await startHolidayApp(
      tester,
      now: () => DateTime(2026, 11, 11, 12),
      signedIn: true,
      settings: HolidaySettings(birthday: MonthDay(11, 14)),
    );
    expect(dayMarks(tester), {14: '🎂'});

    await applyAccountSettings(
      tester,
      HolidaySettings(birthday: MonthDay(11, 20)),
    );
    expect(dayMarks(tester), {20: '🎂'});

    await applyAccountSettings(tester, const HolidaySettings());
    expect(dayMarks(tester), isEmpty);

    final text = logs.text;
    expect(text, contains('holiday settings changed from test'));
    for (final secret in ['14.11', '20.11', '11-14', '11-20', 'MonthDay(']) {
      expect(text, isNot(contains(secret)), reason: secret);
    }
  });
}
