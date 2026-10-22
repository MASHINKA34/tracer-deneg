import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/router.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/features/shell/search_stub_screen.dart';
import 'package:milionchik/features/stats/donut_chart.dart';
import 'package:milionchik/features/stats/stats_screen.dart';
import 'package:milionchik/features/stats/stats_year.dart';
import 'package:milionchik/features/stats/year_chart.dart';
import 'package:milionchik/ui/components/chip.dart';
import 'package:milionchik/ui/components/segmented.dart';
import 'package:milionchik/ui/components/stat_row.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';
import '../../support/test_fonts.dart';
import '../shell/shell_harness.dart';
import 'stats_fixture.dart';
import 'stats_year_fixture.dart';

const Color _figmaHeat3 = Color(0x61C2541C);
const Color _figmaAccent = Color(0xFFC2541C);
const Color _figmaSurface3 = Color(0xFFE7DFD3);
const Color _figmaSecondary = Color(0xFF6B6257);
const Color _figmaDisabled = Color(0xFFC4BBAE);

const double _statusBar = 32;

Finder _inStats(Finder finder) =>
    find.descendant(of: find.byType(StatsScreen), matching: finder);

Finder _column(int month) => find.byWidgetPredicate(
  (w) => w is YearChartColumn && w.month.month == month,
);

Color _barColor(WidgetTester tester, int month) {
  final box = tester.widget<DecoratedBox>(
    find.descendant(of: _column(month), matching: find.byType(DecoratedBox)),
  );
  return (box.decoration as BoxDecoration).color!;
}

Rect _bar(WidgetTester tester, int month) => tester.getRect(
  find.descendant(of: _column(month), matching: find.byType(DecoratedBox)),
);

Text _letter(WidgetTester tester, int month) => tester
    .widgetList<Text>(
      find.descendant(of: _column(month), matching: find.byType(Text)),
    )
    .last;

StatsMode _selectedMode(WidgetTester tester) => tester
    .widget<AppSegmented<StatsMode>>(find.byType(AppSegmented<StatsMode>))
    .selected;

List<String> _stats(ShellHarness h) => [
  for (final r in h.records)
    if (r.loggerName == 'stats' && r.level == Level.FINE) r.message,
];

Future<ShellHarness> _startYear(
  WidgetTester tester,
  Future<Object?> Function(AppDatabase db) seed, {
  Size size = const Size(360, 800),
}) async {
  await loadTestFonts();
  final db = openTestDatabase();
  await tester.runAsync(() => seed(db));
  final h = await ShellHarness.start(tester, db: db, size: size);
  await openStatsTab(h);
  await tester.tap(_inStats(find.text('Год')));
  await tester.pumpAndSettle();
  return h;
}

Future<void> _tapLetter(WidgetTester tester, String letter, int month) async {
  await tester.tap(
    find.descendant(of: _column(month), matching: find.text(letter)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('«Год» как 46:5398: чип «📅 2026», «Всего за 2026» 211 350 ₽, '
      '«В среднем 21 135 ₽ / мес», подпись максимума, категории за год', (
    tester,
  ) async {
    await _startYear(tester, (db) => seedMockupYear(db));

    expect(_selectedMode(tester), StatsMode.year);
    expect(find.byType(DonutChart), findsNothing);
    final chip = tester.widget<AppChip>(_inStats(find.byType(AppChip)));
    expect(chip.label, '2026');
    expect(chip.emoji, '📅');
    expect(_inStats(find.text('Всего за 2026')), findsOneWidget);
    expect(_inStats(find.text('211${nbsp}350$nbsp₽')), findsOneWidget);
    expect(_inStats(find.text('В среднем')), findsOneWidget);
    expect(_inStats(find.text('21${nbsp}135$nbsp₽ / мес')), findsOneWidget);
    expect(
      _inStats(
        find.text(
          'Самый дорогой месяц — июль (24${nbsp}300$nbsp₽). '
          'Октябрь ещё идёт.',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _column(7), matching: find.text('24,3к')),
      findsOneWidget,
    );
    expect(find.text('24,3к'), findsOneWidget);
    expect(_inStats(find.text('По категориям за год')), findsOneWidget);
    expect(statRowNames(tester).take(4), [
      'Продукты',
      'Кафе',
      'Спорт',
      'Транспорт',
    ]);
    final rows = tester.widgetList<StatRow>(find.byType(StatRow)).toList();
    expect(rows.first.share, '34% · 212 трат');
    expect(rows.first.amount, '72${nbsp}400$nbsp₽');
    expect(rows[1].share, '17% · 124 траты');
    expect(rows[2].share, '14% · 10 трат');
    expect(rows[3].share, '11% · 268 трат');
    expect(
      [for (final r in rows.take(4)) (r.fraction * 308).round()],
      [308, 153, 123, 103],
    );
  });

  testWidgets('цвета столбиков: прошлые heat-3, текущий октябрь accent с '
      'буквой accent/strong, будущие — серая черта 4 surface-3, буква '
      'disabled', (tester) async {
    await _startYear(tester, (db) => seedMockupYear(db));

    for (var m = 1; m <= 9; m++) {
      expect(_barColor(tester, m), _figmaHeat3, reason: 'месяц $m');
      expect(_letter(tester, m).style!.color, _figmaSecondary);
    }
    expect(_barColor(tester, 10), _figmaAccent);
    expect(_letter(tester, 10).style!.color, _figmaAccent);
    for (final m in [11, 12]) {
      expect(_barColor(tester, m), _figmaSurface3);
      expect(_bar(tester, m).height, yearFutureBarHeight);
      expect(_letter(tester, m).style!.color, _figmaDisabled);
    }
    expect(
      [for (var m = 1; m <= 10; m++) _bar(tester, m).height],
      [97, 90, 100, 81, 94, 107, 110, 103, 92, 83],
    );
    expect(
      [for (var m = 1; m <= 12; m++) _letter(tester, m).data],
      ['Я', 'Ф', 'М', 'А', 'М', 'И', 'И', 'А', 'С', 'О', 'Н', 'Д'],
    );
    expect(
      tester.widget<YearChartColumn>(_column(10)).kind,
      StatsYearMonthKind.current,
    );
  });

  testWidgets('раскладка 360 dp как 46:5398 (y макета минус строка '
      'состояния 32): карточка 336×288 с y=148, столбики по местам макета, '
      'список с y=486', (tester) async {
    await _startYear(tester, (db) => seedMockupYear(db));

    final card = tester.getRect(
      find
          .ancestor(
            of: find.byType(YearChart),
            matching: find.byType(DecoratedBox),
          )
          .last,
    );
    expect(card, const Rect.fromLTWH(12, 148 - _statusBar, 336, 288));
    const figmaX = [
      0.0,
      24.73,
      49.45,
      74.18,
      98.91,
      123.64,
      154.36,
      185.09,
      209.82,
      234.55,
      259.27,
      284.0,
    ];
    for (var m = 1; m <= 12; m++) {
      expect(
        _bar(tester, m).left - 30,
        moreOrLessEquals(figmaX[m - 1], epsilon: 0.6),
        reason: 'месяц $m',
      );
    }
    expect(_bar(tester, 7).top, 148 - _statusBar + 18 + 46 + 12 + 20);
    expect(_bar(tester, 10).bottom, 148 - _statusBar + 18 + 46 + 12 + 152 - 22);
    expect(
      tester.getRect(_inStats(find.text('По категориям за год'))).top,
      450 - _statusBar,
    );
    expect(
      tester.getRect(find.byType(StatRow).first).top,
      486 + 4 - _statusBar,
    );
  });

  testWidgets('среднее только по прошедшим месяцам: траты лишь в октябре — '
      '18 300 ₽ / 10 = 1 830 ₽ / мес; прошлый год делится на 12', (
    tester,
  ) async {
    await _startYear(
      tester,
      (db) => seedStatsBudget(db, [
        (LocalDate(2026, 10, 3), 'Кафе', 18300),
        (LocalDate(2025, 3, 3), 'Кафе', 6000),
        (LocalDate(2025, 11, 3), 'Кафе', 6000),
      ]),
    );

    expect(_inStats(find.text('1${nbsp}830$nbsp₽ / мес')), findsOneWidget);
    expect(_inStats(find.text('18${nbsp}300$nbsp₽')), findsWidgets);

    await tester.tap(find.bySemanticsLabel('Предыдущий год'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<AppChip>(_inStats(find.byType(AppChip))).label,
      '2025',
    );
    expect(_inStats(find.text('Всего за 2025')), findsOneWidget);
    expect(_inStats(find.text('1${nbsp}000$nbsp₽ / мес')), findsOneWidget);
    expect(
      _inStats(find.text('Самый дорогой месяц — март (6${nbsp}000$nbsp₽).')),
      findsOneWidget,
    );
    for (var m = 1; m <= 12; m++) {
      expect(_barColor(tester, m), _figmaHeat3, reason: 'месяц $m');
    }
  });

  testWidgets('тап по сентябрю → режим «Месяц» на сентябре: чип «Сентябрь '
      '2026», кольцо и «Всего за сентябрь»', (tester) async {
    final h = await _startYear(tester, (db) => seedMockupYear(db));

    await _tapLetter(tester, 'С', 9);

    expect(_selectedMode(tester), StatsMode.month);
    expect(find.byType(YearChart), findsNothing);
    expect(find.byType(DonutChart), findsOneWidget);
    expect(
      _inStats(find.widgetWithText(AppChip, 'Сентябрь 2026')),
      findsOneWidget,
    );
    expect(_inStats(find.text('Всего за сентябрь')), findsOneWidget);
    expect(_inStats(find.text('20${nbsp}300$nbsp₽')), findsOneWidget);
    expect(
      _stats(h),
      containsAllInOrder([
        'stats year bar tap month=2026-09 → month mode',
        'stats month 2026-10 → 2026-09 by=year-bar',
      ]),
    );
  });

  testWidgets('нажатие между столбиками — ближайший месяц; по TalkBack — '
      'текущий октябрь', (tester) async {
    await _startYear(tester, (db) => seedMockupYear(db));

    final march = _bar(tester, 3);
    final april = _bar(tester, 4);
    await tester.tapAt(Offset(march.right + 2, march.bottom - 4));
    await tester.pumpAndSettle();
    expect(_inStats(find.widgetWithText(AppChip, 'Март 2026')), findsOneWidget);

    await tester.tap(_inStats(find.text('Год')));
    await tester.pumpAndSettle();
    expect(_bar(tester, 4), april);
    final semantics = tester.ensureSemantics();
    tester.semantics.tap(
      find.semantics.byLabel('Октябрь 2026, 18${nbsp}300 рублей'),
    );
    await tester.pumpAndSettle();
    semantics.dispose();
    expect(
      _inStats(find.widgetWithText(AppChip, 'Октябрь 2026')),
      findsOneWidget,
    );
    expect(_selectedMode(tester), StatsMode.month);
  });

  testWidgets('будущий ноябрь не открывается: остаётся «Год», debug', (
    tester,
  ) async {
    final h = await _startYear(tester, (db) => seedMockupYear(db));

    await _tapLetter(tester, 'Н', 11);

    expect(_selectedMode(tester), StatsMode.year);
    expect(find.byType(YearChart), findsOneWidget);
    expect(
      _stats(h),
      contains(
        'stats year bar tap month=2026-11 ignored: future month '
        'today=2026-10-19',
      ),
    );
  });

  testWidgets('год ‹ ›: › на текущем году неактивна, ‹ — 2025 без трат '
      '(пусто), › — обратно 2026', (tester) async {
    final h = await _startYear(tester, (db) => seedMockupYear(db));

    await tester.tap(find.bySemanticsLabel('Следующий год'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<AppChip>(_inStats(find.byType(AppChip))).label,
      '2026',
    );

    await tester.tap(find.bySemanticsLabel('Предыдущий год'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<AppChip>(_inStats(find.byType(AppChip))).label,
      '2025',
    );
    expect(_inStats(find.text('В 2025 году трат нет')), findsOneWidget);
    expect(find.byType(YearChart), findsNothing);

    await tester.tap(find.bySemanticsLabel('Следующий год'));
    await tester.pumpAndSettle();
    expect(_inStats(find.text('Всего за 2026')), findsOneWidget);
    expect(
      _stats(h),
      containsAllInOrder([
        'stats year 2026 → 2025 by=arrow',
        'stats year 2025 → 2026 by=arrow',
      ]),
    );
  });

  testWidgets('переключатель: «Год» открывает год показанного месяца, '
      '«Месяц» возвращает тот же месяц', (tester) async {
    await _startYear(
      tester,
      (db) => seedStatsBudget(db, [
        (LocalDate(2026, 10, 3), 'Кафе', 1000),
        (LocalDate(2025, 12, 3), 'Кафе', 2000),
      ]),
    );
    await tester.tap(find.bySemanticsLabel('Предыдущий год'));
    await tester.pumpAndSettle();
    await _tapLetter(tester, 'Д', 12);
    expect(
      _inStats(find.widgetWithText(AppChip, 'Декабрь 2025')),
      findsOneWidget,
    );

    await tester.tap(_inStats(find.text('Год')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<AppChip>(_inStats(find.byType(AppChip))).label,
      '2025',
    );

    await tester.tap(_inStats(find.text('Месяц')));
    await tester.pumpAndSettle();
    expect(
      _inStats(find.widgetWithText(AppChip, 'Декабрь 2025')),
      findsOneWidget,
    );
  });

  testWidgets('тап по категории года → /search с категорией и всем годом', (
    tester,
  ) async {
    final h = await _startYear(tester, (db) => seedMockupYear(db));
    final categories = (await tester.runAsync(
      () => h.db.select(h.db.categories).get(),
    ))!;
    final cafe = categories.firstWhere((c) => c.name == 'Кафе').id;

    final row = find.widgetWithText(StatRow, 'Кафе');
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(find.byType(SearchStubScreen), findsOneWidget);
    final uri = GoRouter.of(tester.element(find.byType(SearchStubScreen)))
        .state
        .uri;
    expect(uri.path, AppRoutes.search);
    expect(uri.queryParameters, {
      'category': cafe,
      'from': '2026-01-01',
      'to': '2026-12-31',
    });
  });

  for (final width in const [320.0, 360.0]) {
    testWidgets('$width dp, шрифт 2.0: год без переполнений, 12 столбиков '
        'внутри карточки, последняя строка докручивается', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _startYear(
        tester,
        (db) => seedMockupYear(db),
        size: Size(width, 800),
      );

      expect(tester.takeException(), isNull);
      for (var m = 1; m <= 12; m++) {
        final rect = tester.getRect(_column(m));
        expect(rect.left, greaterThanOrEqualTo(30 - 0.01));
        expect(rect.right, lessThanOrEqualTo(width - 30 + 0.01));
      }
      final scrollable = tester.state<ScrollableState>(
        _inStats(find.byType(Scrollable)).first,
      );
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final last = tester.getRect(find.byType(StatRow).last);
      expect(last.bottom, lessThanOrEqualTo(800 - 80));
    });
  }
}
