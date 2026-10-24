import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milionchik/ui/components/month_card.dart';
import 'package:milionchik/ui/decor/decor_painter.dart';
import 'package:shared/shared.dart';

import '../../features/auth/session_expired_fixture.dart' show testUnmounting;
import '../../features/holidays/holiday_banner_fixture.dart';
import '../../features/holidays/holiday_decor_fixture.dart';
import '../../support/app_scope.dart';
import '../../support/golden.dart';

Future<ui.Image> _cardOnScreen(WidgetTester tester) {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(goldenKey),
  );
  final layer = boundary.debugLayer! as OffsetLayer;
  return layer.toImage(tester.getRect(find.byType(MonthCard)).inflate(12));
}

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

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  for (final example in figmaHolidayExamples) {
    final figma = figmaHolidayCards[example.key]!;
    for (final brightness in Brightness.values) {
      final node = brightness == Brightness.light
          ? figma.lightCard
          : figma.darkCard;
      final layer = example.key != HolidayKey.halloween
          ? example.key.name
          : brightness == Brightness.light
          ? 'halloween-cute'
          : 'halloween-spooky';
      for (final width in const [360.0, 320.0]) {
        for (final scale in const [1.0, 2.0]) {
          final name =
              '${example.key.name}_${brightness.name}_${width.toInt()}'
              '${scale == 1 ? '' : '_x${scale.toInt()}'}';
          testUnmounting('главная: праздничная карточка $name, слой $layer '
              '(Figma $node)', (tester) async {
            final db = openTestDatabase();
            await tester.runAsync(() => seedFigmaHolidayCard(db, example));
            debugDisableShadows = false;
            try {
              await pumpHolidayMonth(
                tester,
                db,
                key: example.key,
                now: example.now,
                brightness: brightness,
                width: width,
                scale: scale,
                height: 1600,
              );

              final card = tester.widget<MonthCard>(find.byType(MonthCard));
              expect(
                card.month,
                YearMonth.of(LocalDate.fromDateTime(example.now)),
              );
              expect(card.mood, holidayMood(example.key));
              expect(_decor(tester).layer.key, layer);
              expect(tester.takeException(), isNull);

              final image = (await tester.runAsync(
                () => _cardOnScreen(tester),
              ))!;
              try {
                await expectLater(
                  image,
                  matchesGoldenFile(goldenName('holiday_decor', name)),
                );
              } finally {
                image.dispose();
              }
            } finally {
              await tester.pumpWidget(const SizedBox.shrink());
              debugDisableShadows = true;
            }
          });
        }
      }
    }
  }
}
