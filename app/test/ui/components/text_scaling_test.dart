import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/ui/components/day_cell.dart';
import 'package:milionchik/ui/components/fitting_text.dart';
import 'package:milionchik/ui/theme/app_text.dart';
import 'package:milionchik/ui/theme/app_theme.dart';
import 'package:shared/shared.dart' show Mood;

import '../../support/test_fonts.dart';

Widget _host(Widget child, {double scale = 1, double width = 100}) =>
    MaterialApp(
      theme: AppTheme.build(Brightness.light, Mood.autumn),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Material(
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    );

double _fontSize(WidgetTester tester, String text) {
  final widget = tester.widget<Text>(find.text(text));
  return widget.textScaler == TextScaler.noScaling
      ? widget.style!.fontSize!
      : MediaQuery.textScalerOf(tester.element(find.text(text)))
            .scale(widget.style!.fontSize!);
}

void main() {
  setUpAll(loadTestFonts);

  group('FittingText: переносы только по словам', () {
    testWidgets('слово помещается — кегль без изменений', (tester) async {
      await tester.pumpWidget(
        _host(FittingText('Кнопка', style: AppText.labelM)),
      );
      expect(_fontSize(tester, 'Кнопка'), 14);
    });

    testWidgets(
      'слово не помещается при шрифте 2.0 — кегль уменьшен, слово целиком',
      (tester) async {
        await tester.pumpWidget(
          _host(
            FittingText('Синхронизировать', style: AppText.labelL),
            scale: 2,
            width: 120,
          ),
        );
        final size = _fontSize(tester, 'Синхронизировать');
        expect(size, lessThan(32));
        // Слово в одну строку: высота — одна строка уменьшенного кегля.
        final box = tester.getSize(find.text('Синхронизировать'));
        expect(box.width, lessThanOrEqualTo(120));
        expect(box.height, lessThan(size * 2));
      },
    );
  });

  group('DayCell при крупном шрифте (00-spec §3)', () {
    Widget cell(double scale) => _host(
      SizedBox(
        height: DayCell.heightFor(TextScaler.linear(scale)),
        child: const DayCell(
          type: DayCellType.medium,
          day: 12,
          amount: '1 280',
        ),
      ),
      scale: scale,
      width: 39,
    );

    testWidgets('шрифт 1.0 — сумма 10 sp видна', (tester) async {
      await tester.pumpWidget(cell(1));
      expect(find.text('1 280'), findsOneWidget);
      expect(_fontSize(tester, '1 280'), 10);
    });

    testWidgets('шрифт 1.3 — сумма уменьшена, но не меньше 8 sp × 1.3', (
      tester,
    ) async {
      await tester.pumpWidget(cell(1.3));
      expect(find.text('1 280'), findsOneWidget);
      final size = _fontSize(tester, '1 280');
      expect(size, lessThanOrEqualTo(13));
      expect(size, greaterThanOrEqualTo(8 * 1.3));
    });

    testWidgets('шрифт 2.0 — сумма не помещается и скрыта, число дня видно', (
      tester,
    ) async {
      await tester.pumpWidget(cell(2));
      expect(find.text('1 280'), findsNothing);
      expect(find.text('12'), findsOneWidget);
    });

    test('высота: 46 при 1.0, растёт, когда не помещается число дня', () {
      expect(DayCell.heightFor(TextScaler.noScaling), 46);
      expect(DayCell.heightFor(const TextScaler.linear(2)), 46);
      expect(DayCell.heightFor(const TextScaler.linear(3)), greaterThan(46));
    });
  });
}
