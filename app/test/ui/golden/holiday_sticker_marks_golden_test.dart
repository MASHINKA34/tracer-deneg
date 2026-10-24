import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milionchik/ui/components/bottom_nav.dart';
import 'package:milionchik/ui/components/month_card.dart';
import 'package:shared/shared.dart';

import '../../support/golden.dart';

final YearMonth _november = YearMonth(2026, 11);

final Map<int, Money> _novemberTotals = {
  for (final MapEntry(key: day, value: rubles) in const {
    1: 1480,
    2: 1660,
    5: 400,
    6: 150,
    7: 160,
    8: 500,
    9: 120,
    10: 1610,
    11: 990,
  }.entries)
    day: Money.rubles(rubles),
};

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  for (final brightness in Brightness.values) {
    for (final width in const [360.0, 320.0]) {
      for (final scale in const [1.0, 2.0]) {
        final suffix =
            '${brightness.name}_${width.toInt()}'
            '${scale == 1 ? '' : '_x${scale.toInt()}'}';

        testWidgets('меню с наклейкой 🎃 $suffix (Figma 34:10095 / '
            '34:10682)', (tester) async {
          await pumpGolden(
            tester,
            brightness: brightness,
            mood: Mood.halloween,
            width: width,
            textScale: scale,
            padding: const EdgeInsets.only(top: 40),
            child: AppBottomNav(
              active: AppNavTab.month,
              onTabSelected: (_) {},
              onAdd: () {},
              fabSticker: '🎃',
            ),
          );
          await expectGolden(
            tester,
            'holiday_sticker_marks',
            'nav_sticker_$suffix',
          );
        });

        testWidgets('карточка ноября с отметкой своего дня рождения 14.11 '
            '$suffix (Figma 33:9789 / 33:10152)', (tester) async {
          await pumpGolden(
            tester,
            brightness: brightness,
            mood: Mood.birthday,
            width: width,
            textScale: scale,
            padding: const EdgeInsets.all(12),
            child: MonthCard(
              month: _november,
              today: LocalDate(2026, 11, 11),
              dayTotals: _novemberTotals,
              mood: Mood.birthday,
              holidayMarks: monthMarkEmojis(
                _november,
                birthday: MonthDay(11, 14),
              ),
              onMonthTap: () {},
              onPrevious: () {},
              onDayTap: (_) {},
            ),
          );
          await expectGolden(
            tester,
            'holiday_sticker_marks',
            'card_birthday_mark_$suffix',
          );
        });
      }
    }
  }
}
