import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/app.dart';
import 'package:milionchik/core/router.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:milionchik/data/repositories/recurring_repository.dart';
import 'package:milionchik/data/current_user.dart';
import 'package:milionchik/data/repositories/outbox_queue.dart';
import 'package:milionchik/features/budgets/budget_switcher_sheet.dart';
import 'package:milionchik/features/export/export_screen.dart';
import 'package:milionchik/features/month/month_header.dart';
import 'package:milionchik/features/month/month_screen.dart';
import 'package:milionchik/features/profile/profile_budgets.dart';
import 'package:milionchik/features/recurring/recurring_screen.dart';
import 'package:milionchik/features/stats/stats_screen.dart';
import 'package:milionchik/ui/components/avatar.dart';
import 'package:milionchik/ui/components/chip.dart';
import 'package:milionchik/ui/components/month_card.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';
import '../auth/session_expired_fixture.dart' show testUnmounting;
import '../shell/shell_harness.dart';
import 'budget_switcher_fixture.dart';

final String _personalTotal = Money.rubles(18300).formatTotal();

final String _familyTotal = Money.rubles(41200).formatTotal();

Finder _row(String budgetId) => find.byWidgetPredicate(
  (w) => w is BudgetSheetRow && w.budget.id == budgetId,
);

Finder _inHeader(Finder finder) =>
    find.descendant(of: find.byType(MonthHeaderView), matching: finder);

Future<void> _openSwitcher(WidgetTester tester, String name) async {
  await tester.tap(find.bySemanticsLabel('$name, выбрать бюджет'));
  await tester.pumpAndSettle();
  expect(find.byType(BudgetSheet), findsOneWidget);
}

Future<String?> _storedChoice(ShellHarness h) => h.tester.runAsync<String?>(
  () => DriftPrefsRepository(h.db).getString(PrefKeys.selectedBudgetId),
);

Iterable<String> _budgetLogs(ShellHarness h, Level level) => h.records
    .where((r) => r.loggerName == 'budgets' && r.level == level)
    .map((r) => r.message);

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testUnmounting('шторка: личный и «Семья» с суммами за октябрь, у «Семьи» '
      'три аватара по порядку вступления, отметка у открытого', (tester) async {
    final db = openTestDatabase();
    final fixture = (await tester.runAsync(() => SwitcherFixture.mockup(db)))!;
    final h = await ShellHarness.start(tester, db: db);

    await _openSwitcher(tester, 'Личный бюджет');

    final personal = find.bySemanticsLabel(
      'Личный бюджет, Только ты$nbsp· $_personalTotal в октябре',
    );
    final family = find.bySemanticsLabel(
      'Семья, 3 участника$nbsp· $_familyTotal в октябре',
    );
    expect(personal, findsOneWidget);
    expect(family, findsOneWidget);
    expect(
      tester.getSemantics(personal),
      isSemantics(isButton: true, isSelected: true),
    );
    expect(
      tester.getSemantics(family),
      isSemantics(isButton: true, isSelected: false),
    );
    expect(
      [
        for (final a in tester.widgetList<AppAvatar>(
          find.descendant(of: _row(familyId), matching: find.byType(AppAvatar)),
        ))
          (a.letter, a.color),
      ],
      [
        ('А', CategoryColor.blue),
        ('Д', CategoryColor.green),
        ('М', CategoryColor.pink),
      ],
    );
    expect(
      find.descendant(
        of: _row(fixture.personalId),
        matching: find.byType(ProfileSelectedMark),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _row(familyId),
        matching: find.byType(ProfileSelectedMark),
      ),
      findsNothing,
    );
    expect(find.text('Создать общий бюджет'), findsOneWidget);
    expect(find.text('Войти по коду приглашения'), findsOneWidget);
    expect(
      _budgetLogs(h, Level.FINE),
      contains(
        'budget sheet opened for=switcher current=${fixture.personalId} '
        'actions=true',
      ),
    );
  });

  testUnmounting('выбор «Семьи»: шапка, главная, статистика, регулярные, '
      '«Новая трата» и экспорт берут общий бюджет; выбор в local_prefs, после '
      'перезапуска открыта «Семья»', (tester) async {
    final db = openTestDatabase();
    final fixture = (await tester.runAsync(() => SwitcherFixture.mockup(db)))!;
    await tester.runAsync(
      () =>
          DriftRecurringRepository(
            db,
            currentUser: LocalPrefsCurrentUser(DriftPrefsRepository(db)),
            outbox: DriftOutboxQueue(db),
          ).applyFromServer([
            RecurringRule(
              id: 'rule-family',
              budgetId: familyId,
              categoryId: fixture.familyCategories.first.id,
              title: 'Интернет',
              amount: Money.rubles(700),
              dayOfMonth: 25,
              startMonth: YearMonth(2026, 9),
              createdAt: testNow.toUtc(),
              updatedAt: testNow.toUtc(),
              updatedBy: familyOwnerId,
            ),
          ]),
    );
    final h = await ShellHarness.start(tester, db: db);
    expect(
      find.descendant(
        of: find.byType(MonthCard),
        matching: find.text(_personalTotal),
      ),
      findsOneWidget,
    );

    await _openSwitcher(tester, 'Личный бюджет');
    await tester.tap(_row(familyId));
    await tester.pumpAndSettle();

    expect(find.byType(BudgetSheet), findsNothing);
    expect(_inHeader(find.text('Семья')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(MonthCard),
        matching: find.text(_familyTotal),
      ),
      findsOneWidget,
    );
    expect(await _storedChoice(h), familyId);
    expect(
      _budgetLogs(h, Level.INFO),
      contains(
        matches(
          RegExp(
            'selected budget changed budgetId=$familyId '
            'from=${fixture.personalId} by=switcher in \\d+ms\$',
          ),
        ),
      ),
    );

    await h.tapTab('Статистика');
    expect(
      find.descendant(
        of: find.byType(StatsScreen),
        matching: find.text(_familyTotal),
      ),
      findsWidgets,
    );

    await h.tapTab('Регулярные');
    expect(
      find.descendant(
        of: find.byType(RecurringScreen),
        matching: find.text('Интернет'),
      ),
      findsOneWidget,
    );

    await h.tapTab('Месяц');
    await h.tapPlus();
    expect(find.widgetWithText(AppChip, 'Семья'), findsOneWidget);
    await h.systemBack();

    GoRouter.of(tester.element(find.byType(MonthScreen)))
        .push(AppRoutes.export);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(ExportScreen),
        matching: find.textContaining('Семья'),
      ),
      findsWidgets,
    );
    await h.systemBack();

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pumpWidget(
      withDatabase(db, MilionchikApp(today: LocalDate.fromDateTime(testNow))),
    );
    await tester.pumpAndSettle();

    expect(_inHeader(find.text('Семья')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(MonthCard),
        matching: find.text(_familyTotal),
      ),
      findsOneWidget,
    );
  });

  testUnmounting('тап по уже открытому бюджету ничего не меняет и не пишет '
      'выбор', (tester) async {
    final db = openTestDatabase();
    final fixture = (await tester.runAsync(() => SwitcherFixture.mockup(db)))!;
    final h = await ShellHarness.start(tester, db: db);

    await _openSwitcher(tester, 'Личный бюджет');
    await tester.tap(_row(fixture.personalId));
    await tester.pumpAndSettle();

    expect(find.byType(BudgetSheet), findsNothing);
    expect(await _storedChoice(h), isNull);
    expect(
      _budgetLogs(h, Level.FINE),
      contains(
        'budget switcher: budgetId=${fixture.personalId} is already open, '
        'nothing changes',
      ),
    );
  });

  for (final (label, choice) in const [
    ('Создать общий бюджет', 'create shared budget'),
    ('Войти по коду приглашения', 'join by invite code'),
  ]) {
    testUnmounting('«$label»: шторка закрыта, снекбар «Появится в следующем '
        'обновлении», открыт прежний бюджет', (tester) async {
      final db = openTestDatabase();
      await tester.runAsync(() => SwitcherFixture.mockup(db));
      final h = await ShellHarness.start(tester, db: db);

      await _openSwitcher(tester, 'Личный бюджет');
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();

      expect(find.byType(BudgetSheet), findsNothing);
      expect(find.text('Появится в следующем обновлении'), findsOneWidget);
      expect(_inHeader(find.text('Личный бюджет')), findsOneWidget);
      expect(await _storedChoice(h), isNull);
      expect(
        _budgetLogs(h, Level.FINE),
        contains('budget switcher: $choice is not available yet → snackbar'),
      );
    });
  }
}
