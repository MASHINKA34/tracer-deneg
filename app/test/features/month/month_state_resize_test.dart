import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/core/app_frame.dart';
import 'package:milionchik/features/month/day_sheet.dart';
import 'package:milionchik/features/month/month_controller.dart';
import 'package:milionchik/features/month/month_picker_sheet.dart';
import 'package:milionchik/features/month/month_screen.dart';
import 'package:milionchik/ui/components/bottom_nav.dart';
import 'package:milionchik/ui/components/month_card.dart';
import 'package:milionchik/ui/components/sheet.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';
import '../shell/shell_harness.dart';
import 'month_fixture.dart';

const Size _tabletPortrait = Size(800, 1280);
const Size _tabletLandscape = Size(1280, 800);
const Size _phone = Size(412, 915);
const Size _unfolded = Size(840, 900);

MonthCard _card(WidgetTester tester) =>
    tester.widget<MonthCard>(find.byType(MonthCard));

ProviderContainer _container(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(AppBottomNav, skipOffstage: false)),
  listen: false,
);

Finder _sheetText(Type sheet, String text) =>
    find.descendant(of: find.byType(sheet), matching: find.text(text));

Future<ShellHarness> _start(WidgetTester tester, Size size) async {
  final db = openTestDatabase();
  await tester.runAsync(() => seedMockupOctober(db));
  return ShellHarness.start(
    tester,
    db: db,
    size: size,
    topInset: 32,
    bottomInset: 24,
  );
}

Future<void> _resize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  await tester.pumpAndSettle();
}

Future<void> _tapLabel(WidgetTester tester, Pattern label) async {
  await tester.tap(find.bySemanticsLabel(label));
  await tester.pumpAndSettle();
}

void _expectCentered(WidgetTester tester, Size window, Type type) {
  final rect = tester.getRect(find.byType(type).first);
  final width = contentWidthFor(window.width);
  expect(rect.left, (window.width - width) / 2);
  expect(rect.width, width);
}

void main() {
  testWidgets('выбранный месяц переживает поворот планшета: сентябрь остаётся '
      'на 800×1280 → 1280×800 → 800×1280, экран месяца тот же, колонка 480 '
      'по центру в обеих ориентациях', (tester) async {
    await _start(tester, _tabletPortrait);
    await _tapLabel(tester, 'Предыдущий месяц');
    expect(_card(tester).month, YearMonth(2026, 9));
    final screen = tester.state(find.byType(MonthScreen));

    for (final size in const [
      _tabletLandscape,
      _tabletPortrait,
      _tabletLandscape,
    ]) {
      await _resize(tester, size);
      expect(_card(tester).month, YearMonth(2026, 9));
      expect(
        _container(tester).read(monthControllerProvider),
        YearMonth(2026, 9),
      );
      expect(identical(tester.state(find.byType(MonthScreen)), screen), isTrue);
      _expectCentered(tester, size, AppBottomNav);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('выбранный месяц переживает раскрытие и складывание '
      'раскладушки 412×915 → 840×900 → 412×915: из всей ширины в колонку 480 '
      'и обратно', (tester) async {
    await _start(tester, _phone);
    await _tapLabel(tester, 'Предыдущий месяц');
    await _tapLabel(tester, 'Предыдущий месяц');
    expect(_card(tester).month, YearMonth(2026, 8));

    for (final size in const [_unfolded, _phone]) {
      await _resize(tester, size);
      expect(_card(tester).month, YearMonth(2026, 8));
      _expectCentered(tester, size, AppBottomNav);
    }
    await _tapLabel(tester, 'Следующий месяц');
    expect(_card(tester).month, YearMonth(2026, 9));
    expect(tester.takeException(), isNull);
  });

  testWidgets('открытая шторка дня переживает поворот: 12 сентября открыта, '
      'день выбран на карточке, день хранится в провайдере; после поворота '
      'шторка в колонке, жест «назад» с превью закрывает её и снимает выбор, '
      'приложение не закрывается', (tester) async {
    final h = await _start(tester, _tabletPortrait);
    await _tapLabel(tester, 'Предыдущий месяц');
    await _tapLabel(tester, RegExp('^12 сентября'));
    expect(find.byType(DaySheet), findsOneWidget);
    expect(
      _container(tester).read(openDaySheetProvider),
      LocalDate(2026, 9, 12),
    );

    for (final size in const [
      _tabletLandscape,
      _tabletPortrait,
      _tabletLandscape,
    ]) {
      await _resize(tester, size);
      expect(find.byType(DaySheet), findsOneWidget);
      expect(_sheetText(DaySheet, 'Суббота, 12 сентября'), findsOneWidget);
      expect(_card(tester).selectedDay, 12);
      expect(_card(tester).month, YearMonth(2026, 9));
      expect(
        _container(tester).read(openDaySheetProvider),
        LocalDate(2026, 9, 12),
      );
      _expectCentered(tester, size, AppSheet);
      expect(tester.getRect(find.byType(AppSheet)).bottom, size.height);
    }
    expect(h.frameworkHandlesBack, isTrue);

    await h.predictiveBackGesture();

    expect(find.byType(DaySheet), findsNothing);
    expect(_container(tester).read(openDaySheetProvider), isNull);
    expect(_card(tester).selectedDay, isNull);
    expect(_card(tester).month, YearMonth(2026, 9));
    expect(h.systemPops, 0);

    await _tapLabel(tester, RegExp('^14 сентября'));
    expect(_sheetText(DaySheet, 'Понедельник, 14 сентября'), findsOneWidget);
    expect(_card(tester).selectedDay, 14);
    expect(tester.takeException(), isNull);
  });

  testWidgets('открытая шторка выбора месяца переживает поворот: год 2025 и '
      'выбранный в ней месяц остаются, «Открыть …» после поворота открывает '
      'его; жест «назад» с превью закрывает шторку на планшете', (
    tester,
  ) async {
    final h = await _start(tester, _tabletPortrait);
    await _tapLabel(tester, 'Октябрь 2026, выбрать месяц');
    await _tapLabel(tester, 'Предыдущий год');
    await _tapLabel(tester, 'Май 2025');
    expect(_sheetText(MonthPicker, '2025'), findsOneWidget);
    expect(_sheetText(MonthPicker, 'Открыть май'), findsOneWidget);
    expect(_container(tester).read(monthPickerOpenProvider), isTrue);

    for (final size in const [_tabletLandscape, _tabletPortrait]) {
      await _resize(tester, size);
      expect(_sheetText(MonthPicker, '2025'), findsOneWidget);
      expect(_sheetText(MonthPicker, 'Открыть май'), findsOneWidget);
      expect(_container(tester).read(monthPickerOpenProvider), isTrue);
      _expectCentered(tester, size, AppSheet);
    }

    final open = find.text('Открыть май');
    await tester.ensureVisible(open);
    await tester.pumpAndSettle();
    await tester.tap(open);
    await tester.pumpAndSettle();
    expect(find.byType(MonthPicker), findsNothing);
    expect(_card(tester).month, YearMonth(2025, 5));
    expect(_container(tester).read(monthPickerOpenProvider), isFalse);

    await _resize(tester, _tabletLandscape);
    await _tapLabel(tester, 'Май 2025, выбрать месяц');
    expect(find.byType(MonthPicker), findsOneWidget);
    await h.predictiveBackGesture();
    expect(find.byType(MonthPicker), findsNothing);
    expect(_container(tester).read(monthPickerOpenProvider), isFalse);
    expect(_card(tester).month, YearMonth(2025, 5));
    expect(h.systemPops, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('«Новая трата» на планшете в альбомной закрывается жестом '
      '«назад» с превью, главная остаётся на своём месяце', (tester) async {
    final h = await _start(tester, _tabletLandscape);
    await _tapLabel(tester, 'Предыдущий месяц');

    await h.tapPlus();
    expect(find.text('Новая трата'), findsOneWidget);
    await _resize(tester, _tabletPortrait);
    expect(find.text('Новая трата'), findsOneWidget);

    await h.predictiveBackGesture();

    expect(find.text('Новая трата'), findsNothing);
    expect(_card(tester).month, YearMonth(2026, 9));
    expect(h.systemPops, 0);
  });
}
