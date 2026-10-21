import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/features/month/month_screen.dart';
import 'package:milionchik/features/shell/tab_stub_screen.dart';
import 'package:milionchik/ui/components/bottom_nav.dart';

import 'shell_harness.dart';

void main() {
  testWidgets('«назад» на «Статистике» ведёт на «Месяц», приложение живо', (
    tester,
  ) async {
    final h = await ShellHarness.start(tester);
    await h.tapTab('Статистика');

    await h.systemBack();

    expect(h.activeTab, AppNavTab.month);
    expect(find.byType(MonthScreen), findsOneWidget);
    expect(find.byType(TabStubScreen), findsNothing);
    expect(h.systemPops, 0);
    expect(h.navDebug(), contains('back on stats root → month'));
  });

  for (final label in ['Регулярные', 'Профиль']) {
    testWidgets('«назад» на вкладке «$label» тоже ведёт на «Месяц»', (
      tester,
    ) async {
      final h = await ShellHarness.start(tester);
      await h.tapTab(label);

      await h.systemBack();

      expect(h.activeTab, AppNavTab.month);
      expect(h.systemPops, 0);
    });
  }

  testWidgets('«назад» на «Месяце» — выход: решает система', (tester) async {
    final h = await ShellHarness.start(tester);

    await h.systemBack();

    expect(h.systemPops, 1);
    expect(h.activeTab, AppNavTab.month);
  });

  testWidgets(
    '«Статистика» → «назад» → «назад»: сначала «Месяц», потом выход',
    (tester) async {
      final h = await ShellHarness.start(tester);
      await h.tapTab('Статистика');

      await h.systemBack();
      expect(h.systemPops, 0);
      await h.systemBack();

      expect(h.systemPops, 1);
    },
  );

  testWidgets(
    'predictive back: на «Статистике» жест ловит приложение, на «Месяце» — система',
    (tester) async {
      final h = await ShellHarness.start(tester);
      expect(h.frameworkHandlesBack, isFalse);
      await h.tapTab('Статистика');

      expect(h.frameworkHandlesBack, isTrue);

      await h.predictiveBackGesture();

      expect(h.activeTab, AppNavTab.month);
      expect(h.systemPops, 0);
      expect(h.frameworkHandlesBack, isFalse);
    },
  );
}
