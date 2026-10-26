import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/ui/components/month_card.dart';
import 'package:milionchik/ui/decor/decor_generator.dart';
import 'package:milionchik/ui/decor/decor_painter.dart';
import 'package:milionchik/ui/icons/app_icon.dart';
import 'package:shared/shared.dart';

import '../../support/golden.dart';
import '../../support/test_fonts.dart';

const List<double> _cardWidths = [296, 336];

Rect _area(YearMonth month, double cardWidth, double scale) => monthTitleArea(
  month: month,
  cardWidth: cardWidth,
  textScaler: TextScaler.linear(scale),
);

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('шрифт 1.0, экраны 320 и 360: верхняя полоса у всех слоёв и '
      'месяцев остаётся, зимние снежинки у названия — как в Figma', (
    tester,
  ) async {
    await loadTestFonts();
    final hidden = <String>[];
    var winterTouches = 0;
    for (final layer in DecorLayer.values) {
      for (final width in _cardWidths) {
        final regions = generateDecor(layer, width: width);
        for (var m = 1; m <= 12; m++) {
          final design = _area(YearMonth(2026, m), width, 1);
          if (decorTopOverlaps(regions, design, beyond: design) > 0) {
            hidden.add('${layer.key} w=$width month=$m');
          }
          if (layer == DecorLayer.winter) {
            winterTouches += decorTopOverlaps(regions, design);
          }
        }
      }
    }
    expect(hidden, isEmpty);
    expect(winterTouches, greaterThan(0));
  });

  testWidgets('шрифт 2.0, экран 320: призрак и тыквы Хеллоуина задевают '
      '«ОКТЯБРЬ» сверх раскладки 1.0 — верхняя полоса убирается', (
    tester,
  ) async {
    await loadTestFonts();
    final october = YearMonth(2026, 10);
    final regions = generateDecor(DecorLayer.halloweenCute, width: 296);

    expect(
      decorTopOverlaps(
        regions,
        _area(october, 296, 2),
        beyond: _area(october, 296, 1),
      ),
      greaterThan(0),
    );
  });

  testWidgets('шрифт 2.0, экран 360: зимние снежинки задевают «ЯНВАРЬ» '
      'сверх раскладки 1.0 — верхняя полоса убирается', (tester) async {
    await loadTestFonts();
    final january = YearMonth(2026, 1);
    final regions = generateDecor(DecorLayer.winter, width: 336);

    expect(
      decorTopOverlaps(
        regions,
        _area(january, 336, 2),
        beyond: _area(january, 336, 1),
      ),
      greaterThan(0),
    );
  });

  for (final (screen, scale) in const [
    (320.0, 1.0),
    (320.0, 2.0),
    (360.0, 1.0),
    (360.0, 1.3),
    (360.0, 2.0),
  ]) {
    testWidgets('$screen dp, шрифт $scale: расчётная область совпадает с '
        'нарисованными названием, «⌄» и годом', (tester) async {
      final month = YearMonth(2026, 10);
      await pumpGolden(
        tester,
        brightness: Brightness.light,
        mood: Mood.autumn,
        width: screen,
        textScale: scale,
        padding: const EdgeInsets.all(12),
        child: MonthCard(
          month: month,
          today: LocalDate(2026, 10, 26),
          dayTotals: const {},
          mood: Mood.autumn,
          onMonthTap: () {},
        ),
      );
      debugDisableShadows = true;

      final card = tester.getRect(find.byType(MonthCard));
      Rect local(Finder f) => tester.getRect(f).shift(-card.topLeft);
      final title = local(find.text('ОКТЯБРЬ'));
      final chevron = local(
        find.byWidgetPredicate(
          (w) => w is AppIcon && w.icon == AppIcons.chevronDown,
        ),
      );
      final year = local(find.text('2026'));
      final drawn = title.expandToInclude(chevron).expandToInclude(year);
      final area = _area(month, card.width, scale).deflate(2);

      expect(area.left, moreOrLessEquals(drawn.left, epsilon: 0.5));
      expect(area.top, moreOrLessEquals(drawn.top, epsilon: 0.5));
      expect(area.right, moreOrLessEquals(drawn.right, epsilon: 0.5));
      expect(area.bottom, moreOrLessEquals(drawn.bottom, epsilon: 0.5));
    });
  }

  testWidgets('решение про верхнюю полосу — в debug-логе decor один раз на '
      'размер и область', (tester) async {
    DecorPainter.clearCache();
    addTearDown(DecorPainter.clearCache);
    final previous = Logger.root.level;
    Logger.root.level = Level.ALL;
    final lines = <String>[];
    final sub = Logger.root.onRecord.listen((r) {
      if (r.loggerName == 'decor' && r.message.startsWith('decor top')) {
        lines.add(r.message);
      }
    });
    addTearDown(() async {
      await sub.cancel();
      Logger.root.level = previous;
    });

    for (final scale in const [2.0, 2.0, 1.0]) {
      await pumpGolden(
        tester,
        brightness: Brightness.light,
        mood: Mood.halloween,
        width: 320,
        textScale: scale,
        padding: const EdgeInsets.all(12),
        child: MonthCard(
          month: YearMonth(2026, 10),
          today: LocalDate(2026, 10, 26),
          dayTotals: const {},
          mood: Mood.halloween,
        ),
      );
      debugDisableShadows = true;
    }

    expect(lines, hasLength(2));
    expect(
      lines.first,
      matches(
        RegExp(
          r'^decor top strip hidden layer=halloween-cute size=296\.0x\d+\.\d: '
          r'\d+ of \d+ top shapes overlap the month title area '
          r'\(-?\d+\.\d,-?\d+\.\d\)-\(-?\d+\.\d,-?\d+\.\d\) beyond its font 1\.0 '
          r'area \(-?\d+\.\d,-?\d+\.\d\)-\(-?\d+\.\d,-?\d+\.\d\) → sides and bottom '
          r'only$',
        ),
      ),
    );
    expect(
      lines.last,
      startsWith('decor top strip kept layer=halloween-cute size=296.0x'),
    );
  });
}
