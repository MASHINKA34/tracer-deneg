import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/core/app_frame.dart';
import 'package:milionchik/ui/theme/app_theme.dart';
import 'package:milionchik/ui/tokens/tokens.g.dart';
import 'package:shared/shared.dart' show Mood;

const Key _child = ValueKey('child');

Future<MediaQueryData> _pump(
  WidgetTester tester,
  MediaQueryData outer, {
  Brightness brightness = Brightness.light,
}) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = outer.size;
  addTearDown(tester.view.reset);
  late MediaQueryData inner;
  await tester.pumpWidget(
    MediaQuery(
      data: outer,
      child: Theme(
        data: AppTheme.build(brightness, Mood.autumn),
        child: AppFrame(
          child: Builder(
            key: _child,
            builder: (context) {
              inner = MediaQuery.of(context);
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    ),
  );
  return inner;
}

Color _side(WidgetTester tester) => tester
    .widget<ColoredBox>(
      find
          .descendant(
            of: find.byType(AppFrame),
            matching: find.byType(ColoredBox),
          )
          .first,
    )
    .color;

void main() {
  test('ширина содержимого: до 480 dp — вся, шире — 480', () {
    expect(contentWidthFor(320), 320);
    expect(contentWidthFor(412), 412);
    expect(contentWidthFor(480), 480);
    expect(contentWidthFor(481), 480);
    expect(contentWidthFor(800), 480);
    expect(contentWidthFor(1280), 480);
  });

  test('левый край колонки: по центру безопасной области, если колонка в ней '
      'помещается, иначе по центру окна', () {
    expect(contentLeftFor(360, EdgeInsets.zero), 0);
    expect(contentLeftFor(360, const EdgeInsets.only(left: 24)), 0);
    expect(contentLeftFor(800, EdgeInsets.zero), 160);
    expect(contentLeftFor(1280, EdgeInsets.zero), 400);
    expect(contentLeftFor(1280, const EdgeInsets.only(left: 40)), 420);
    expect(contentLeftFor(1280, const EdgeInsets.only(right: 48)), 376);
    expect(contentLeftFor(500, const EdgeInsets.only(left: 40)), 10);
  });

  testWidgets('телефон 360×800: содержимое во весь экран, отступы как у '
      'системы', (tester) async {
    const outer = MediaQueryData(
      size: Size(360, 800),
      padding: EdgeInsets.only(top: 32, bottom: 24),
      viewPadding: EdgeInsets.only(top: 32, bottom: 24),
      systemGestureInsets: EdgeInsets.fromLTRB(20, 0, 20, 24),
    );
    final inner = await _pump(tester, outer);

    expect(tester.getRect(find.byKey(_child)), Offset.zero & outer.size);
    expect(inner.size, outer.size);
    expect(inner.padding, outer.padding);
    expect(inner.viewPadding, outer.viewPadding);
    expect(inner.systemGestureInsets, outer.systemGestureInsets);
  });

  testWidgets('планшет 1280×800 с вырезом слева 40 и жестами по краям: колонка '
      '480 по центру безопасной области (420 слева), боковые отступы до неё '
      'не доходят, верх, низ и клавиатура как у системы, сгиб сдвинут в '
      'координаты колонки', (tester) async {
    const outer = MediaQueryData(
      size: Size(1280, 800),
      padding: EdgeInsets.fromLTRB(40, 32, 0, 24),
      viewPadding: EdgeInsets.fromLTRB(40, 32, 0, 24),
      viewInsets: EdgeInsets.only(bottom: 300),
      systemGestureInsets: EdgeInsets.fromLTRB(20, 0, 20, 24),
      displayFeatures: [
        DisplayFeature(
          bounds: Rect.fromLTRB(630, 0, 650, 800),
          type: DisplayFeatureType.hinge,
          state: DisplayFeatureState.postureFlat,
        ),
      ],
    );
    final inner = await _pump(tester, outer);

    expect(
      tester.getRect(find.byKey(_child)),
      const Rect.fromLTWH(420, 0, 480, 800),
    );
    expect(inner.size, const Size(480, 800));
    expect(inner.padding, const EdgeInsets.fromLTRB(0, 32, 0, 24));
    expect(inner.viewPadding, const EdgeInsets.fromLTRB(0, 32, 0, 24));
    expect(inner.viewInsets, const EdgeInsets.only(bottom: 300));
    expect(inner.systemGestureInsets, const EdgeInsets.only(bottom: 24));
    expect(
      inner.displayFeatures.single.bounds,
      const Rect.fromLTRB(210, 0, 230, 800),
    );
    expect(inner.displayFeatures.single.type, DisplayFeatureType.hinge);
    expect(_side(tester), neutralLight.bgApp);
  });

  testWidgets('окно 500 dp с вырезом слева 40 и справа 16: колонка со сдвигом '
      '10, внутри остаются 30 слева и 6 справа', (tester) async {
    const outer = MediaQueryData(
      size: Size(500, 900),
      padding: EdgeInsets.fromLTRB(40, 32, 16, 0),
      viewPadding: EdgeInsets.fromLTRB(40, 32, 16, 0),
    );
    final inner = await _pump(tester, outer);

    expect(
      tester.getRect(find.byKey(_child)),
      const Rect.fromLTWH(10, 0, 480, 900),
    );
    expect(inner.padding, const EdgeInsets.fromLTRB(30, 32, 6, 0));
    expect(inner.viewPadding, const EdgeInsets.fromLTRB(30, 32, 6, 0));
  });

  testWidgets('по бокам — bg/app тёмной темы', (tester) async {
    await _pump(
      tester,
      const MediaQueryData(size: Size(800, 1280)),
      brightness: Brightness.dark,
    );

    expect(_side(tester), neutralDark.bgApp);
  });
}
