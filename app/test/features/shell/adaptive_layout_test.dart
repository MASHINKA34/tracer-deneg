import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/core/app_frame.dart';
import 'package:milionchik/features/month/day_sheet.dart';
import 'package:milionchik/features/month/month_header.dart';
import 'package:milionchik/features/month/month_picker_sheet.dart';
import 'package:milionchik/features/month/month_screen.dart';
import 'package:milionchik/features/month/today_block.dart';
import 'package:milionchik/features/expense/edit_expense_screen.dart';
import 'package:milionchik/features/expense/new_expense_screen.dart';
import 'package:milionchik/features/shell/search_stub_screen.dart';
import 'package:milionchik/ui/components/bottom_nav.dart';
import 'package:milionchik/ui/components/month_card.dart';
import 'package:milionchik/ui/components/sheet.dart';
import 'package:milionchik/ui/tokens/tokens.g.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';
import '../month/month_fixture.dart';
import 'shell_harness.dart';

const double _statusBar = 32;
const double _gestureBar = 24;

Future<ShellHarness> _start(
  WidgetTester tester,
  Size size, {
  double scale = 1,
  FakeViewPadding? padding,
}) async {
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  final db = openTestDatabase();
  await tester.runAsync(() => seedMockupOctober(db));
  final h = await ShellHarness.start(
    tester,
    db: db,
    size: size,
    topInset: _statusBar,
    bottomInset: _gestureBar,
  );
  if (padding != null) {
    tester.view
      ..padding = padding
      ..viewPadding = padding;
    await tester.pumpAndSettle();
  }
  return h;
}

Rect _rect(WidgetTester tester, Type type) =>
    tester.getRect(find.byType(type).first);

MediaQueryData _media(WidgetTester tester, Type type) =>
    MediaQuery.of(tester.element(find.byType(type).first));

ScrollPosition _monthScroll(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byType(MonthScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

Future<void> _expectTodayFullyReachable(WidgetTester tester) async {
  final position = _monthScroll(tester);
  final scrolls = position.maxScrollExtent > 0;
  position.jumpTo(position.maxScrollExtent);
  await tester.pumpAndSettle();
  final bottom = _rect(tester, TodayBlock).bottom;
  final limit = _rect(tester, AppBottomNav).top - 20;
  if (scrolls) {
    expect(bottom, closeTo(limit, 0.5));
  } else {
    expect(bottom, lessThanOrEqualTo(limit));
  }
}

Color _sideColor(WidgetTester tester) => tester
    .widget<ColoredBox>(
      find
          .descendant(
            of: find.byType(AppFrame),
            matching: find.byType(ColoredBox),
          )
          .first,
    )
    .color;

void _expectColumn(
  WidgetTester tester,
  Size window, {
  required double left,
  required double width,
}) {
  final nav = _rect(tester, AppBottomNav);
  expect(nav.left, left);
  expect(nav.width, width);
  expect(nav.bottom, window.height);
  final header = _rect(tester, MonthHeader);
  expect(header.left, left);
  expect(header.width, width);
  expect(header.top, _statusBar);
  final card = _rect(tester, MonthCard);
  expect(card.left, left + 12);
  expect(card.right, left + width - 12);
  expect(_media(tester, MonthHeader).size, Size(width, window.height));
}

Future<void> _openDay(WidgetTester tester, String date) async {
  await tester.tap(find.bySemanticsLabel(RegExp('^$date')));
  await tester.pumpAndSettle();
}

void main() {
  for (final (size, scale) in const [
    (Size(320, 800), 1.0),
    (Size(320, 800), 2.0),
    (Size(412, 915), 1.0),
    (Size(412, 915), 2.0),
  ]) {
    final name = '${size.width.toInt()}×${size.height.toInt()} шрифт $scale';
    testWidgets('телефон $name: шапка, карточка и меню во всю ширину, меню до '
        'низа над жестовой панелью, главная прокручивается до конца блока '
        '«Сегодня», шторка дня во всю ширину, без переполнения', (
      tester,
    ) async {
      await _start(tester, size, scale: scale);

      _expectColumn(tester, size, left: 0, width: size.width);
      final nav = _rect(tester, AppBottomNav);
      final tab = tester.getRect(
        find
            .descendant(
              of: find.byType(AppBottomNav),
              matching: find.bySemanticsLabel('Месяц'),
            )
            .first,
      );
      expect(tab.top, greaterThanOrEqualTo(nav.top));
      expect(tab.bottom, lessThanOrEqualTo(size.height - _gestureBar));

      await _expectTodayFullyReachable(tester);

      _monthScroll(tester).jumpTo(0);
      await tester.pumpAndSettle();
      await _openDay(tester, '17 октября');
      final sheet = _rect(tester, AppSheet);
      expect(sheet.left, 0);
      expect(sheet.right, size.width);
      expect(sheet.bottom, size.height);
      expect(tester.takeException(), isNull);
    });
  }

  for (final (size, scale) in const [
    (Size(800, 1280), 1.0),
    (Size(800, 1280), 2.0),
  ]) {
    testWidgets('планшет 800×1280 шрифт $scale: колонка 480 dp по центру '
        '(160 dp по бокам), по бокам bg/app, меню до низа, без '
        'переполнения', (tester) async {
      await _start(tester, size, scale: scale);

      _expectColumn(tester, size, left: 160, width: maxContentWidth);
      expect(_sideColor(tester), neutralLight.bgApp);
      await _expectTodayFullyReachable(tester);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('планшет в тёмной теме: по бокам bg/app тёмной темы', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await _start(tester, const Size(800, 1280));

    expect(_sideColor(tester), neutralDark.bgApp);
  });

  for (final scale in const [1.0, 2.0]) {
    testWidgets('альбомная 1280×800 шрифт $scale с вырезом слева 40 dp: '
        'колонка 480 по центру безопасной области (420 dp слева), вырез её не '
        'сдвигает, шторка дня ровно над колонкой, главная прокручивается '
        'вместо обрезания', (tester) async {
      const size = Size(1280, 800);
      await _start(
        tester,
        size,
        scale: scale,
        padding: const FakeViewPadding(
          left: 40,
          top: _statusBar,
          bottom: _gestureBar,
        ),
      );

      _expectColumn(tester, size, left: 420, width: maxContentWidth);
      expect(_media(tester, MonthScreen).padding.left, 0);
      expect(_media(tester, MonthScreen).viewPadding.left, 0);
      expect(_media(tester, MonthScreen).padding.top, _statusBar);
      if (scale == 2) {
        expect(
          _rect(tester, TodayBlock).bottom,
          greaterThan(_rect(tester, AppBottomNav).top),
        );
      }
      await _expectTodayFullyReachable(tester);

      _monthScroll(tester).jumpTo(0);
      await tester.pumpAndSettle();
      await _openDay(tester, '17 октября');
      final sheet = _rect(tester, AppSheet);
      expect(sheet.left, 420);
      expect(sheet.width, maxContentWidth);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('окно 500 dp с вырезом слева 40 dp: колонка 480 со сдвигом 10, '
      'под вырезом остаётся 30 dp — на столько и отступает содержимое', (
    tester,
  ) async {
    const size = Size(500, 900);
    await _start(
      tester,
      size,
      padding: const FakeViewPadding(
        left: 40,
        top: _statusBar,
        bottom: _gestureBar,
      ),
    );

    expect(_rect(tester, AppBottomNav).left, 10);
    expect(_rect(tester, AppBottomNav).width, maxContentWidth);
    expect(_media(tester, MonthScreen).padding.left, 30);
    expect(_media(tester, MonthScreen).viewPadding.left, 30);
    expect(_rect(tester, MonthHeader).left, 40);
    expect(_rect(tester, MonthCard).left, 52);
    expect(_rect(tester, MonthCard).right, 478);
    expect(tester.takeException(), isNull);
  });

  testWidgets('альбомная 1280×800: шторка дня, выбор месяца, «Новая трата», '
      'трата и поиск — в колонке 480 dp, шторки у низа экрана, затемнение на '
      'всё окно и тап по боковому полю закрывает шторку', (tester) async {
    const size = Size(1280, 800);
    final h = await _start(tester, size);

    await _openDay(tester, '17 октября');
    var sheet = _rect(tester, AppSheet);
    expect(sheet.left, 400);
    expect(sheet.width, maxContentWidth);
    expect(sheet.bottom, size.height);
    expect(find.byType(DaySheet), findsOneWidget);
    expect(tester.getRect(find.byType(ModalBarrier).last), Offset.zero & size);
    await tester.tapAt(const Offset(100, 600));
    await tester.pumpAndSettle();
    expect(find.byType(DaySheet), findsNothing);

    await _openDay(tester, '17 октября');
    await tester.tap(
      find.descendant(of: find.byType(DaySheet), matching: find.text('Кафе')),
    );
    await tester.pumpAndSettle();
    expect(
      _rect(tester, EditExpenseScreen),
      const Rect.fromLTWH(400, 0, maxContentWidth, 800),
    );
    await h.systemBack();
    await h.systemBack();
    expect(find.byType(DaySheet), findsNothing);

    await tester.tap(find.bySemanticsLabel('Поиск'));
    await tester.pumpAndSettle();
    expect(
      _rect(tester, SearchStubScreen),
      const Rect.fromLTWH(400, 0, maxContentWidth, 800),
    );
    await h.systemBack();

    await tester.tap(find.bySemanticsLabel('Октябрь 2026, выбрать месяц'));
    await tester.pumpAndSettle();
    expect(find.byType(MonthPicker), findsOneWidget);
    sheet = _rect(tester, AppSheet);
    expect(sheet.left, 400);
    expect(sheet.width, maxContentWidth);
    expect(sheet.bottom, size.height);
    await h.systemBack();

    await h.tapPlus();
    expect(
      _rect(tester, NewExpenseScreen),
      const Rect.fromLTWH(400, 0, maxContentWidth, 800),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('альбомная 960×600 шрифт 2.0: шторка дня в колонке 480 во всю '
      'высоту под статус-баром, она и выбор месяца прокручиваются до кнопки, '
      'кнопки нажимаются', (tester) async {
    const size = Size(960, 600);
    await _start(tester, size, scale: 2);

    await _openDay(tester, '17 октября');
    expect(
      _rect(tester, AppSheet),
      const Rect.fromLTRB(240, _statusBar, 720, 600),
    );
    final add = find.text('Добавить трату в этот день');
    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(add).bottom,
      lessThanOrEqualTo(size.height - _gestureBar),
    );
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(find.byType(NewExpenseScreen), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Закрыть'));
    await tester.pumpAndSettle();
    expect(find.byType(DaySheet), findsOneWidget);
    await tester.tapAt(const Offset(480, 10));
    await tester.pumpAndSettle();
    expect(find.byType(DaySheet), findsNothing);

    await tester.tap(find.bySemanticsLabel('Октябрь 2026, выбрать месяц'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Сентябрь 2026'));
    await tester.pumpAndSettle();
    final open = find.text('Открыть сентябрь');
    await tester.ensureVisible(open);
    await tester.pumpAndSettle();
    await tester.tap(open);
    await tester.pumpAndSettle();
    expect(find.byType(MonthPicker), findsNothing);
    expect(
      tester.widget<MonthCard>(find.byType(MonthCard)).month,
      YearMonth(2026, 9),
    );
    expect(tester.takeException(), isNull);
  });
}
