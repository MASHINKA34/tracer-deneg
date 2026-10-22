import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/router.dart';
import 'package:milionchik/features/search/search_period.dart';
import 'package:milionchik/features/search/search_screen.dart';
import 'package:milionchik/features/stats/stats_screen.dart';
import 'package:milionchik/l10n/app_localizations_ru.dart';
import 'package:milionchik/ui/components/chip.dart';
import 'package:milionchik/ui/components/stat_row.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';
import '../../support/test_fonts.dart';
import '../month/month_fixture.dart';
import '../shell/shell_harness.dart';
import 'stats_fixture.dart';

Uri _location(WidgetTester tester, Type screen) =>
    GoRouter.of(tester.element(find.byType(screen))).state.uri;

Future<ShellHarness> _octoberStats(WidgetTester tester) async {
  await loadTestFonts();
  final db = openTestDatabase();
  await tester.runAsync(() => seedMockupOctober(db));
  final h = await ShellHarness.start(tester, db: db);
  await openStatsTab(h);
  return h;
}

Future<String> _cafeId(WidgetTester tester, ShellHarness h) async {
  final categories = (await tester.runAsync(
    () => h.db.select(h.db.categories).get(),
  ))!;
  return categories.firstWhere((c) => c.name == 'Кафе').id;
}

Future<void> _tapRow(WidgetTester tester, String name) async {
  final row = find.widgetWithText(StatRow, name);
  await tester.ensureVisible(row);
  await tester.pumpAndSettle();
  await tester.tap(row);
  await tester.pumpAndSettle();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('тап по «Кафе» → /search с категорией и октябрём, на поиске '
      'чипы «☕ Кафе» и «Октябрь 2026», «назад» — снова статистика', (
    tester,
  ) async {
    final h = await _octoberStats(tester);
    final cafeId = await _cafeId(tester, h);

    await _tapRow(tester, 'Кафе');

    expect(find.byType(SearchScreen), findsOneWidget);
    final uri = _location(tester, SearchScreen);
    expect(uri.path, AppRoutes.search);
    expect(uri.queryParameters, {
      'category': cafeId,
      'from': '2026-10-01',
      'to': '2026-10-31',
    });
    expect(
      find.descendant(
        of: find.byType(SearchScreen),
        matching: find.widgetWithText(AppChip, 'Кафе'),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<AppChip>(
            find.descendant(
              of: find.byType(SearchScreen),
              matching: find.widgetWithText(AppChip, 'Кафе'),
            ),
          )
          .emoji,
      '☕',
    );
    expect(
      find.descendant(
        of: find.byType(SearchScreen),
        matching: find.widgetWithText(AppChip, 'Октябрь 2026'),
      ),
      findsOneWidget,
    );
    expect(
      h.records
          .where((r) => r.loggerName == 'stats' && r.level == Level.FINE)
          .map((r) => r.message),
      contains(
        'stats category row #1 tap id=$cafeId month=2026-10 → /search '
        'filter category+period 2026-10-01..2026-10-31',
      ),
    );
    expect(
      h.navDebug(),
      contains(
        'search opened with filter category=$cafeId '
        'period=2026-10-01..2026-10-31',
      ),
    );

    await h.systemBack();
    expect(find.byType(SearchScreen), findsNothing);
    expect(find.byType(StatsScreen), findsOneWidget);
    expect(_location(tester, StatsScreen).path, AppRoutes.stats);
  });

  testWidgets('строка открывается и по TalkBack-нажатию на подпись строки', (
    tester,
  ) async {
    await _octoberStats(tester);

    final semantics = tester.ensureSemantics();
    await tester.tap(
      find.bySemanticsLabel(RegExp(r'^Продукты, 34 %, 18 трат, ')),
    );
    await tester.pumpAndSettle();
    semantics.dispose();

    expect(find.byType(SearchScreen), findsOneWidget);
  });

  group('SearchRouteFilter.fromQuery', () {
    late List<LogRecord> records;

    setUp(() {
      records = [];
      Logger.root.level = Level.ALL;
      final sub = Logger.root.onRecord.listen(records.add);
      addTearDown(sub.cancel);
    });

    test('адрес из статистики разбирается обратно в категорию и период', () {
      final uri = Uri.parse(
        AppRoutes.searchFor(
          categoryId: 'c 1/☕',
          from: LocalDate(2026, 10, 1),
          to: LocalDate(2026, 10, 31),
        ),
      );

      expect(
        SearchRouteFilter.fromQuery(uri.queryParameters),
        SearchRouteFilter(
          categoryId: 'c 1/☕',
          from: LocalDate(2026, 10, 1),
          to: LocalDate(2026, 10, 31),
        ),
      );
      expect(records.where((r) => r.level >= Level.WARNING), isEmpty);
    });

    test('без параметров — фильтра нет', () {
      final filter = SearchRouteFilter.fromQuery(const {});

      expect(filter.isEmpty, isTrue);
      expect(filter.toString(), 'category=- period=..');
    });

    test('дата не yyyy-MM-dd — warn [nav], поиск без неё', () {
      final filter = SearchRouteFilter.fromQuery(const {
        'category': 'cafe',
        'from': '31.10.2026',
        'to': '2026-10-31',
      });

      expect(filter.categoryId, 'cafe');
      expect(filter.from, isNull);
      expect(filter.to, LocalDate(2026, 10, 31));
      expect(
        [
          for (final r in records)
            if (r.level == Level.WARNING) '[${r.loggerName}] ${r.message}',
        ],
        [
          '[nav] search route: from=31.10.2026 is not a yyyy-MM-dd date, '
              'opening search without it',
        ],
      );
    });

    test('период задом наперёд и пустая категория отбрасываются', () {
      final filter = SearchRouteFilter.fromQuery(const {
        'category': '',
        'from': '2026-10-31',
        'to': '2026-10-01',
      });

      expect(filter.isEmpty, isTrue);
      expect(
        records.map((r) => r.message),
        contains(
          'search route: period 2026-10-31..2026-10-01 ends before it '
          'starts, opening search without period',
        ),
      );
    });
  });

  test('чип периода поиска: целый месяц — «Октябрь 2026», иначе даты', () {
    final l10n = AppLocalizationsRu();

    expect(
      searchPeriodLabel(l10n, LocalDate(2026, 10, 1), LocalDate(2026, 10, 31)),
      'Октябрь 2026',
    );
    expect(
      searchPeriodLabel(l10n, LocalDate(2026, 10, 1), LocalDate(2026, 10, 19)),
      '01.10.2026 – 19.10.2026',
    );
  });
}
