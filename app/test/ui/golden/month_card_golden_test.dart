import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/ui/catalog/demo_months.dart';
import 'package:milionchik/ui/components/month_card.dart';
import 'package:shared/shared.dart';

import '../../support/golden.dart';

/// Эталоны карточки месяца (00-spec §14): осень, зима, весна, лето, Новый
/// год, Хеллоуин — в светлой и тёмной теме, на экранах 320 / 360 / 412 dp,
/// при шрифте 1.0 и 2.0. Данные — с макетов Figma (`demo_months.dart`).
/// Карточка — с полями 12, как на экране (ширина карточки = экран − 24).
void main() {
  for (final demo in demoMonths) {
    for (final brightness in Brightness.values) {
      for (final width in const [320.0, 360.0, 412.0]) {
        for (final scale in const [1.0, 2.0]) {
          final name =
              '${demo.name}_${brightness.name}_${width.toInt()}'
              '${scale == 1 ? '' : '_x${scale.toInt()}'}';
          testWidgets('month card $name (Figma ${demo.figmaNode})', (
            tester,
          ) async {
            await pumpGolden(
              tester,
              brightness: brightness,
              mood: demo.mood,
              width: width,
              textScale: scale,
              padding: const EdgeInsets.all(12),
              child: MonthCard(
                month: demo.month,
                today: demo.today,
                dayTotals: demo.dayTotals,
                mood: demo.mood,
                holidayMarks: demo.marks,
                onMonthTap: () {},
                onPrevious: () {},
                onNext: canGoToNextMonth(demo.month, demo.today) ? () {} : null,
                onDayTap: (_) {},
              ),
            );
            await expectGolden(tester, 'month_card', name);
          });
        }
      }
    }
  }
}
