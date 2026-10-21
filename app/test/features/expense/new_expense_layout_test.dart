import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/ui/components/category_tile.dart';
import 'package:milionchik/ui/components/chip.dart';
import 'package:milionchik/ui/components/keypad_key.dart';
import 'package:milionchik/ui/components/tap_target.dart';

import '../../support/app_scope.dart';
import '../../support/test_fonts.dart';
import '../month/month_fixture.dart';
import '../shell/shell_harness.dart';
import 'new_expense_harness.dart';

const double _statusBar = 32;

Future<ShellHarness> _open(
  WidgetTester tester, {
  double width = 360,
  double scale = 1,
  double topInset = _statusBar,
  double bottomInset = 0,
}) async {
  await loadTestFonts();
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  final db = openTestDatabase();
  await tester.runAsync(() => seedMockupOctober(db));
  final h = await ShellHarness.start(
    tester,
    db: db,
    size: Size(width, 800),
    topInset: topInset,
    bottomInset: bottomInset,
  );
  await h.tapPlus();
  return h;
}

Rect _setupArea(WidgetTester tester) => tester.getRect(
  find
      .ancestor(
        of: inNewExpense(find.text('Настроить')),
        matching: find.byType(GestureDetector),
      )
      .first,
);

List<Rect> _neighbourAreas(WidgetTester tester) => [
  for (final e in inNewExpense(find.byType(AppChip)).evaluate())
    tester.getRect(
      find.descendant(
        of: find.byWidget(e.widget),
        matching: find.byType(TapTarget),
      ),
    ),
  for (final e in inNewExpense(find.byType(CategoryTile)).evaluate())
    tester.getRect(
      find.descendant(
        of: find.byWidget(e.widget),
        matching: find.byType(InkWell),
      ),
    ),
];

void main() {
  testWidgets('360 × 800 под статус-баром 32 — раскладка как на 10:763: шапка '
      '56, сумма, чипы, сетка 4 × 76, подсказка, клавиатура от 492 до низа', (
    tester,
  ) async {
    await _open(tester);

    final close = tester.getRect(find.bySemanticsLabel('Закрыть'));
    expect(close.center, const Offset(30, _statusBar + 28));
    expect(close.size, const Size(48, 48));
    final title = tester.getRect(inNewExpense(find.text('Новая трата')));
    expect(title.center.dy, _statusBar + 28);
    expect(tester.getRect(inNewExpense(find.text('Сумма'))).top, 106);

    final chips = inNewExpense(find.byType(AppChip));
    expect(chips, findsNWidgets(3));
    final date = tester.getRect(
      find
          .descendant(
            of: find.widgetWithText(AppChip, 'Сегодня, 19 окт'),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(date.top, 196);
    expect(date.height, 36);

    expect(tester.getRect(inNewExpense(find.text('Категория'))).top, 254);
    final tiles = [
      for (final e in inNewExpense(find.byType(CategoryTile)).evaluate())
        tester.getRect(find.byWidget(e.widget)),
    ];
    expect({for (final r in tiles) r.left}, {16.0, 100.0, 184.0, 268.0});
    expect({for (final r in tiles) r.top}, {286.0, 372.0});
    expect({for (final r in tiles) r.width}, {76.0});

    final hint = tester.getRect(
      inNewExpense(find.text('Нажми на категорию — и трата сохранится')),
    );
    expect(hint.top, 462);

    final keys = [
      for (final e in inNewExpense(find.byType(KeypadKey)).evaluate())
        tester.getRect(find.byWidget(e.widget)),
    ];
    expect(keys, hasLength(12));
    expect(keys.first.topLeft, const Offset(12, 504));
    expect(keys.first.height, 58);
    expect(keys.first.width, moreOrLessEquals(106.67, epsilon: 0.01));
    expect(keys.last.bottomRight.dy, 504 + 4 * 58 + 3 * 8);
    expect(keys.last.right, 348);
  });

  for (final (width, scale) in const [
    (360.0, 1.0),
    (320.0, 1.0),
    (360.0, 2.0),
    (320.0, 2.0),
  ]) {
    testWidgets('$width dp, шрифт $scale: «Настроить» нажимается в области не '
        'меньше 48 × 48, она не заходит на чипы и плитки; крестик 48 × 48 не '
        'заходит на чип бюджета', (tester) async {
      await _open(tester, width: width, scale: scale);

      final setup = _setupArea(tester);
      expect(setup.width, greaterThanOrEqualTo(48));
      expect(setup.height, greaterThanOrEqualTo(48));
      for (final other in _neighbourAreas(tester)) {
        expect(setup.overlaps(other), isFalse, reason: '$setup ∩ $other');
      }
      final close = tester.getRect(find.bySemanticsLabel('Закрыть'));
      final budget = tester.getRect(
        find
            .descendant(
              of: find.widgetWithText(AppChip, 'Личный'),
              matching: find.byType(TapTarget),
            )
            .first,
      );
      expect(close.overlaps(budget), isFalse);

      await tester.tapAt(Offset(setup.left + 2, setup.top + 1));
      await tester.pumpAndSettle();
      expect(find.text('Категории'), findsOneWidget);
    });
  }

  for (final width in const [360.0, 320.0]) {
    testWidgets('$width dp, шрифт 2.0, жестовая панель 24: без переполнений, '
        'экран прокручивается, все клавиши нажимаются, плитки видны после '
        'прокрутки, последний ряд клавиш над жестовой панелью', (tester) async {
      final h = await _open(tester, width: width, scale: 2, bottomInset: 24);
      expect(tester.takeException(), isNull);

      await typeKeys(tester, '1234567,89');
      expect(amountText(tester), '1${nbspace}234${nbspace}567,89');
      for (final name in [
        'Продукты',
        'Кафе',
        'Транспорт',
        'Дом',
        'Здоровье',
        'Спорт',
        'Развлечения',
        'Все',
      ]) {
        final tile = categoryTile(name);
        await tester.ensureVisible(tile);
        await tester.pumpAndSettle();
        expect(
          tester.getRect(tile).bottom,
          lessThanOrEqualTo(800),
          reason: name,
        );
      }

      final scrollable = tester.state<ScrollableState>(
        inNewExpense(find.byType(Scrollable)).first,
      );
      expect(scrollable.position.maxScrollExtent, greaterThan(0));
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pumpAndSettle();
      final backspace = tester.getRect(keypadKey('Стереть'));
      expect(backspace.bottom, lessThanOrEqualTo(800 - 24 - 12));
      await tester.tap(keypadKey('Стереть'));
      await tester.pump();
      expect(amountText(tester), '1${nbspace}234${nbspace}567,8');
      expect(tester.takeException(), isNull);
      expect(h.systemPops, 0);
    });
  }

  testWidgets('жестовая панель 48: клавиатура тянется до низа экрана, клавиши '
      'над панелью', (tester) async {
    await _open(tester, bottomInset: 48);

    final scrollable = tester.state<ScrollableState>(
      inNewExpense(find.byType(Scrollable)).first,
    );
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pumpAndSettle();
    final panel = tester.getRect(
      find
          .ancestor(of: keypadKey('1'), matching: find.byType(DecoratedBox))
          .last,
    );
    expect(panel.bottom, 800);
    expect(
      tester.getRect(keypadKey('Стереть')).bottom,
      lessThanOrEqualTo(800 - 48 - 12),
    );
  });

  for (final (top, bottom) in const [(48.0, 48.0), (24.0, 48.0)]) {
    testWidgets('360 × 800, вырез $top и кнопки навигации $bottom, шрифт 1.0: '
        'всё помещается без прокрутки — клавиши ниже 58, но не ниже 48, '
        'нижний ряд над панелью навигации', (tester) async {
      await _open(tester, topInset: top, bottomInset: bottom);

      final scrollable = tester.state<ScrollableState>(
        inNewExpense(find.byType(Scrollable)).first,
      );
      expect(scrollable.position.maxScrollExtent, 0);
      final keys = [
        for (final e in inNewExpense(find.byType(KeypadKey)).evaluate())
          tester.getRect(find.byWidget(e.widget)),
      ];
      final height = keys.first.height;
      expect(height, inInclusiveRange(48, 58));
      expect({for (final r in keys) r.height}, {height});
      expect(keys.last.bottom, lessThanOrEqualTo(800 - bottom - 12));
      expect(
        tester
            .getRect(
              inNewExpense(
                find.text('Нажми на категорию — и трата сохранится'),
              ),
            )
            .bottom,
        lessThanOrEqualTo(keys.first.top),
      );
    });
  }
}
