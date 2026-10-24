import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milionchik/ui/components/holiday_banner.dart';
import 'package:shared/shared.dart';

import '../../features/holidays/holiday_banner_fixture.dart';
import '../../support/app_scope.dart';
import '../../support/golden.dart';

const Set<HolidayKey> _relayout = {
  HolidayKey.defender,
  HolidayKey.maslenitsa,
  HolidayKey.halloween,
  HolidayKey.birthday,
};

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  for (final example in figmaHolidayExamples) {
    for (final brightness in Brightness.values) {
      final variants = [
        (360.0, 1.0),
        if (_relayout.contains(example.key)) ...[
          (320.0, 1.0),
          (360.0, 2.0),
          (320.0, 2.0),
        ],
      ];
      for (final (width, scale) in variants) {
        final name =
            '${example.key.name}_${brightness.name}_${width.toInt()}'
            '${scale == 1 ? '' : '_x${scale.toInt()}'}';
        final figma = brightness == Brightness.light
            ? example.light
            : example.dark;
        testWidgets('главная с плашкой $name (Figma $figma)', (tester) async {
          final db = openTestDatabase();
          await tester.runAsync(() => seedHolidayMonth(db, example.key));
          debugDisableShadows = false;
          await pumpHolidayMonth(
            tester,
            db,
            key: example.key,
            now: example.now,
            brightness: brightness,
            width: width,
            scale: scale,
          );

          expect(find.byType(HolidayBanner), findsOneWidget);
          expect(tester.takeException(), isNull);
          await expectGolden(tester, 'holiday_banner', name);
        });
      }
    }
  }
}
