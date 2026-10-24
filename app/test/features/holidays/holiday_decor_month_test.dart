import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milionchik/app.dart';
import 'package:milionchik/features/holidays/mood_controller.dart';
import 'package:milionchik/ui/components/day_cell.dart';
import 'package:milionchik/ui/components/month_card.dart';
import 'package:milionchik/ui/decor/decor_painter.dart';
import 'package:milionchik/ui/theme/mood_colors.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';
import '../auth/session_expired_fixture.dart' show testUnmounting;
import 'holiday_banner_fixture.dart';
import 'holiday_decor_fixture.dart';

MonthCard _card(WidgetTester tester) =>
    tester.widget<MonthCard>(find.byType(MonthCard));

DecorPainter _decor(WidgetTester tester) => tester
    .widgetList<CustomPaint>(
      find.descendant(
        of: find.byType(MonthCard),
        matching: find.byType(CustomPaint),
      ),
    )
    .map((p) => p.painter)
    .whereType<DecorPainter>()
    .single;

Mood _cellMood(WidgetTester tester) =>
    MoodColors.of(tester.element(find.byType(DayCell).first)).mood;

Mood _season(YearMonth month) => Mood.ofSeason(seasonOf(month.month));

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  for (final example in figmaHolidayExamples) {
    final holiday = holidayMood(example.key);
    final today = LocalDate.fromDateTime(example.now);
    final current = YearMonth.of(today);
    final previous = current.previous;
    final layer = example.key == HolidayKey.halloween
        ? 'halloween-cute'
        : example.key.name;

    testUnmounting('${example.key.name}, сегодня $today: карточка $current - '
        'праздничный декор $layer и цвета, $previous - сезон '
        '${_season(previous).name}, будущий ${current.next} - '
        '${_season(current.next).name}', (tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(360, 800);
      addTearDown(tester.view.reset);
      final db = openTestDatabase();
      await tester.runAsync(() => seedFigmaHolidayCard(db, example));
      await tester.pumpWidget(
        ProviderScope(
          overrides: holidayOverrides(db, example.key, () => example.now),
          child: const MilionchikApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(_card(tester).month, current);
      expect(_card(tester).mood, holiday);
      expect(_decor(tester).mood, holiday);
      expect(_decor(tester).brightness, Brightness.light);
      expect(_decor(tester).layer.key, layer);
      expect(_cellMood(tester), holiday);
      expect(
        Money.sum(_card(tester).dayTotals.values),
        Money.rubles(
          figmaHolidayCards[example.key]!.rubles.values.reduce((a, b) => a + b),
        ),
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(MilionchikApp)),
      );
      final moodToday = container.read(moodControllerProvider);
      expect(moodToday.mood, holiday);
      expect(monthCardMood(current, moodToday), holiday);
      expect(monthCardMood(current.next, moodToday), _season(current.next));
      expect(_card(tester).onNext, isNull);

      await tester.tap(find.bySemanticsLabel('Предыдущий месяц'));
      await tester.pumpAndSettle();

      expect(_card(tester).month, previous);
      expect(_card(tester).mood, _season(previous));
      expect(_decor(tester).mood, _season(previous));
      expect(_decor(tester).layer.key, _season(previous).name);
      expect(_cellMood(tester), _season(previous));
      expect(
        MoodColors.of(tester.element(find.byType(MonthCard))).mood,
        holiday,
      );
    });
  }
}
