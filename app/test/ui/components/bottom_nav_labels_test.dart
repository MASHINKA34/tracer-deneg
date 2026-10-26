import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/ui/components/bottom_nav.dart';

import '../../support/golden.dart';

const List<String> _labels = ['Месяц', 'Статистика', 'Регулярные', 'Профиль'];

Future<void> _pumpNav(
  WidgetTester tester, {
  required double width,
  required double scale,
  AppNavTab active = AppNavTab.month,
}) async {
  await pumpGolden(
    tester,
    brightness: Brightness.light,
    width: width,
    textScale: scale,
    padding: const EdgeInsets.only(top: 40),
    child: AppBottomNav(active: active, onTabSelected: (_) {}, onAdd: () {}),
  );
  debugDisableShadows = true;
}

double _fontSize(WidgetTester tester, String label) =>
    tester.widget<Text>(find.text(label)).style!.fontSize!;

double _factor(WidgetTester tester, String label, {required bool active}) =>
    _fontSize(tester, label) / (active ? 12 : 11);

Rect _rect(WidgetTester tester, String label) =>
    tester.getRect(find.text(label));

void main() {
  for (final (width, scale) in const [
    (320.0, 2.0),
    (320.0, 1.3),
    (320.0, 1.0),
    (360.0, 2.0),
  ]) {
    testWidgets('$width dp, шрифт $scale: у всех подписей один масштаб, '
        'между соседними не меньше 4 dp, все в пределах экрана', (
      tester,
    ) async {
      await _pumpNav(tester, width: width, scale: scale);

      final month = _factor(tester, 'Месяц', active: true);
      for (final label in _labels.skip(1)) {
        expect(
          _factor(tester, label, active: false),
          moreOrLessEquals(month, epsilon: 1e-9),
          reason: label,
        );
      }
      expect(month, lessThan(scale));
      expect(
        month,
        moreOrLessEquals(
          scale *
              AppBottomNav.labelScale(
                width: width,
                textScaler: TextScaler.linear(scale),
                labels: _labels,
              ),
          epsilon: 1e-9,
        ),
      );
      expect(
        _rect(tester, 'Статистика').left - _rect(tester, 'Месяц').right,
        greaterThanOrEqualTo(AppBottomNav.labelGap - 0.01),
      );
      expect(
        _rect(tester, 'Профиль').left - _rect(tester, 'Регулярные').right,
        greaterThanOrEqualTo(AppBottomNav.labelGap - 0.01),
      );
      for (final label in _labels) {
        final rect = _rect(tester, label);
        expect(rect.left, greaterThanOrEqualTo(0), reason: label);
        expect(rect.right, lessThanOrEqualTo(width), reason: label);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('360 dp, шрифт 1.0: подписи как в Figma — активная 12, '
      'остальные 11, без уменьшения', (tester) async {
    await _pumpNav(tester, width: 360, scale: 1);

    expect(_fontSize(tester, 'Месяц'), 12);
    for (final label in _labels.skip(1)) {
      expect(_fontSize(tester, label), 11, reason: label);
    }
  });

  testWidgets('масштаб подписей не меняется при переключении вкладки', (
    tester,
  ) async {
    await _pumpNav(tester, width: 320, scale: 2);
    final onMonth = _factor(tester, 'Месяц', active: true);

    await _pumpNav(tester, width: 320, scale: 2, active: AppNavTab.recurring);

    expect(
      _factor(tester, 'Регулярные', active: true),
      moreOrLessEquals(onMonth, epsilon: 1e-9),
    );
    expect(
      _factor(tester, 'Месяц', active: false),
      moreOrLessEquals(onMonth, epsilon: 1e-9),
    );
  });

  testWidgets(
    'решение о масштабе подписей пишется в debug-лог nav.labels один раз '
    'на изменение',
    (tester) async {
      final previous = Logger.root.level;
      Logger.root.level = Level.ALL;
      final records = <LogRecord>[];
      final sub = Logger.root.onRecord.listen(records.add);
      addTearDown(() async {
        await sub.cancel();
        Logger.root.level = previous;
      });
      Iterable<String> navLines() => records
          .where((r) => r.loggerName == 'nav.labels' && r.level == Level.FINE)
          .map((r) => r.message);

      await _pumpNav(tester, width: 360, scale: 1);
      await tester.pump();
      expect(navLines(), [
        'nav labels at full size: widest «Регулярные» 71.0dp, tab 71.0dp, '
            'gap 4.0dp, textScale=1.00 width=360dp',
      ]);

      await _pumpNav(tester, width: 320, scale: 2);
      expect(
        navLines().last,
        'nav labels scaled together x0.430 to fit: widest «Регулярные» '
        '142.0dp, tab 61.0dp, gap 4.0dp, textScale=2.00 width=320dp',
      );
      expect(navLines(), hasLength(2));
    },
  );
}
