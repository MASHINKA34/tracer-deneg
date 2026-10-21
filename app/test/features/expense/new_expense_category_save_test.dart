import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/router.dart';
import 'package:milionchik/features/expense/category_grid.dart';
import 'package:milionchik/features/expense/new_expense_screen.dart';
import 'package:milionchik/features/month/day_sheet.dart';
import 'package:milionchik/features/month/today_block.dart';
import 'package:milionchik/features/shell/categories_stub_screen.dart';
import 'package:milionchik/ui/components/category_tile.dart';
import 'package:milionchik/ui/components/snackbar.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';
import '../month/month_fixture.dart';
import '../shell/shell_harness.dart';
import 'new_expense_harness.dart';

final LocalDate _today = LocalDate(2026, 10, 19);

Future<(ShellHarness, String)> _start(WidgetTester tester) async {
  final db = openTestDatabase();
  final budgetId = (await tester.runAsync(() => seedMockupOctober(db)))!;
  final h = await ShellHarness.start(tester, db: db);
  return (h, budgetId);
}

List<String> _gridNames(WidgetTester tester, Finder scope) {
  final tiles = find.descendant(of: scope, matching: find.byType(CategoryTile));
  final entries =
      [
        for (final element in tiles.evaluate())
          (
            tester.getTopLeft(find.byWidget(element.widget)),
            (element.widget as CategoryTile).name,
          ),
      ]..sort((a, b) {
        final dy = a.$1.dy.compareTo(b.$1.dy);
        return dy != 0 ? dy : a.$1.dx.compareTo(b.$1.dx);
      });
  return [for (final e in entries) e.$2];
}

String _location(WidgetTester tester) =>
    GoRouter.of(tester.element(find.byType(Navigator).first)).state.uri
        .toString();

void main() {
  testWidgets('сетка — первые 7 категорий бюджета по порядку и «Все» в '
      'конце, «Другое» и остальные — только в шторке', (tester) async {
    final (h, _) = await _start(tester);
    await h.tapPlus();

    expect(_gridNames(tester, find.byType(NewExpenseScreen)), [
      'Продукты',
      'Кафе',
      'Транспорт',
      'Дом',
      'Здоровье',
      'Спорт',
      'Развлечения',
      'Все',
    ]);
    final all = tester.widget<CategoryTile>(categoryTile('Все'));
    expect(all.emoji, allCategoriesEmoji);
    expect(all.color, isNull);
    expect(
      inNewExpense(find.text('Нажми на категорию — и трата сохранится')),
      findsOneWidget,
    );
  });

  testWidgets('«+» → 643 → «Кафе»: трата на сегодня в личном бюджете, лёгкая '
      'вибрация, экран закрылся, трата сразу на карточке и в «Сегодня»', (
    tester,
  ) async {
    final (h, budgetId) = await _start(tester);
    final before = await allExpenses(tester, h.db, budgetId, _today);
    final total = Money.sum([for (final e in before) e.amount]);
    final categories = await budgetCategories(tester, h.db, budgetId);
    final cafe = categories.firstWhere((c) => c.name == 'Кафе');

    await h.tapPlus();
    await typeKeys(tester, '643');
    final haptics = hapticCount(h.platformCalls);
    await tapCategory(tester, 'Кафе');

    expect(find.byType(NewExpenseScreen), findsNothing);
    expect(hapticCount(h.platformCalls) - haptics, 1);
    final after = await allExpenses(tester, h.db, budgetId, _today);
    expect(after, hasLength(before.length + 1));
    final saved = after.firstWhere((e) => !before.any((b) => b.id == e.id));
    expect(saved.amount, const Money.rubles(643));
    expect(saved.categoryId, cafe.id);
    expect(saved.spentOn, _today);
    expect(saved.budgetId, budgetId);
    expect(saved.comment, '');

    final newTotal = total + const Money.rubles(643);
    expect(
      find.bySemanticsLabel(
        RegExp('^19 октября, потрачено ${groupDigits(newTotal.roundedRubles)}'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(TodayBlock),
        matching: find.text('643$nbspace₽'),
      ),
      findsOneWidget,
    );
    expect(h.navDebug(), contains('new expense closed by save'));
    expect(h.systemPops, 0);
  });

  testWidgets('шторка дня → «Добавить трату в этот день» → 250 → «Продукты»: '
      'трата на 17 октября, назад к шторке с тремя тратами', (tester) async {
    final (h, budgetId) = await _start(tester);
    final day = LocalDate(2026, 10, 17);
    final before = await allExpenses(tester, h.db, budgetId, day);
    expect(before, hasLength(2));

    await tester.tap(find.bySemanticsLabel(RegExp('^17 октября')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Добавить трату в этот день'));
    await tester.pumpAndSettle();
    expect(inNewExpense(find.text('17 окт')), findsOneWidget);
    await typeKeys(tester, '250');
    await tapCategory(tester, 'Продукты');

    expect(find.byType(NewExpenseScreen), findsNothing);
    expect(find.byType(DaySheet), findsOneWidget);
    final after = await allExpenses(tester, h.db, budgetId, day);
    expect(after, hasLength(3));
    expect(
      after.where((e) => e.amount == const Money.rubles(250)).single.spentOn,
      day,
    );
    expect(
      find.descendant(
        of: find.byType(DaySheet),
        matching: find.textContaining('3 траты'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('чип даты: сегодня «Сегодня, 19 окт», вчера «Вчера, 18 окт», '
      'раньше «17 окт», прошлый год «30 дек 2025»; будущая и кривая дата из '
      'маршрута — сегодня и warn', (tester) async {
    final (h, _) = await _start(tester);

    Future<void> open(String location, String chip) async {
      GoRouter.of(tester.element(find.byType(Navigator).first)).push(location);
      await tester.pumpAndSettle();
      expect(inNewExpense(find.text(chip)), findsOneWidget, reason: location);
      expect(inNewExpense(find.text('Комментарий')), findsOneWidget);
      await h.systemBack();
    }

    await open(AppRoutes.newExpense, 'Сегодня, 19 окт');
    await open(
      AppRoutes.newExpenseOn(LocalDate(2026, 10, 18)),
      'Вчера, 18 окт',
    );
    await open(AppRoutes.newExpenseOn(LocalDate(2026, 10, 17)), '17 окт');
    await open(AppRoutes.newExpenseOn(LocalDate(2025, 12, 30)), '30 дек 2025');
    await open(
      AppRoutes.newExpenseOn(LocalDate(2026, 10, 20)),
      'Сегодня, 19 окт',
    );
    await open('${AppRoutes.newExpense}?date=19.10.2026', 'Сегодня, 19 окт');

    final warnings = [
      for (final r in h.records)
        if (r.loggerName == 'expense' && r.level == Level.WARNING) r.message,
    ];
    expect(warnings, [
      'new expense date parameter "2026-10-20" ignored: future date, '
          'expenses are recorded by fact, using today=2026-10-19',
      'new expense date parameter "19.10.2026" ignored: not a yyyy-mm-dd '
          'date, using today=2026-10-19',
    ]);
    expect(
      h.records
          .where((r) => r.loggerName == 'expense' && r.level == Level.FINE)
          .map((r) => r.message),
      containsAllInOrder([
        'new expense opened date=2026-10-19 from=today today=2026-10-19',
        'new expense opened date=2026-10-18 from=route today=2026-10-19',
        'new expense opened date=2026-10-17 from=route today=2026-10-19',
        'new expense opened date=2025-12-30 from=route today=2026-10-19',
      ]),
    );
  });

  testWidgets('сумма 0: тап по категории встряхивает сумму, подсказка «Сначала '
      'введи сумму», ничего не сохранено, экран открыт; после цифры подсказка '
      'снова обычная, когда сумма больше нуля', (tester) async {
    final (h, budgetId) = await _start(tester);
    final before = await allExpenses(tester, h.db, budgetId, _today);
    await h.tapPlus();
    final haptics = hapticCount(h.platformCalls);

    await tester.tap(
      find.descendant(of: categoryTile('Кафе'), matching: find.byType(InkWell)),
    );
    await tester.pump();
    await tester.pump(amountShakeDuration ~/ 5);
    final shake = tester
        .widget<Transform>(
          find
              .ancestor(
                of: find.byKey(const ValueKey('new-expense-amount')),
                matching: find.byType(Transform),
              )
              .first,
        )
        .transform
        .getTranslation()
        .x;
    expect(shake.abs(), greaterThan(1));
    await tester.pumpAndSettle();

    expect(find.byType(NewExpenseScreen), findsOneWidget);
    expect(inNewExpense(find.text('Сначала введи сумму')), findsOneWidget);
    expect(
      inNewExpense(find.text('Нажми на категорию — и трата сохранится')),
      findsNothing,
    );
    expect(hapticCount(h.platformCalls), haptics);
    expect(await allExpenses(tester, h.db, budgetId, _today), before);
    expect(
      h.records.map((r) => r.message),
      contains(
        matches(
          r'^expense save category=\S+ rejected: amount is zero, nothing saved$',
        ),
      ),
    );

    await typeKeys(tester, '0,');
    expect(amountText(tester), '0,');
    expect(inNewExpense(find.text('Сначала введи сумму')), findsOneWidget);
    await typeKeys(tester, '5');
    expect(inNewExpense(find.text('Сначала введи сумму')), findsNothing);
    expect(
      inNewExpense(find.text('Нажми на категорию — и трата сохранится')),
      findsOneWidget,
    );
    await tester.longPress(keypadKey('Стереть'));
    await tester.pumpAndSettle();
    await tapCategory(tester, 'Кафе');
    expect(inNewExpense(find.text('Сначала введи сумму')), findsOneWidget);
    expect(await allExpenses(tester, h.db, budgetId, _today), before);
  });

  testWidgets('«Все» — шторка со всеми 11 категориями бюджета, тап по '
      '«Подаркам» сохраняет трату и закрывает шторку и экран', (tester) async {
    final (h, budgetId) = await _start(tester);
    final before = await allExpenses(tester, h.db, budgetId, _today);
    await h.tapPlus();
    await typeKeys(tester, '99,5');

    await tapCategory(tester, 'Все');
    expect(find.byType(AllCategoriesSheet), findsOneWidget);
    expect(find.text('Все категории'), findsOneWidget);
    expect(_gridNames(tester, find.byType(AllCategoriesSheet)), [
      'Продукты',
      'Кафе',
      'Транспорт',
      'Дом',
      'Здоровье',
      'Спорт',
      'Развлечения',
      'Одежда',
      'Связь',
      'Подарки',
      'Другое',
    ]);

    final gifts = find.descendant(
      of: find.byType(AllCategoriesSheet),
      matching: find.widgetWithText(CategoryTile, 'Подарки'),
    );
    await tester.ensureVisible(gifts);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: gifts, matching: find.byType(InkWell)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AllCategoriesSheet), findsNothing);
    expect(find.byType(NewExpenseScreen), findsNothing);
    final after = await allExpenses(tester, h.db, budgetId, _today);
    final saved = after.firstWhere((e) => !before.any((b) => b.id == e.id));
    expect(saved.amount, const Money.rubles(99, 50));
    final categories = await budgetCategories(tester, h.db, budgetId);
    expect(
      saved.categoryId,
      categories.firstWhere((c) => c.name == 'Подарки').id,
    );
  });

  testWidgets('«Все» при сумме 0: выбор в шторке — подсказка, ничего не '
      'сохранено; шторка закрывается «назад» без выбора', (tester) async {
    final (h, budgetId) = await _start(tester);
    final before = await allExpenses(tester, h.db, budgetId, _today);
    await h.tapPlus();

    await tapCategory(tester, 'Все');
    await h.systemBack();
    expect(find.byType(AllCategoriesSheet), findsNothing);
    expect(find.byType(NewExpenseScreen), findsOneWidget);

    await tapCategory(tester, 'Все');
    final other = find.descendant(
      of: find.byType(AllCategoriesSheet),
      matching: find.widgetWithText(CategoryTile, 'Другое'),
    );
    await tester.ensureVisible(other);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: other, matching: find.byType(InkWell)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AllCategoriesSheet), findsNothing);
    expect(inNewExpense(find.text('Сначала введи сумму')), findsOneWidget);
    expect(await allExpenses(tester, h.db, budgetId, _today), before);
  });

  testWidgets('«Настроить» над сеткой и в шторке «Все» открывает /categories '
      '(заглушка «Категории»), «назад» возвращает к введённой сумме', (
    tester,
  ) async {
    final (h, _) = await _start(tester);
    await h.tapPlus();
    await typeKeys(tester, '1250');

    await tester.tap(inNewExpense(find.text('Настроить')));
    await tester.pumpAndSettle();
    expect(find.byType(CategoriesStubScreen), findsOneWidget);
    expect(find.text('Категории'), findsOneWidget);
    expect(_location(tester), AppRoutes.categories);
    await h.systemBack();
    expect(find.byType(CategoriesStubScreen), findsNothing);
    expect(amountText(tester), '1${nbspace}250');

    await tapCategory(tester, 'Все');
    await tester.tap(
      find.descendant(
        of: find.byType(AllCategoriesSheet),
        matching: find.text('Настроить'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AllCategoriesSheet), findsNothing);
    expect(find.byType(CategoriesStubScreen), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Назад'));
    await tester.pumpAndSettle();
    expect(amountText(tester), '1${nbspace}250');
    expect(
      h.records.where((r) => r.loggerName == 'expense').map((r) => r.message),
      containsAllInOrder([
        'categories setup from=grid → /categories',
        'category tile «all» → sheet with 11 categories',
        'categories setup from=all sheet → /categories',
      ]),
    );
  });

  testWidgets('двойной тап по категории — одна трата', (tester) async {
    final (h, budgetId) = await _start(tester);
    final before = await allExpenses(tester, h.db, budgetId, _today);
    await h.tapPlus();
    await typeKeys(tester, '77');

    final ink = find.descendant(
      of: categoryTile('Дом'),
      matching: find.byType(InkWell),
    );
    await tester.tap(ink);
    await tester.tap(ink, warnIfMissed: false);
    await tester.pumpAndSettle();

    final after = await allExpenses(tester, h.db, budgetId, _today);
    expect(after.length, before.length + 1);
    expect(find.byType(NewExpenseScreen), findsNothing);
  });

  testWidgets('успех в логе: info [expense] с id, бюджетом, категорией, датой '
      'и мс без суммы; сумма — только на debug', (tester) async {
    final (h, budgetId) = await _start(tester);
    final categories = await budgetCategories(tester, h.db, budgetId);
    final transport = categories.firstWhere((c) => c.name == 'Транспорт');
    await h.tapPlus();
    await typeKeys(tester, '4321,5');
    await tapCategory(tester, 'Транспорт');

    final saved = (await allExpenses(
      tester,
      h.db,
      budgetId,
      _today,
    )).firstWhere((e) => e.amount == const Money(432150));
    final info = [
      for (final r in h.records)
        if (r.loggerName == 'expense' && r.level >= Level.INFO) r.message,
    ];
    expect(info, hasLength(1));
    expect(
      info.single,
      matches(
        '^expense saved id=${saved.id} budgetId=$budgetId '
        'category=${transport.id} date=2026-10-19 in \\d+ms\$',
      ),
    );
    for (final r in h.records.where((r) => r.level >= Level.INFO)) {
      expect(r.message, isNot(contains('4321')), reason: r.message);
      expect(r.message, isNot(contains('432150')), reason: r.message);
    }
    expect(
      h.records
          .where((r) => r.loggerName == 'expense' && r.level == Level.FINE)
          .map((r) => r.message),
      contains('expense saved id=${saved.id} amountKopecks=432150'),
    );
  });

  testWidgets('ошибка записи в базу: снекбар, экран и сумма остаются, error '
      '[expense] с бюджетом, категорией, датой и причиной без значений '
      'параметров SQL', (tester) async {
    final (h, budgetId) = await _start(tester);
    await tester.runAsync(
      () => h.db.customStatement(
        'CREATE TRIGGER expenses_fail BEFORE INSERT ON expenses '
        "BEGIN SELECT RAISE(ABORT, 'disk I/O error'); END",
      ),
    );
    final categories = await budgetCategories(tester, h.db, budgetId);
    final health = categories.firstWhere((c) => c.name == 'Здоровье');
    await h.tapPlus();
    await typeKeys(tester, '98765,43');
    await tapCategory(tester, 'Здоровье');

    expect(find.byType(NewExpenseScreen), findsOneWidget);
    expect(amountText(tester), '98${nbspace}765,43');
    expect(find.byType(AppSnackbar), findsOneWidget);
    expect(
      find.text('Не удалось сохранить трату. Попробуй ещё раз'),
      findsOneWidget,
    );

    final errors = [
      for (final r in h.records)
        if (r.loggerName == 'expense' && r.level == Level.SEVERE) r,
    ];
    expect(errors, hasLength(1));
    final error = errors.single;
    expect(
      error.message,
      matches(
        '^expense save failed budgetId=$budgetId category=${health.id} '
        'date=2026-10-19 after \\d+ms, nothing saved: SqliteException',
      ),
    );
    expect(error.message, contains('disk I/O error'));
    expect(error.message, contains('INSERT INTO "expenses"'));
    expect(error.stackTrace, isNotNull);
    for (final r in h.records.where((r) => r.level >= Level.INFO)) {
      final text = '${r.message} ${r.error}';
      expect(text, isNot(contains('9876543')), reason: text);
      expect(text, isNot(contains('98765')), reason: text);
    }

    await tester.runAsync(
      () => h.db.customStatement('DROP TRIGGER expenses_fail'),
    );
    await tapCategory(tester, 'Здоровье');
    expect(find.byType(NewExpenseScreen), findsNothing);
  });
}
