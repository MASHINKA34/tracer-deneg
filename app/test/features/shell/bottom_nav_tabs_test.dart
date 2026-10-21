import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/features/month/month_stub_screen.dart';
import 'package:milionchik/features/shell/tab_stub_screen.dart';
import 'package:milionchik/ui/components/bottom_nav.dart';
import 'package:milionchik/ui/catalog/catalog_screen.dart';
import 'package:milionchik/ui/components/fab.dart';
import 'package:milionchik/ui/components/logo.dart';

import 'shell_harness.dart';

void main() {
  Finder stubTitle(String title) => find.descendant(
    of: find.byType(TabStubScreen),
    matching: find.text(title),
  );

  testWidgets('старт на «Месяце»: заглушка и меню с активным «Месяцем»', (
    tester,
  ) async {
    final h = await ShellHarness.start(tester);

    expect(find.byType(MonthStubScreen), findsOneWidget);
    expect(find.byType(AppBottomNav), findsOneWidget);
    expect(h.activeTab, AppNavTab.month);
    expect(find.byType(AppFab), findsOneWidget);
  });

  testWidgets('тап по вкладкам переключает экран и подсветку', (tester) async {
    final h = await ShellHarness.start(tester);

    await h.tapTab('Статистика');
    expect(h.activeTab, AppNavTab.stats);
    expect(stubTitle('Статистика'), findsOneWidget);
    expect(find.byType(MonthStubScreen), findsNothing);

    await h.tapTab('Регулярные');
    expect(h.activeTab, AppNavTab.recurring);
    expect(stubTitle('Регулярные'), findsOneWidget);

    await h.tapTab('Профиль');
    expect(h.activeTab, AppNavTab.profile);
    expect(stubTitle('Профиль'), findsOneWidget);

    await h.tapTab('Месяц');
    expect(h.activeTab, AppNavTab.month);
    expect(find.byType(MonthStubScreen), findsOneWidget);
    expect(find.byType(TabStubScreen), findsNothing);
  });

  testWidgets('ветка «Месяц» не пересоздаётся при уходе на другую вкладку', (
    tester,
  ) async {
    final h = await ShellHarness.start(tester);
    final before = tester.element(find.byType(MonthStubScreen));

    await h.tapTab('Статистика');
    expect(find.byType(MonthStubScreen, skipOffstage: false), findsOneWidget);
    await h.tapTab('Месяц');

    expect(
      identical(tester.element(find.byType(MonthStubScreen)), before),
      isTrue,
    );
  });

  testWidgets('смена вкладки и повторный тап — в debug-логе nav', (
    tester,
  ) async {
    final h = await ShellHarness.start(tester);

    await h.tapTab('Статистика');
    await h.tapTab('Статистика');
    await h.tapTab('Профиль');
    await h.tapTab('Месяц');

    expect(h.navDebug(), [
      'tab month → stats',
      'tab stats tapped again → branch root',
      'tab stats → profile',
      'tab profile → month',
    ]);
  });

  testWidgets('переходы в info-логе nav: оболочка и экраны вкладок по разу', (
    tester,
  ) async {
    final h = await ShellHarness.start(tester);
    await h.tapTab('Статистика');
    await h.tapTab('Месяц');
    await h.tapTab('Статистика');

    expect(
      h.records
          .where((r) => r.loggerName == 'nav' && r.level == Level.INFO)
          .map((r) => r.message),
      ['push shell (from -)', 'push month (from -)', 'push stats (from -)'],
    );
  });

  testWidgets('долгий тап по логотипу: каталог поверх меню, «назад» — к меню', (
    tester,
  ) async {
    final h = await ShellHarness.start(tester);

    await tester.longPress(find.byType(AppLogo));
    await tester.pumpAndSettle();
    expect(find.byType(CatalogScreen), findsOneWidget);
    expect(find.byType(AppBottomNav), findsNothing);

    await h.systemBack();
    expect(find.byType(CatalogScreen), findsNothing);
    expect(h.activeTab, AppNavTab.month);
    expect(h.systemPops, 0);
  });

  testWidgets('меню до низа экрана, без системной панели снизу отступ 18', (
    tester,
  ) async {
    await ShellHarness.start(tester);

    final nav = tester.getRect(find.byType(AppBottomNav));
    expect(nav.bottom, 800);
    expect(nav.left, 0);
    expect(nav.width, 360);
    final label = tester.getRect(find.text('Месяц'));
    expect(nav.bottom - label.bottom, greaterThanOrEqualTo(18));
  });

  testWidgets('с жестовой панелью 48 dp меню до низа, кнопки над панелью', (
    tester,
  ) async {
    final h = await ShellHarness.start(tester, bottomInset: 48);

    final nav = tester.getRect(find.byType(AppBottomNav));
    expect(nav.bottom, 800);
    for (final label in ['Месяц', 'Статистика', 'Регулярные', 'Профиль']) {
      expect(tester.getRect(h.navLabel(label)).bottom, lessThanOrEqualTo(752));
    }
    expect(tester.getRect(find.byType(AppFab)).bottom, lessThanOrEqualTo(752));

    await h.tapTab('Регулярные');
    expect(h.activeTab, AppNavTab.recurring);
  });

  testWidgets('экран 320 dp и шрифт 2.0: подписи меню целиком', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final h = await ShellHarness.start(tester, size: const Size(320, 800));

    for (final label in ['Месяц', 'Статистика', 'Регулярные', 'Профиль']) {
      final rect = tester.getRect(h.navLabel(label));
      expect(rect.left, greaterThanOrEqualTo(0), reason: label);
      expect(rect.right, lessThanOrEqualTo(320), reason: label);
    }
    expect(tester.takeException(), isNull);

    await h.tapTab('Статистика');
    expect(h.activeTab, AppNavTab.stats);
  });
}
