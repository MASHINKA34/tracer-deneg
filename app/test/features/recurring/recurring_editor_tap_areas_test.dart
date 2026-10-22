import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milionchik/features/recurring/recurring_day_sheet.dart';

import 'recurring_editor_harness.dart';

void _expectNoOverlap(List<Rect> rects) {
  for (var i = 0; i < rects.length; i++) {
    for (var j = i + 1; j < rects.length; j++) {
      final overlap = rects[i].intersect(rects[j]);
      expect(
        overlap.width <= 0.01 || overlap.height <= 0.01,
        isTrue,
        reason: '$i and $j overlap: ${rects[i]} ${rects[j]}',
      );
    }
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  for (final (width, scale) in const [(360.0, 1.0), (320.0, 2.0)]) {
    testWidgets('$width dp, шрифт $scale: строки «Категория» и «День '
        'списания» и 31 ячейка шторки дня — не меньше 48 × 48 без наложений, '
        'ошибок раскладки нет', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final h = await RecurringEditorHarness.start(
        tester,
        size: Size(width, 640),
      );
      await h.openRule(gymTitle);
      expect(tester.takeException(), isNull);

      final rows = [
        tester.getRect(h.row('Категория')),
        tester.getRect(h.row('День списания')),
      ];
      for (final rect in rows) {
        expect(rect.height, greaterThanOrEqualTo(48), reason: '$rect');
      }
      _expectNoOverlap(rows);

      await h.openDaySheet();
      expect(tester.takeException(), isNull);
      final cells = [
        for (var day = 1; day <= recurringDayCount; day++)
          tester.getRect(h.dayCell(day)),
      ];
      for (final rect in cells) {
        expect(rect.width, greaterThanOrEqualTo(48), reason: '$rect');
        expect(rect.height, greaterThanOrEqualTo(48), reason: '$rect');
      }
      _expectNoOverlap(cells);
      expect(tester.getSemantics(h.dayCell(12)).label, '12-е число, выбран');
      expect(tester.getSemantics(h.dayCell(13)).label, '13-е число');
    });
  }

  test(
    'колонок в сетке дней столько, сколько влезает по 48 dp, не больше 7',
    () {
      expect(recurringDayColumns(328), 6);
      expect(recurringDayColumns(288), 6);
      expect(recurringDayColumns(336), 7);
      expect(recurringDayColumns(448), 7);
      expect(recurringDayColumns(40), 1);
    },
  );
}
