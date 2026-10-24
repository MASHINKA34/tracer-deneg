import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/router.dart';
import 'package:milionchik/features/budgets/budget_switcher_sheet.dart';
import 'package:milionchik/features/month/month_header.dart';
import 'package:milionchik/features/month/month_screen.dart';
import 'package:milionchik/features/profile/profile_screen.dart';
import 'package:milionchik/features/search/search_screen.dart';
import 'package:milionchik/ui/components/avatar.dart';
import 'package:milionchik/ui/components/bottom_nav.dart';
import 'package:milionchik/ui/icons/app_icon.dart';

import '../../support/app_scope.dart';
import '../shell/shell_harness.dart';

Finder _inHeader(Finder finder) =>
    find.descendant(of: find.byType(MonthHeaderView), matching: finder);

Finder _icon(AppIcons icon) =>
    _inHeader(find.byWidgetPredicate((w) => w is AppIcon && w.icon == icon));

Iterable<String> _monthDebug(ShellHarness h) => h.records
    .where((r) => r.loggerName == 'month' && r.level == Level.FINE)
    .map((r) => r.message);

void main() {
  testWidgets('название и эмодзи бюджета из базы, буква аватара из названия, '
      'переименование сразу видно в шапке', (tester) async {
    final db = openTestDatabase();
    final budgets = testBudgets(db);
    final personal = await budgets.createLocalPersonal();
    final h = await ShellHarness.start(tester, db: db);

    expect(_inHeader(find.text('Личный бюджет')), findsOneWidget);
    expect(_inHeader(find.text('👛')), findsOneWidget);
    expect(
      find.descendant(of: find.byType(AppAvatar), matching: find.text('Л')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Личный бюджет, выбрать бюджет'), findsOne);
    expect(
      _monthDebug(h),
      contains('header budget shown budgetId=${personal.id} kind=personal'),
    );

    await budgets.update(personal.id, name: 'семья', emoji: '🏠');
    await tester.pumpAndSettle();

    expect(_inHeader(find.text('семья')), findsOneWidget);
    expect(_inHeader(find.text('🏠')), findsOneWidget);
    expect(_inHeader(find.text('Личный бюджет')), findsNothing);
    expect(
      find.descendant(of: find.byType(AppAvatar), matching: find.text('С')),
      findsOneWidget,
    );
  });

  testWidgets('шапка как на 7:7: под статус-баром 32, высота 52, плашка '
      '12/8, справа поиск 22, облако 20 и аватар 32 до поля 16', (
    tester,
  ) async {
    final db = openTestDatabase();
    await testBudgets(db).createLocalPersonal();
    await ShellHarness.start(tester, db: db, topInset: 32);

    final header = tester.getRect(find.byType(MonthHeaderView));
    expect(header.top, 32);
    expect(header.height, 52);
    expect(header.width, 360);

    final pill = tester.getRect(
      find
          .ancestor(
            of: _inHeader(find.text('Личный бюджет')),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(pill.left, 12);
    expect(pill.top, 32 + 8);
    expect(pill.height, 36);

    expect(
      tester.getRect(_icon(AppIcons.search)),
      const Rect.fromLTWH(241, 47, 22, 22),
    );
    expect(
      tester.getRect(_icon(AppIcons.cloudCheck)),
      const Rect.fromLTWH(280, 48, 20, 20),
    );
    expect(
      tester.getRect(find.byType(AppAvatar)),
      const Rect.fromLTWH(312, 42, 32, 32),
    );
    expect(tester.getSize(_icon(AppIcons.chevronDown)), const Size(16, 16));
    expect(find.bySemanticsLabel('Синхронизировано'), findsOneWidget);
  });

  testWidgets('иконка поиска открывает заглушку /search без меню, стрелка и '
      'системное «назад» возвращают на «Месяц»', (tester) async {
    final db = openTestDatabase();
    await testBudgets(db).createLocalPersonal();
    final h = await ShellHarness.start(tester, db: db);

    await tester.tap(_icon(AppIcons.search));
    await tester.pumpAndSettle();

    expect(find.byType(SearchScreen), findsOneWidget);
    expect(find.text('Поиск'), findsOneWidget);
    expect(find.byType(AppBottomNav), findsNothing);
    final router = GoRouter.of(tester.element(find.byType(SearchScreen)));
    expect(router.state.uri.path, AppRoutes.search);
    expect(_monthDebug(h), contains('header search tap → /search'));

    await tester.tap(find.bySemanticsLabel('Назад'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchScreen), findsNothing);
    expect(find.byType(MonthScreen), findsOneWidget);
    expect(h.activeTab, AppNavTab.month);
    expect(router.state.uri.path, AppRoutes.month);

    await tester.tap(_icon(AppIcons.search));
    await tester.pumpAndSettle();
    await h.systemBack();
    expect(find.byType(SearchScreen), findsNothing);
    expect(find.byType(MonthScreen), findsOneWidget);
    expect(h.systemPops, 0);
    expect(
      h.navDebug(),
      containsAllInOrder([
        'search closed by back button',
        'search closed by back',
      ]),
    );
  });

  testWidgets('аватар ведёт на вкладку «Профиль» с подсветкой в меню, '
      '«назад» с профиля — снова «Месяц»', (tester) async {
    final db = openTestDatabase();
    await testBudgets(db).createLocalPersonal();
    final h = await ShellHarness.start(tester, db: db);

    await tester.tap(find.byType(AppAvatar));
    await tester.pumpAndSettle();

    expect(h.activeTab, AppNavTab.profile);
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(find.byType(MonthHeaderView), findsNothing);
    expect(
      _monthDebug(h),
      contains('header avatar tap → profile tab (/profile)'),
    );

    await h.systemBack();
    expect(h.activeTab, AppNavTab.month);
    expect(find.byType(MonthHeaderView), findsOneWidget);
  });

  testWidgets('тап по названию бюджета открывает шторку бюджетов, нажатие в '
      'debug-логе month', (tester) async {
    final db = openTestDatabase();
    final personal = await testBudgets(db).createLocalPersonal();
    final h = await ShellHarness.start(tester, db: db);

    await tester.tap(_inHeader(find.text('Личный бюджет')));
    await tester.pumpAndSettle();

    expect(find.byType(MonthScreen), findsOneWidget);
    expect(find.byType(BudgetSheet), findsOneWidget);
    expect(h.activeTab, AppNavTab.month);
    expect(
      _monthDebug(h),
      contains('header budget tap budgetId=${personal.id} → switcher'),
    );
  });

  testWidgets('в базе нет бюджета: плашки нет, поиск, статус и аватар на '
      'месте и работают', (tester) async {
    final h = await ShellHarness.start(tester);

    expect(_inHeader(find.byType(Text)), findsOneWidget);
    expect(_icon(AppIcons.chevronDown), findsNothing);
    expect(_icon(AppIcons.search), findsOneWidget);
    expect(_icon(AppIcons.cloudCheck), findsOneWidget);
    expect(find.byType(AppAvatar), findsOneWidget);
    expect(
      _monthDebug(h),
      contains('header without budget: no budget selected'),
    );

    await tester.tap(find.byType(AppAvatar));
    await tester.pumpAndSettle();
    expect(h.activeTab, AppNavTab.profile);
  });

  testWidgets('шрифт 2.0 на 320 dp: название усекается многоточием, иконки '
      'своего размера и в пределах экрана, без переполнений', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    final db = openTestDatabase();
    await testBudgets(db).createLocalPersonal();
    await ShellHarness.start(tester, db: db, size: const Size(320, 800));

    expect(tester.takeException(), isNull);
    final name = tester.renderObject<RenderParagraph>(
      _inHeader(find.text('Личный бюджет')),
    );
    expect(name.didExceedMaxLines, isTrue);

    final search = tester.getRect(_icon(AppIcons.search));
    final cloud = tester.getRect(_icon(AppIcons.cloudCheck));
    final avatar = tester.getRect(find.byType(AppAvatar));
    final chevron = tester.getRect(_icon(AppIcons.chevronDown));
    expect(search.size, const Size(22, 22));
    expect(cloud.size, const Size(20, 20));
    expect(avatar.size, const Size(32, 32));
    expect(chevron.size, const Size(16, 16));
    expect(avatar.right, 320 - 16);
    expect(cloud.right, avatar.left - 12);
    expect(search.right + 5, cloud.left - 12);
    expect(chevron.right, lessThan(search.left));
    final header = tester.getRect(find.byType(MonthHeaderView));
    for (final r in [search, cloud, avatar, chevron]) {
      expect(header.contains(r.center), isTrue);
    }
  });
}
