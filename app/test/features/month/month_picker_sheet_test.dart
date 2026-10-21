import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/current_user.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/repositories/categories_repository.dart';
import 'package:milionchik/data/repositories/expenses_repository.dart';
import 'package:milionchik/data/repositories/outbox_queue.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:milionchik/features/month/month_picker_sheet.dart';
import 'package:milionchik/ui/components/bottom_nav.dart';
import 'package:milionchik/ui/components/month_card.dart';
import 'package:milionchik/ui/components/month_tab.dart';
import 'package:milionchik/ui/components/sheet.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';
import '../shell/shell_harness.dart';
import 'month_fixture.dart';
import 'month_picker_fixture.dart';

String _rub(String digits) => '${digits.replaceAll(' ', nbsp)}$nbsp₽';

Finder get _sheet => find.byType(MonthPicker);

Finder _inSheet(Finder finder) => find.descendant(of: _sheet, matching: finder);

Finder _sheetText(String text) => _inSheet(find.text(text));

List<MonthTab> _tabs(WidgetTester tester) =>
    tester.widgetList<MonthTab>(_inSheet(find.byType(MonthTab))).toList();

MonthCard _card(WidgetTester tester) =>
    tester.widget<MonthCard>(find.byType(MonthCard));

Iterable<String> _monthDebug(ShellHarness h) => h.records
    .where((r) => r.loggerName == 'month' && r.level == Level.FINE)
    .map((r) => r.message);

Future<void> _tapLabel(WidgetTester tester, Pattern label) async {
  await tester.tap(find.bySemanticsLabel(label));
  await tester.pumpAndSettle();
}

Future<void> _openPicker(
  WidgetTester tester, [
  String title = 'Октябрь 2026',
]) => _tapLabel(tester, '$title, выбрать месяц');

Future<String> _seed(
  WidgetTester tester,
  AppDatabase db,
  Future<String> Function(AppDatabase db) seed,
) async => (await tester.runAsync(() => seed(db)))!;

Future<void> _addExpense(
  WidgetTester tester,
  AppDatabase db,
  String budgetId,
  LocalDate day,
  int rubles,
) async {
  await tester.runAsync(() async {
    final user = LocalPrefsCurrentUser(DriftPrefsRepository(db));
    final outbox = DriftOutboxQueue(db);
    final categories = await DriftCategoriesRepository(
      db,
      currentUser: user,
      outbox: outbox,
    ).watchByBudget(budgetId).first;
    await DriftExpensesRepository(db, currentUser: user, outbox: outbox).create(
      budgetId: budgetId,
      categoryId: categories.first.id,
      amount: Money.rubles(rubles),
      spentOn: day,
    );
  });
}

void main() {
  testWidgets('тап по названию месяца открывает шторку как на 9:257: год '
      '2026, 12 вкладок Я…Д, столбики ∝ итогам месяцев (июль — 64 из 72), '
      'октябрь выбран, сводка, сравнение, легенда и «Открыть октябрь»; '
      'шторка и затемнение поверх нижнего меню', (tester) async {
    final db = openTestDatabase();
    await _seed(tester, db, seedMockupYear);
    final h = await ShellHarness.start(tester, db: db);

    await _openPicker(tester);

    expect(_sheet, findsOneWidget);
    expect(_sheetText('Выбор месяца'), findsOneWidget);
    expect(_sheetText('2026'), findsOneWidget);
    final tabs = _tabs(tester);
    expect(tabs.map((t) => t.letter).join(), 'ЯФМАМИИАСОНД');
    expect(tabs.map((t) => t.state), [
      for (var m = 1; m <= 9; m++) MonthTabState.normal,
      MonthTabState.selected,
      MonthTabState.future,
      MonthTabState.future,
    ]);
    expect(tabs.map((t) => t.fraction * monthBarArea), [
      for (final h in mockupBarHeights) moreOrLessEquals(h),
    ]);
    expect(tabs.map((t) => t.semanticLabel).first, 'Январь 2026');

    expect(_sheetText('Октябрь 2026 · идёт сейчас'), findsOneWidget);
    expect(_sheetText(_rub('18 300')), findsOneWidget);
    expect(
      _sheetText('на ${_rub('2 100')} меньше, чем в сентябре'),
      findsOneWidget,
    );
    expect(_sheetText('В среднем ${_rub('963')} в день'), findsOneWidget);
    expect(_sheetText('🍂'), findsOneWidget);
    expect(
      _sheetText(
        'Высота столбика — сколько потрачено за месяц. Самый дорогой — '
        'июль, ${_rub('24 300')}',
      ),
      findsOneWidget,
    );
    expect(_sheetText('Открыть октябрь'), findsOneWidget);

    final sheet = tester.getRect(find.byType(AppSheet));
    final nav = tester.getRect(find.byType(AppBottomNav));
    expect(sheet.bottom, 800);
    expect(sheet.top, lessThan(nav.top));
    expect(h.activeTab, AppNavTab.month);
    expect(tester.takeException(), isNull);
  });

  testWidgets('будущие месяцы недоступны: ноябрь и декабрь без действия в '
      'TalkBack, тап по ним не меняет выбор; › у года на текущем 2026 '
      'неактивна', (tester) async {
    final db = openTestDatabase();
    await _seed(tester, db, seedMockupYear);
    await ShellHarness.start(tester, db: db);
    await _openPicker(tester);

    for (final label in ['Ноябрь 2026', 'Декабрь 2026']) {
      expect(
        tester.getSemantics(find.bySemanticsLabel(label)),
        isSemantics(
          label: label,
          isEnabled: false,
          hasEnabledState: true,
          hasTapAction: false,
        ),
      );
      await _tapLabel(tester, label);
      expect(_tabs(tester)[9].state, MonthTabState.selected);
      expect(_sheetText('Открыть октябрь'), findsOneWidget);
    }
    expect(_tabs(tester).sublist(10).map((t) => t.onTap), [null, null]);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Следующий год')),
      isSemantics(isEnabled: false, hasTapAction: false),
    );
    await _tapLabel(tester, 'Следующий год');
    expect(_sheetText('2026'), findsOneWidget);
    expect(_sheet, findsOneWidget);
  });

  testWidgets('сравнение для текущего месяца — тот же отрезок дней: 1–19 '
      'октября против 1–19 сентября (траты сентября после 19-го не '
      'считаются), прошедший сентябрь — полный против полного августа', (
    tester,
  ) async {
    final db = openTestDatabase();
    await _seed(tester, db, seedMockupOctober);
    await ShellHarness.start(tester, db: db);
    await _openPicker(tester);

    expect(
      _sheetText('на ${_rub('2 100')} меньше, чем в сентябре'),
      findsOneWidget,
    );
    expect(_inSheet(find.textContaining('7${nbsp}289')), findsNothing);

    await _tapLabel(tester, 'Сентябрь 2026');
    expect(_sheetText('Сентябрь 2026'), findsOneWidget);
    expect(_sheetText(_rub('25 589')), findsOneWidget);
    expect(
      _sheetText('на ${_rub('1 380')} меньше, чем в августе'),
      findsOneWidget,
    );
    expect(_sheetText('В среднем ${_rub('853')} в день'), findsOneWidget);

    await _tapLabel(tester, 'Август 2026');
    expect(_sheetText(_rub('26 969')), findsOneWidget);
    expect(_inSheet(find.textContaining(', чем в ')), findsNothing);
    expect(_sheetText('☀️'), findsOneWidget);
  });

  testWidgets('«Открыть сентябрь» закрывает шторку и показывает сентябрь на '
      'главной', (tester) async {
    final db = openTestDatabase();
    await _seed(tester, db, seedMockupYear);
    final h = await ShellHarness.start(tester, db: db);
    await _openPicker(tester);

    await _tapLabel(tester, 'Сентябрь 2026');
    expect(_tabs(tester)[8].state, MonthTabState.selected);
    expect(_tabs(tester)[9].state, MonthTabState.normal);
    expect(_card(tester).month, YearMonth(2026, 10));

    await tester.tap(_sheetText('Открыть сентябрь'));
    await tester.pumpAndSettle();

    expect(_sheet, findsNothing);
    final card = _card(tester);
    expect(card.month, YearMonth(2026, 9));
    expect(card.dayTotals, {12: Money.rubles(20400), 25: Money.rubles(100)});
    expect(find.text('СЕНТЯБРЬ'), findsOneWidget);
    expect(find.text(_rub('20 500')), findsOneWidget);
    expect(
      _monthDebug(h),
      containsAllInOrder([
        'month title tap month=2026-10 → month picker',
        'month picker opened shown=2026-10',
        'month picker selected 2026-10 → 2026-09 by=tab, compare '
            '2026-09-01..2026-09-30 with 2026-08-01..2026-08-31',
        'month picker open button month=2026-09',
        matches(r'^month picker closed: open 2026-09 after \d+ms$'),
        'month 2026-10 → 2026-09 by=picker',
      ]),
    );

    await _openPicker(tester, 'Сентябрь 2026');
    expect(_tabs(tester)[8].state, MonthTabState.selected);
    expect(_sheetText('Открыть сентябрь'), findsOneWidget);
  });

  testWidgets('жест «назад» закрывает шторку, главная остаётся на своём '
      'месяце, приложение не закрывается', (tester) async {
    final db = openTestDatabase();
    await _seed(tester, db, seedMockupYear);
    final h = await ShellHarness.start(tester, db: db);

    await _openPicker(tester);
    await _tapLabel(tester, 'Сентябрь 2026');
    await h.systemBack();
    expect(_sheet, findsNothing);
    expect(_card(tester).month, YearMonth(2026, 10));

    await _openPicker(tester);
    await h.predictiveBackGesture();
    expect(_sheet, findsNothing);
    expect(_card(tester).month, YearMonth(2026, 10));
    expect(h.systemPops, 0);
    expect(_monthDebug(h).where((m) => m.startsWith('month picker closed')), [
      for (var i = 0; i < 2; i++)
        matches(
          r'^month picker closed without choice after \d+ms: back '
          r'gesture, tap outside or swipe down$',
        ),
    ]);

    await _openPicker(tester);
    await tester.tapAt(const Offset(180, 40));
    await tester.pumpAndSettle();
    expect(_sheet, findsNothing);
  });

  testWidgets('год ‹: 2025 без трат — столбики пустые, выбран октябрь 2025, '
      'без сравнения и самого дорогого; декабрь 2025 → › на 2026 выбирает '
      'текущий октябрь, а не будущий декабрь', (tester) async {
    final db = openTestDatabase();
    await _seed(tester, db, seedMockupYear);
    final h = await ShellHarness.start(tester, db: db);
    await _openPicker(tester);

    await _tapLabel(tester, 'Предыдущий год');
    expect(_sheetText('2025'), findsOneWidget);
    final tabs = _tabs(tester);
    expect(tabs.map((t) => t.fraction), List<double>.filled(12, 0));
    expect(
      tabs.map((t) => t.state).where((s) => s == MonthTabState.future),
      isEmpty,
    );
    expect(tabs[9].state, MonthTabState.selected);
    expect(_sheetText('Октябрь 2025'), findsOneWidget);
    expect(_sheetText(_rub('0')), findsOneWidget);
    expect(_sheetText('В среднем — в день'), findsOneWidget);
    expect(_inSheet(find.textContaining(', чем в ')), findsNothing);
    expect(
      _sheetText('Высота столбика — сколько потрачено за месяц.'),
      findsOneWidget,
    );

    await _tapLabel(tester, 'Декабрь 2025');
    expect(_sheetText('❄️'), findsOneWidget);
    await _tapLabel(tester, 'Следующий год');
    expect(_sheetText('2026'), findsOneWidget);
    expect(_tabs(tester)[9].state, MonthTabState.selected);
    expect(_tabs(tester)[11].state, MonthTabState.future);
    expect(_sheetText('Открыть октябрь'), findsOneWidget);
    expect(
      _monthDebug(h),
      containsAllInOrder([
        'month picker year 2026 → 2025 by=arrow selected=2025-10, compare '
            '2025-10-01..2025-10-31 with 2025-09-01..2025-09-30',
        'month picker selected 2025-10 → 2025-12 by=tab, compare '
            '2025-12-01..2025-12-31 with 2025-11-01..2025-11-30',
        'month picker year 2025 → 2026 by=arrow selected=2026-10 (same month '
            'is in the future, current month instead), compare '
            '2026-10-01..2026-10-19 with 2026-09-01..2026-09-19',
      ]),
    );
  });

  testWidgets('январь сравнивается с декабрём прошлого года', (tester) async {
    final db = openTestDatabase();
    final budgetId = await _seed(tester, db, seedMockupYear);
    await _addExpense(tester, db, budgetId, LocalDate(2025, 12, 30), 3000);
    await ShellHarness.start(tester, db: db);
    await _openPicker(tester);

    await _tapLabel(tester, 'Январь 2026');
    expect(_sheetText('Январь 2026'), findsOneWidget);
    expect(
      _sheetText('на ${_rub('18 260')} больше, чем в декабре'),
      findsOneWidget,
    );
    expect(_sheetText('Открыть январь'), findsOneWidget);
  });

  testWidgets('в базе нет бюджета: шторка без сумм и сравнения, «Открыть» '
      'переключает главную', (tester) async {
    final h = await ShellHarness.start(tester);
    await _openPicker(tester);

    expect(_tabs(tester).map((t) => t.fraction), List<double>.filled(12, 0));
    expect(_sheetText(_rub('0')), findsOneWidget);
    expect(_inSheet(find.textContaining(', чем в ')), findsNothing);
    await _tapLabel(tester, 'Май 2026');
    expect(_sheetText('🌷'), findsOneWidget);
    await tester.tap(_sheetText('Открыть май'));
    await tester.pumpAndSettle();
    expect(_card(tester).month, YearMonth(2026, 5));
    expect(
      _monthDebug(h),
      contains('month picker without budget: no budget selected, no sums'),
    );
  });

  testWidgets('320 dp и шрифт 2.0: шторка без переполнений, кнопка доступна', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    final db = openTestDatabase();
    await _seed(tester, db, seedMockupYear);
    await ShellHarness.start(tester, db: db, size: const Size(320, 800));
    await _openPicker(tester);
    expect(tester.takeException(), isNull);

    await _tapLabel(tester, 'Июль 2026');
    final open = _sheetText('Открыть июль');
    await tester.ensureVisible(open);
    await tester.pumpAndSettle();
    await tester.tap(open);
    await tester.pumpAndSettle();
    expect(_card(tester).month, YearMonth(2026, 7));
    expect(tester.takeException(), isNull);
  });
}
