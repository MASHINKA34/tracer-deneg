import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/features/expense/expense_date_sheet.dart';
import 'package:milionchik/features/expense/new_expense_controller.dart';
import 'package:milionchik/features/expense/new_expense_screen.dart';
import 'package:milionchik/ui/components/chip.dart';
import 'package:milionchik/ui/components/tap_target.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';
import '../../support/test_fonts.dart';
import '../month/month_fixture.dart';
import '../shell/shell_harness.dart';
import 'new_expense_harness.dart';

Finder _inSheet(Finder finder) =>
    find.descendant(of: find.byType(ExpenseDateSheet), matching: finder);

Finder _chip(String label) => find.widgetWithText(AppChip, label);

Future<(ShellHarness, String)> _start(
  WidgetTester tester, {
  DateTime? now,
  Size size = const Size(360, 800),
  double scale = 1,
}) async {
  await loadTestFonts();
  if (scale != 1) {
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
  }
  final db = openTestDatabase();
  final budgetId = (await tester.runAsync(() => seedMockupOctober(db)))!;
  final h = await ShellHarness.start(tester, db: db, now: now, size: size);
  await h.tapPlus();
  return (h, budgetId);
}

Future<void> _openSheet(WidgetTester tester, String chipLabel) async {
  final chip = inNewExpense(_chip(chipLabel));
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pumpAndSettle();
  expect(find.byType(ExpenseDateSheet), findsOneWidget);
}

Future<void> _tapInSheet(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _done(WidgetTester tester) =>
    _tapInSheet(tester, _inSheet(find.text('Готово')));

SemanticsNode _node(WidgetTester tester, String label) =>
    tester.getSemantics(find.bySemanticsLabel(label));

bool _tappable(SemanticsNode node) =>
    node.getSemanticsData().hasAction(SemanticsAction.tap);

bool _selected(AppChip chip) => chip.selected;

void main() {
  test('быстрые даты: сегодня, вчера и позавчера от «сегодня» через границу '
      'месяца и года', () {
    final today = LocalDate(2027, 1, 1);
    expect(quickExpenseDate(QuickExpenseDate.today, today), today);
    expect(
      quickExpenseDate(QuickExpenseDate.yesterday, today),
      LocalDate(2026, 12, 31),
    );
    expect(
      quickExpenseDate(QuickExpenseDate.dayBefore, today),
      LocalDate(2026, 12, 30),
    );
  });

  test('высота строки календаря 36 при шрифте 1.0 и растёт с крупным '
      'шрифтом', () {
    expect(expenseDateDayHeightFor(TextScaler.noScaling), 36);
    expect(expenseDateDayHeightFor(const TextScaler.linear(2)), 54);
  });

  testWidgets('будущие дни недоступны: 20–31 октября «будет» без действия, тап '
      'по 25 не меняет выбор, › неактивна на октябре; ‹ → сентябрь, все дни '
      'доступны, › → октябрь, дальше нельзя', (tester) async {
    await _start(tester);
    await _openSheet(tester, 'Сегодня, 19 окт');

    expect(_inSheet(find.text('Дата траты')), findsOneWidget);
    expect(_inSheet(find.text('Октябрь 2026')), findsOneWidget);
    final today = _node(tester, '19 октября, сегодня, выбран');
    expect(_tappable(today), isTrue);
    for (var day = 20; day <= 31; day++) {
      expect(
        _node(tester, '$day октября, будет'),
        isSemantics(
          isEnabled: false,
          hasEnabledState: true,
          hasTapAction: false,
        ),
        reason: '$day октября',
      );
    }

    await _tapInSheet(tester, _inSheet(find.text('25')));
    expect(
      find.bySemanticsLabel('19 октября, сегодня, выбран'),
      findsOneWidget,
    );

    final next = _node(tester, 'Следующий месяц');
    expect(_tappable(next), isFalse);
    await _tapInSheet(tester, find.bySemanticsLabel('Следующий месяц'));
    expect(_inSheet(find.text('Октябрь 2026')), findsOneWidget);

    await _tapInSheet(tester, find.bySemanticsLabel('Предыдущий месяц'));
    expect(_inSheet(find.text('Сентябрь 2026')), findsOneWidget);
    for (var day = 1; day <= 30; day++) {
      expect(
        _tappable(_node(tester, '$day сентября')),
        isTrue,
        reason: '$day сентября',
      );
    }
    expect(_tappable(_node(tester, 'Следующий месяц')), isTrue);
    await _tapInSheet(tester, find.bySemanticsLabel('Следующий месяц'));
    expect(_inSheet(find.text('Октябрь 2026')), findsOneWidget);
    expect(_tappable(_node(tester, 'Следующий месяц')), isFalse);

    await _done(tester);
    expect(find.byType(ExpenseDateSheet), findsNothing);
    expect(inNewExpense(_chip('Сегодня, 19 окт')), findsOneWidget);
  });

  testWidgets('«Вчера» ставит 18 октября: чип «Вчера» выбран, 18 выделено, '
      '«Готово» → чип «Вчера, 18 окт», трата сохраняется на 18 октября, '
      'выбор даты в debug-логе', (tester) async {
    final (h, budgetId) = await _start(tester);
    await _openSheet(tester, 'Сегодня, 19 окт');

    expect(
      _selected(tester.widget<AppChip>(_inSheet(_chip('Сегодня')))),
      isTrue,
    );
    await _tapInSheet(tester, _inSheet(_chip('Вчера')));
    expect(_selected(tester.widget<AppChip>(_inSheet(_chip('Вчера')))), isTrue);
    expect(
      _selected(tester.widget<AppChip>(_inSheet(_chip('Сегодня')))),
      isFalse,
    );
    expect(find.bySemanticsLabel('18 октября, выбран'), findsOneWidget);
    expect(find.bySemanticsLabel('19 октября, сегодня'), findsOneWidget);

    await _done(tester);
    expect(inNewExpense(_chip('Вчера, 18 окт')), findsOneWidget);

    final before = await allExpenses(
      tester,
      h.db,
      budgetId,
      LocalDate(2026, 10, 18),
    );
    await typeKeys(tester, '250');
    await tapCategory(tester, 'Кафе');
    expect(find.byType(NewExpenseScreen), findsNothing);
    final after = await allExpenses(
      tester,
      h.db,
      budgetId,
      LocalDate(2026, 10, 18),
    );
    expect(after, hasLength(before.length + 1));
    final saved = after.firstWhere((e) => !before.any((b) => b.id == e.id));
    expect(saved.spentOn, LocalDate(2026, 10, 18));
    expect(saved.amount, const Money.rubles(250));

    final debug = [
      for (final r in h.records)
        if (r.loggerName == 'expense' && r.level == Level.FINE) r.message,
    ];
    expect(debug, contains('date sheet opened initial=2026-10-19'));
    expect(
      debug,
      contains('date sheet selected 2026-10-19 → 2026-10-18 by=yesterday'),
    );
    expect(
      debug,
      contains(matches(r'^date sheet done date=2026-10-18 after \d+ms$')),
    );
    expect(
      debug,
      contains('expense date 2026-10-19 → 2026-10-18 by=date sheet'),
    );
  });

  testWidgets('«Позавчера» → чип «17 окт», трата на 17 октября видна в '
      'календаре и в шторке дня', (tester) async {
    final (h, budgetId) = await _start(tester);
    final day = LocalDate(2026, 10, 17);
    final before = await allExpenses(tester, h.db, budgetId, day);
    final total = Money.sum([for (final e in before) e.amount]);

    await _openSheet(tester, 'Сегодня, 19 окт');
    await _tapInSheet(tester, _inSheet(_chip('Позавчера')));
    expect(find.bySemanticsLabel('17 октября, выбран'), findsOneWidget);
    await _done(tester);
    expect(inNewExpense(_chip('17 окт')), findsOneWidget);

    await typeKeys(tester, '300');
    await tapCategory(tester, 'Продукты');
    final after = await allExpenses(tester, h.db, budgetId, day);
    expect(after, hasLength(before.length + 1));
    expect(
      find.bySemanticsLabel(
        RegExp(
          '^17 октября, потрачено '
          '${groupDigits((total + const Money.rubles(300)).roundedRubles)}',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('день из календаря прошлого месяца: ‹ → 12 сентября → «Готово» '
      '→ чип «12 сент», трата на 12 сентября', (tester) async {
    final (h, budgetId) = await _start(tester);
    await _openSheet(tester, 'Сегодня, 19 окт');
    await _tapInSheet(tester, find.bySemanticsLabel('Предыдущий месяц'));
    await _tapInSheet(tester, find.bySemanticsLabel('12 сентября'));
    expect(find.bySemanticsLabel('12 сентября, выбран'), findsOneWidget);
    for (final label in ['Сегодня', 'Вчера', 'Позавчера']) {
      expect(
        _selected(tester.widget<AppChip>(_inSheet(_chip(label)))),
        isFalse,
      );
    }
    await _done(tester);
    expect(inNewExpense(_chip('12 сент')), findsOneWidget);

    await typeKeys(tester, '99');
    await tapCategory(tester, 'Транспорт');
    final saved = await allExpenses(
      tester,
      h.db,
      budgetId,
      LocalDate(2026, 9, 12),
    );
    expect(
      saved.where((e) => e.amount == const Money.rubles(99)),
      hasLength(1),
    );
  });

  testWidgets('выбор без «Готово»: «Позавчера», затем «назад» — шторка '
      'закрыта, дата остаётся сегодняшней, в логе закрытие без выбора', (
    tester,
  ) async {
    final (h, _) = await _start(tester);
    await _openSheet(tester, 'Сегодня, 19 окт');
    await _tapInSheet(tester, _inSheet(_chip('Позавчера')));
    await h.systemBack();

    expect(find.byType(ExpenseDateSheet), findsNothing);
    expect(find.byType(NewExpenseScreen), findsOneWidget);
    expect(inNewExpense(_chip('Сегодня, 19 окт')), findsOneWidget);
    expect(
      h.records.map((r) => r.message),
      contains(
        matches(
          r'^date sheet closed without choice after \d+ms: back gesture, tap '
          r'outside or swipe down, date stays 2026-10-19$',
        ),
      ),
    );
  });

  testWidgets('1 ноября: «Вчера» — 31 октября, календарь листается на октябрь; '
      'шторка открывается с выбранной датой', (tester) async {
    await _start(tester, now: DateTime(2026, 11, 1, 9));
    await _openSheet(tester, 'Сегодня, 1 нояб');
    expect(_inSheet(find.text('Ноябрь 2026')), findsOneWidget);
    await _tapInSheet(tester, _inSheet(_chip('Вчера')));
    expect(_inSheet(find.text('Октябрь 2026')), findsOneWidget);
    expect(find.bySemanticsLabel('31 октября, выбран'), findsOneWidget);
    await _done(tester);
    expect(inNewExpense(_chip('Вчера, 31 окт')), findsOneWidget);

    await _openSheet(tester, 'Вчера, 31 окт');
    expect(_inSheet(find.text('Октябрь 2026')), findsOneWidget);
    expect(find.bySemanticsLabel('31 октября, выбран'), findsOneWidget);
  });

  testWidgets('контроллер не ставит будущую дату: warn и дата прежняя', (
    tester,
  ) async {
    final records = <LogRecord>[];
    final previous = Logger.root.level;
    Logger.root.level = Level.ALL;
    final sub = Logger.root.onRecord.listen(records.add);
    addTearDown(() async {
      await sub.cancel();
      Logger.root.level = previous;
    });
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(openTestDatabase()),
        clockProvider.overrideWithValue(Clock(now: () => testNow)),
      ],
    );
    addTearDown(container.dispose);
    final provider = newExpenseControllerProvider(null);
    final sub2 = container.listen(provider, (_, _) {});
    addTearDown(sub2.close);
    final controller = container.read(provider.notifier);

    expect(controller.setDate(LocalDate(2026, 10, 20), by: 'test'), isFalse);
    expect(container.read(provider).date, LocalDate(2026, 10, 19));
    expect(
      records.where((r) => r.level == Level.WARNING).map((r) => r.message),
      contains(
        'expense date 2026-10-20 by=test rejected: future day '
        'today=2026-10-19, keeping 2026-10-19',
      ),
    );
    expect(controller.setDate(LocalDate(2026, 10, 1), by: 'test'), isTrue);
    expect(container.read(provider).date, LocalDate(2026, 10, 1));
  });

  for (final (width, scale) in const [
    (360.0, 1.0),
    (320.0, 1.0),
    (360.0, 2.0),
    (320.0, 2.0),
  ]) {
    testWidgets('$width dp, шрифт $scale: шторка без переполнений, числа '
        'не обрезаны и внутри своих ячеек, ‹ › нажимаются в 48 × 48 и не '
        'заходят друг на друга, ячейки дней не перекрываются, «Готово» '
        'достижима прокруткой', (tester) async {
      await _start(tester, size: Size(width, 800), scale: scale);
      await _openSheet(tester, 'Сегодня, 19 окт');
      expect(tester.takeException(), isNull);

      final sheet = tester.getRect(find.byType(ExpenseDateSheet));
      for (var day = 1; day <= 31; day++) {
        final text = _inSheet(find.text('$day'));
        expect(text, findsOneWidget, reason: '$day');
        final paragraph = tester.renderObject<RenderParagraph>(text);
        expect(paragraph.didExceedMaxLines, isFalse, reason: '$day');
        final textRect = tester.getRect(text);
        expect(textRect.left, greaterThanOrEqualTo(sheet.left));
        expect(textRect.right, lessThanOrEqualTo(sheet.right));
      }

      final areas = <Rect>[];
      for (var day = 1; day <= 19; day++) {
        areas.add(
          tester.getRect(
            find
                .ancestor(
                  of: _inSheet(find.text('$day')),
                  matching: find.byType(GestureDetector),
                )
                .first,
          ),
        );
      }
      for (var i = 0; i < areas.length; i++) {
        for (var j = i + 1; j < areas.length; j++) {
          expect(
            areas[i].intersect(areas[j]).width > 0.01 &&
                areas[i].intersect(areas[j]).height > 0.01,
            isFalse,
            reason: '${areas[i]} ∩ ${areas[j]}',
          );
        }
      }

      final previous = tester.getRect(
        find.bySemanticsLabel('Предыдущий месяц'),
      );
      final next = tester.getRect(find.bySemanticsLabel('Следующий месяц'));
      for (final r in [previous, next]) {
        expect(r.width, greaterThanOrEqualTo(kMinTapTarget));
        expect(r.height, greaterThanOrEqualTo(kMinTapTarget));
      }
      expect(previous.overlaps(next), isFalse);

      await _tapInSheet(tester, find.bySemanticsLabel('1 октября'));
      await _done(tester);
      expect(find.byType(ExpenseDateSheet), findsNothing);
      expect(tester.takeException(), isNull);
      expect(inNewExpense(_chip('1 окт')), findsOneWidget);
    });
  }
}
