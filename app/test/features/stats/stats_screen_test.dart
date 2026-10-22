import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/features/month/month_picker_sheet.dart';
import 'package:milionchik/features/stats/donut_chart.dart';
import 'package:milionchik/features/stats/stats_screen.dart';
import 'package:milionchik/ui/components/chip.dart';
import 'package:milionchik/ui/components/stat_row.dart';
import 'package:milionchik/ui/icons/app_icon.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';
import '../../support/test_fonts.dart';
import '../month/month_fixture.dart';
import '../shell/shell_harness.dart';
import 'stats_fixture.dart';

const Color _figmaGreen = Color(0xFF3BA55C);
const Color _figmaOrange = Color(0xFFF08C2E);
const Color _figmaIndigo = Color(0xFF5B63E0);
const Color _figmaYellow = Color(0xFFE3B321);
const Color _figmaPink = Color(0xFFE5579A);
const Color _figmaTeal = Color(0xFF1FA6A0);
const Color _figmaRed = Color(0xFFE0524A);
const Color _figmaSuccess = Color(0xFF2E8B57);
const Color _figmaDanger = Color(0xFFD0453A);

Finder _inStats(Finder finder) =>
    find.descendant(of: find.byType(StatsScreen), matching: finder);

Text _text(WidgetTester tester, String text) =>
    tester.widget<Text>(_inStats(find.text(text)));

Finder _trendIcon() => _inStats(find.byType(AppIcon));

Finder _flippedTrendIcon() => _inStats(
  find.byWidgetPredicate((w) => w is Transform && w.child is AppIcon),
);

Future<ShellHarness> _start(
  WidgetTester tester,
  Future<Object?> Function(AppDatabase db) seed, {
  Size size = const Size(360, 800),
}) async {
  await loadTestFonts();
  final db = openTestDatabase();
  await tester.runAsync(() => seed(db));
  final h = await ShellHarness.start(tester, db: db, size: size);
  await openStatsTab(h);
  return h;
}

void main() {
  testWidgets('октябрь как 12:820: 7 сегментов по убыванию суммы цветами '
      'категорий, в центре «7 категорий», итог, сравнение и среднее', (
    tester,
  ) async {
    await _start(tester, (db) => seedMockupOctober(db));

    final donut = donutOf(tester);
    expect(donut.segments, hasLength(7));
    expect(
      [for (final s in donut.segments) s.weight],
      [624000, 318000, 290000, 215000, 164000, 110000, 109000],
    );
    expect(
      [for (final s in donut.segments) s.color],
      [
        _figmaGreen,
        _figmaOrange,
        _figmaIndigo,
        _figmaYellow,
        _figmaPink,
        _figmaTeal,
        _figmaRed,
      ],
    );
    expect(
      find.descendant(of: find.byType(DonutChart), matching: find.text('7')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(DonutChart),
        matching: find.text('категорий'),
      ),
      findsOneWidget,
    );
    expect(_inStats(find.text('Всего за октябрь')), findsOneWidget);
    expect(_inStats(find.text('18${nbsp}300$nbsp₽')), findsOneWidget);
    expect(_inStats(find.text('В среднем 963$nbsp₽ в день')), findsOneWidget);
    expect(
      _inStats(find.widgetWithText(AppChip, 'Октябрь 2026')),
      findsOneWidget,
    );
  });

  testWidgets('плашка сравнения: меньше сентября — «−10% к сентябрю» '
      'зелёным status/success со стрелкой вниз', (tester) async {
    await _start(tester, (db) => seedMockupOctober(db));

    final text = _text(tester, '−10% к сентябрю');
    expect(text.style!.color, _figmaSuccess);
    final icon = tester.widget<AppIcon>(_trendIcon());
    expect(icon.icon, AppIcons.trendingDown);
    expect(icon.color, _figmaSuccess);
    expect(_flippedTrendIcon(), findsNothing);
  });

  testWidgets('больше прошлого месяца — «+25% к сентябрю» красным '
      'status/danger, стрелка перевёрнута вверх', (tester) async {
    await _start(
      tester,
      (db) => seedStatsBudget(db, [
        (LocalDate(2026, 10, 2), 'Кафе', 1000),
        (LocalDate(2026, 10, 18), 'Кафе', 250),
        (LocalDate(2026, 9, 5), 'Продукты', 1000),
        (LocalDate(2026, 9, 25), 'Продукты', 9000),
      ]),
    );

    final text = _text(tester, '+25% к сентябрю');
    expect(text.style!.color, _figmaDanger);
    final icon = tester.widget<AppIcon>(_trendIcon());
    expect(icon.icon, AppIcons.trendingDown);
    expect(icon.color, _figmaDanger);
    final flipped = tester.widget<Transform>(_flippedTrendIcon());
    expect(flipped.transform.storage[5], -1);
  });

  testWidgets('в прошлом месяце трат не было — плашки сравнения нет, '
      'одна категория — целое кольцо', (tester) async {
    await _start(
      tester,
      (db) => seedStatsBudget(db, [(LocalDate(2026, 10, 3), 'Дом', 4500)]),
    );

    expect(_inStats(find.textContaining('к сентябрю')), findsNothing);
    expect(donutOf(tester).segments, hasLength(1));
    expect(_inStats(find.text('категория')), findsOneWidget);
    expect(_inStats(find.text('100% · 1 трата')), findsOneWidget);
    expect(_inStats(find.text('В среднем 237$nbsp₽ в день')), findsOneWidget);
  });

  testWidgets('список: StatRow в порядке сегментов, «34% · 18 трат», полосы '
      'относительно «Продуктов»', (tester) async {
    await _start(tester, (db) => seedMockupOctober(db));

    expect(statRowNames(tester), [
      'Продукты',
      'Кафе',
      'Спорт',
      'Транспорт',
      'Развлечения',
      'Связь',
      'Здоровье',
    ]);
    final rows = tester.widgetList<StatRow>(find.byType(StatRow)).toList();
    expect(
      [for (final r in rows) r.share],
      [
        '34% · 18 трат',
        '17% · 11 трат',
        '16% · 1 трата',
        '12% · 6 трат',
        '9% · 4 траты',
        '6% · 2 траты',
        '6% · 1 трата',
      ],
    );
    expect(
      [for (final r in rows) r.amount],
      [
        '6${nbsp}240$nbsp₽',
        '3${nbsp}180$nbsp₽',
        '2${nbsp}900$nbsp₽',
        '2${nbsp}150$nbsp₽',
        '1${nbsp}640$nbsp₽',
        '1${nbsp}100$nbsp₽',
        '1${nbsp}090$nbsp₽',
      ],
    );
    expect(
      [for (final r in rows) (308 * r.fraction).round()],
      [308, 157, 143, 106, 81, 54, 54],
    );
    expect(_inStats(find.text('По категориям')), findsOneWidget);
    expect(_inStats(find.text('по сумме ↓')), findsOneWidget);
    expect(
      find.bySemanticsLabel('Кафе, 17 %, 11 трат, 3${nbsp}180 рублей'),
      findsOneWidget,
    );
  });

  testWidgets('раскладка 360 dp как 12:820: шапка 60, переключатель 44, '
      'карточка 336×168 с кольцом 132, список с y=374', (tester) async {
    await _start(tester, (db) => seedMockupOctober(db));

    expect(tester.getRect(_inStats(find.text('Статистика'))).top, 16);
    expect(tester.getRect(_inStats(find.byType(AppChip))).center.dy, 30);
    expect(
      tester.getRect(find.byType(DonutChart)),
      const Rect.fromLTWH(30, 134, donutSize, donutSize),
    );
    expect(tester.getRect(find.byType(StatRow).first).top, 346);
    expect(tester.getRect(_inStats(find.text('По категориям'))).top, 304);
  });

  testWidgets('чип периода открывает выбор месяца, «Открыть сентябрь» — '
      'статистика сентября со сравнением к августу', (tester) async {
    await _start(tester, (db) => seedMockupOctober(db));

    await tester.tap(_inStats(find.byType(AppChip)));
    await tester.pumpAndSettle();
    expect(find.byType(MonthPicker), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Сентябрь 2026'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Открыть сентябрь'));
    await tester.pumpAndSettle();

    expect(find.byType(MonthPicker), findsNothing);
    expect(
      _inStats(find.widgetWithText(AppChip, 'Сентябрь 2026')),
      findsOneWidget,
    );
    expect(_inStats(find.text('Всего за сентябрь')), findsOneWidget);
    expect(_inStats(find.textContaining('к августу')), findsOneWidget);
    expect(donutOf(tester).segments, isNotEmpty);
  });

  testWidgets('«Год» в переключателе открывает год показанного месяца '
      'вместо кольца, debug [stats]', (tester) async {
    final h = await _start(tester, (db) => seedMockupOctober(db));

    await tester.tap(_inStats(find.text('Год')));
    await tester.pumpAndSettle();

    expect(find.byType(DonutChart), findsNothing);
    expect(
      h.records
          .where((r) => r.loggerName == 'stats' && r.level == Level.FINE)
          .map((r) => r.message),
      contains(
        'stats mode month → year by=segmented month=2026-10, '
        'opening its year 2026',
      ),
    );
  });

  testWidgets('месяц без трат — пустое состояние в духе 47:5951 без кольца и '
      'списка', (tester) async {
    await _start(tester, (db) => seedStatsBudget(db));

    expect(_inStats(find.text('В октябре трат нет')), findsOneWidget);
    expect(
      _inStats(
        find.text(
          'Когда появятся траты, здесь будет диаграмма по категориям и '
          'сравнение с прошлым месяцем.',
        ),
      ),
      findsOneWidget,
    );
    expect(find.byType(DonutChart), findsNothing);
    expect(find.byType(StatRow), findsNothing);
    final icon = tester.widget<AppIcon>(_inStats(find.byType(AppIcon)));
    expect(icon.icon, AppIcons.pieChart);
  });

  testWidgets('бюджета ещё нет — то же пустое состояние', (tester) async {
    await _start(tester, (db) async => null);

    expect(_inStats(find.text('В октябре трат нет')), findsOneWidget);
    expect(find.byType(DonutChart), findsNothing);
  });

  for (final width in const [320.0, 360.0]) {
    testWidgets('$width dp, шрифт 2.0: без переполнений, тексты строк '
        'внутри экрана, последняя строка докручивается', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _start(
        tester,
        (db) => seedMockupOctober(db),
        size: Size(width, 800),
      );

      expect(tester.takeException(), isNull);
      final scrollable = tester.state<ScrollableState>(
        _inStats(find.byType(Scrollable)).first,
      );
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      for (final row in find.byType(StatRow).evaluate()) {
        for (final text
            in find
                .descendant(
                  of: find.byWidget(row.widget),
                  matching: find.byType(Text),
                )
                .evaluate()) {
          final rect = tester.getRect(find.byWidget(text.widget));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(width));
        }
      }
      final last = tester.getRect(find.byType(StatRow).last);
      expect(last.bottom, lessThanOrEqualTo(800 - 80));
    });
  }
}
