import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:milionchik/core/router.dart';
import 'package:milionchik/features/month/month_screen.dart';
import 'package:milionchik/features/expense/new_expense_screen.dart';
import 'package:milionchik/features/shell/tab_stub_screen.dart';
import 'package:milionchik/ui/components/bottom_nav.dart';
import 'package:milionchik/ui/components/fab.dart';

import 'shell_harness.dart';

void main() {
  final title = find.text('Новая трата');

  String location(WidgetTester tester) => GoRouter.of(
    tester.element(find.byType(AppBottomNav, skipOffstage: false)),
  ).state.uri.path;

  testWidgets('«+» открывает «Новую трату» на весь экран без меню', (
    tester,
  ) async {
    final h = await ShellHarness.start(tester);

    await h.tapPlus();

    expect(find.byType(NewExpenseScreen), findsOneWidget);
    expect(title, findsOneWidget);
    expect(find.bySemanticsLabel('Закрыть'), findsOneWidget);
    expect(find.byType(AppBottomNav), findsNothing);
    expect(location(tester), AppRoutes.newExpense);
    expect(tester.getRect(find.byType(NewExpenseScreen)).top, 0);
  });

  testWidgets(
    'верх «+» над меню открывает «Новую трату», угол мимо круга — нет',
    (tester) async {
      await ShellHarness.start(tester);
      final fab = tester.getRect(find.byType(AppFab));
      final nav = tester.getRect(find.byType(AppBottomNav));
      expect(fab.top, lessThan(nav.top));

      await tester.tapAt(fab.topLeft + const Offset(3, 3));
      await tester.pumpAndSettle();
      expect(find.byType(NewExpenseScreen), findsNothing);

      await tester.tapAt(Offset(fab.center.dx, fab.top + 4));
      await tester.pumpAndSettle();
      expect(find.byType(NewExpenseScreen), findsOneWidget);
    },
  );

  testWidgets('«Новая трата» въезжает снизу вверх', (tester) async {
    final h = await ShellHarness.start(tester);

    await tester.tap(find.byType(AppFab));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    final start = tester.getRect(find.byType(NewExpenseScreen)).top;
    await tester.pump(newExpenseTransition ~/ 2);
    final middle = tester.getRect(find.byType(NewExpenseScreen)).top;
    await tester.pumpAndSettle();
    final end = tester.getRect(find.byType(NewExpenseScreen)).top;

    expect(start, greaterThan(700));
    expect(middle, inExclusiveRange(0, start));
    expect(end, 0);
    expect(h.navDebug(), contains('new expense open from tab=month'));
  });

  testWidgets('без анимаций в системе — сразу на месте', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await ShellHarness.start(tester);

    await tester.tap(find.byType(AppFab));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    expect(tester.getRect(find.byType(NewExpenseScreen)).top, 0);
  });

  testWidgets('крестик закрывает и возвращает на ту же вкладку', (
    tester,
  ) async {
    final h = await ShellHarness.start(tester);
    await h.tapTab('Статистика');

    await h.tapPlus();
    await tester.tap(find.bySemanticsLabel('Закрыть'));
    await tester.pumpAndSettle();

    expect(find.byType(NewExpenseScreen), findsNothing);
    expect(h.activeTab, AppNavTab.stats);
    expect(find.byType(TabStubScreen), findsOneWidget);
    expect(location(tester), AppRoutes.stats);
    expect(
      h.navDebug(),
      containsAllInOrder([
        'new expense open from tab=stats',
        'new expense closed by close button',
      ]),
    );
    expect(h.systemPops, 0);
  });

  testWidgets('системное «назад» закрывает «Новую трату», а не приложение', (
    tester,
  ) async {
    final h = await ShellHarness.start(tester);

    await h.tapPlus();
    expect(h.frameworkHandlesBack, isTrue);
    await h.systemBack();

    expect(find.byType(NewExpenseScreen), findsNothing);
    expect(find.byType(MonthScreen), findsOneWidget);
    expect(h.activeTab, AppNavTab.month);
    expect(h.systemPops, 0);
    expect(h.navDebug(), contains('new expense closed by back'));
  });

  testWidgets('жест «назад» (predictive back) закрывает «Новую трату»', (
    tester,
  ) async {
    final h = await ShellHarness.start(tester);
    await h.tapTab('Профиль');

    await h.tapPlus();
    await h.predictiveBackGesture();

    expect(find.byType(NewExpenseScreen), findsNothing);
    expect(h.activeTab, AppNavTab.profile);
    expect(h.systemPops, 0);
    expect(h.navDebug(), contains('new expense closed by back'));
  });
}
