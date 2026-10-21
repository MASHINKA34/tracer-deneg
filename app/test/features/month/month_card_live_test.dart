import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/queries/month_queries.dart';
import 'package:milionchik/ui/catalog/demo_months.dart';
import 'package:milionchik/ui/components/day_cell.dart';
import 'package:milionchik/ui/components/fab.dart';
import 'package:milionchik/ui/components/month_card.dart';
import 'package:milionchik/ui/decor/decor_painter.dart';
import 'package:milionchik/ui/theme/mood_colors.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';
import '../shell/shell_harness.dart';
import 'month_fixture.dart';

final YearMonth _october = YearMonth(2026, 10);
final YearMonth _september = YearMonth(2026, 9);

Future<String> _seedOctober(WidgetTester tester, AppDatabase db) async =>
    (await tester.runAsync(() => seedMockupOctober(db)))!;

MonthCard _card(WidgetTester tester) =>
    tester.widget<MonthCard>(find.byType(MonthCard));

Map<int, DayCell> _cells(WidgetTester tester) => {
  for (final cell in tester.widgetList<DayCell>(
    find.descendant(of: find.byType(MonthCard), matching: find.byType(DayCell)),
  ))
    if (cell.day != null) cell.day!: cell,
};

Iterable<String> _monthDebug(ShellHarness h) => h.records
    .where((r) => r.loggerName == 'month' && r.level == Level.FINE)
    .map((r) => r.message);

Future<void> _tapArrow(WidgetTester tester, String label) async {
  await tester.tap(find.bySemanticsLabel(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('октябрь из базы как на 7:7: суммы и уровни дней, сегодня 19-е, '
      'будущие дни серые без сумм, итог 18 300 ₽ и среднее 963 ₽', (
    tester,
  ) async {
    final db = openTestDatabase();
    await _seedOctober(tester, db);
    await ShellHarness.start(tester, db: db);

    final card = _card(tester);
    expect(card.month, _october);
    expect(card.today, LocalDate(2026, 10, 19));
    expect(card.dayTotals, demoAutumn.dayTotals);
    expect(card.mood, Mood.autumn);
    expect(card.holidayMarks, {31: '🎃'});

    const z = DayCellType.zero;
    const l = DayCellType.low;
    const m = DayCellType.medium;
    const h = DayCellType.high;
    final expected = <int, (DayCellType, String?)>{
      1: (l, '450'),
      2: (m, '1${nbsp}280'),
      3: (h, '2${nbsp}340'),
      4: (z, '—'),
      5: (m, '860'),
      6: (l, '320'),
      7: (l, '450'),
      8: (m, '1${nbsp}150'),
      9: (m, '540'),
      10: (h, '2${nbsp}670'),
      11: (m, '990'),
      12: (h, '2${nbsp}900'),
      13: (l, '210'),
      14: (z, '—'),
      15: (m, '760'),
      16: (l, '430'),
      17: (m, '1${nbsp}450'),
      18: (l, '400'),
      19: (DayCellType.today, '1${nbsp}100'),
      for (var day = 20; day <= 31; day++) day: (DayCellType.future, null),
    };
    final cells = _cells(tester);
    expect(cells.keys, List.generate(31, (i) => i + 1));
    for (final MapEntry(key: day, value: (type, amount)) in expected.entries) {
      expect(cells[day]!.type, type, reason: 'day $day');
      expect(cells[day]!.amount, amount, reason: 'day $day');
    }
    expect(cells[31]!.holidayEmoji, '🎃');

    expect(find.text('18${nbsp}300$nbsp₽'), findsOneWidget);
    expect(find.text('963$nbsp₽ / день'), findsOneWidget);
    expect(find.text('ОКТЯБРЬ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('‹ открывает сентябрь с суммами сентября из базы, › на текущем '
      'октябре неактивна, › с сентября возвращает октябрь', (tester) async {
    final db = openTestDatabase();
    final budgetId = await _seedOctober(tester, db);
    final september = (await tester.runAsync(
      () => DriftMonthQueries(db).watchDayTotals(budgetId, _september).first,
    ))!;
    final h = await ShellHarness.start(tester, db: db);

    expect(_card(tester).onNext, isNull);
    await _tapArrow(tester, 'Следующий месяц');
    expect(_card(tester).month, _october);

    await _tapArrow(tester, 'Предыдущий месяц');
    final card = _card(tester);
    expect(card.month, _september);
    expect(september, isNotEmpty);
    expect(card.dayTotals, september);
    expect(card.mood, Mood.autumn);
    expect(card.onNext, isNotNull);
    expect(find.text('СЕНТЯБРЬ'), findsOneWidget);
    final types = _cells(tester).values.map((c) => c.type).toSet();
    expect(types, isNot(contains(DayCellType.today)));
    expect(types, isNot(contains(DayCellType.future)));
    expect(
      find.text(Money.sum(september.values).formatTotal()),
      findsOneWidget,
    );

    await _tapArrow(tester, 'Следующий месяц');
    expect(_card(tester).month, _october);
    expect(_card(tester).onNext, isNull);
    expect(
      _monthDebug(h),
      containsAllInOrder([
        'month 2026-10 → 2026-09 by=arrow',
        'month 2026-09 → 2026-10 by=arrow',
      ]),
    );
  });

  testWidgets('стрелка листает со сдвигом: старая карточка уходит, новая '
      'въезжает с нужной стороны', (tester) async {
    final db = openTestDatabase();
    await _seedOctober(tester, db);
    await ShellHarness.start(tester, db: db);
    final october = find.byKey(ValueKey(_october));
    final september = find.byKey(ValueKey(_september));
    final rest = tester.getRect(october);

    await tester.tap(find.bySemanticsLabel('Предыдущий месяц'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(MonthCard), findsNWidgets(2));
    expect(tester.getRect(september).left, lessThan(rest.left - 20));
    expect(tester.getRect(october).left, greaterThan(rest.left + 20));
    await tester.pumpAndSettle();
    expect(find.byType(MonthCard), findsOneWidget);
    expect(tester.getRect(september).left, rest.left);

    await tester.tap(find.bySemanticsLabel('Следующий месяц'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getRect(october).left, greaterThan(rest.left + 20));
    expect(tester.getRect(september).left, lessThan(rest.left - 20));
    await tester.pumpAndSettle();
    expect(tester.getRect(october), rest);
  });

  testWidgets('свайп вправо — прошлый месяц, влево — следующий, на текущем '
      'вперёд нельзя, короткое движение не листает', (tester) async {
    final db = openTestDatabase();
    await _seedOctober(tester, db);
    final h = await ShellHarness.start(tester, db: db);

    await tester.drag(find.byType(MonthCard), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(_card(tester).month, _october);

    await tester.drag(find.byType(MonthCard), const Offset(20, 0));
    await tester.pumpAndSettle();
    expect(_card(tester).month, _october);

    await tester.drag(find.byType(MonthCard), const Offset(200, 0));
    await tester.pumpAndSettle();
    expect(_card(tester).month, _september);

    await tester.fling(find.byType(MonthCard), const Offset(120, 0), 1000);
    await tester.pumpAndSettle();
    expect(_card(tester).month, YearMonth(2026, 8));

    await tester.drag(find.byType(MonthCard), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(_card(tester).month, _september);

    expect(
      _monthDebug(h),
      containsAllInOrder([
        'month next by=swipe ignored: 2026-10 is the current month, '
            '2026-11 is in the future today=2026-10-19',
        'month swipe ignored dx=20 velocity=0: shorter than 48px and slower '
            'than 300px/s',
        'month 2026-10 → 2026-09 by=swipe',
        'month 2026-09 → 2026-08 by=swipe',
        'month 2026-08 → 2026-09 by=swipe',
      ]),
    );
  });

  testWidgets('в октябре открыть январь: зимняя карточка со снежинками, а '
      'акцент меню и «+» осенний — по сегодняшней дате', (tester) async {
    final db = openTestDatabase();
    await _seedOctober(tester, db);
    await ShellHarness.start(tester, db: db);

    for (var i = 0; i < 9; i++) {
      await _tapArrow(tester, 'Предыдущий месяц');
    }

    final card = _card(tester);
    expect(card.month, YearMonth(2026, 1));
    expect(card.mood, Mood.winter);
    expect(card.dayTotals, isEmpty);
    expect(card.holidayMarks, {1: '🎄'});
    final decor = tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(MonthCard),
            matching: find.byType(CustomPaint),
          ),
        )
        .map((p) => p.painter)
        .whereType<DecorPainter>()
        .single;
    expect(decor.mood, Mood.winter);
    final cell = tester.element(find.byType(DayCell).first);
    expect(MoodColors.of(cell).mood, Mood.winter);
    expect(
      MoodColors.of(cell).accent,
      MoodColors.forMood(Mood.winter, Brightness.light).accent,
    );
    expect(
      MoodColors.of(tester.element(find.byType(AppFab))).mood,
      Mood.autumn,
    );
    expect(find.text('ЯНВАРЬ'), findsOneWidget);
  });

  testWidgets('сегодня 31 января 2026: главная на январе, всё зимнее, 31-е — '
      'сегодня, › неактивна, итог 21 860 ₽ и среднее 705 ₽', (tester) async {
    final db = openTestDatabase();
    await tester.runAsync(() => seedMockupJanuary(db));
    await ShellHarness.start(tester, db: db, now: DateTime(2026, 1, 31, 20));

    final card = _card(tester);
    expect(card.month, YearMonth(2026, 1));
    expect(card.today, LocalDate(2026, 1, 31));
    expect(card.mood, Mood.winter);
    expect(card.onNext, isNull);
    expect(_cells(tester)[31]!.type, DayCellType.today);
    expect(
      MoodColors.of(tester.element(find.byType(AppFab))).mood,
      Mood.winter,
    );
    expect(find.text('21${nbsp}860$nbsp₽'), findsOneWidget);
    expect(find.text('705$nbsp₽ / день'), findsOneWidget);
  });

  testWidgets('выбранный месяц переживает смену вкладки', (tester) async {
    final db = openTestDatabase();
    await _seedOctober(tester, db);
    final h = await ShellHarness.start(tester, db: db);

    await _tapArrow(tester, 'Предыдущий месяц');
    expect(_card(tester).month, _september);

    await h.tapTab('Статистика');
    expect(find.byType(MonthCard), findsNothing);
    await h.tapTab('Профиль');
    await h.tapTab('Месяц');

    expect(_card(tester).month, _september);
  });

  testWidgets('тап по будущему дню ничего не открывает, нажатие в debug-логе '
      'month', (tester) async {
    final db = openTestDatabase();
    await _seedOctober(tester, db);
    final h = await ShellHarness.start(tester, db: db);

    await tester.tap(find.bySemanticsLabel(RegExp(r'^20 октября')));
    await tester.pumpAndSettle();

    expect(_card(tester).month, _october);
    expect(_card(tester).selectedDay, isNull);
    expect(
      _monthDebug(h),
      contains('day tap date=2026-10-20 ignored: future day today=2026-10-19'),
    );
  });

  testWidgets('в базе нет бюджета: карточка текущего месяца без сумм, '
      'листается', (tester) async {
    final h = await ShellHarness.start(tester);

    final card = _card(tester);
    expect(card.month, _october);
    expect(card.dayTotals, isEmpty);
    expect(
      find.descendant(
        of: find.byType(MonthCard),
        matching: find.text('0$nbsp₽'),
      ),
      findsOneWidget,
    );
    expect(
      _monthDebug(h),
      contains(
        startsWith(
          'month shown month=2026-10 without budget: no budget selected, '
          'card without sums in ',
        ),
      ),
    );

    await _tapArrow(tester, 'Предыдущий месяц');
    expect(_card(tester).month, _september);
  });
}
