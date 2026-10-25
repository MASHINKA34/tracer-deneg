import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/app.dart';
import 'package:milionchik/features/expense/new_expense_screen.dart';
import 'package:milionchik/features/month/day_sheet.dart';
import 'package:milionchik/features/month/month_controller.dart';
import 'package:milionchik/features/month/month_screen.dart';
import 'package:milionchik/ui/components/bottom_nav.dart';
import 'package:milionchik/ui/components/dialog.dart';
import 'package:milionchik/ui/components/month_card.dart';
import 'package:shared/shared.dart';

import '../features/auth/session_expired_fixture.dart' show testUnmounting;
import '../features/expense/new_expense_harness.dart' show amountText, typeKeys;
import '../features/month/month_fixture.dart';
import '../features/shell/shell_harness.dart';
import '../support/app_scope.dart';

final _october = YearMonth(2026, 10);

final _september = YearMonth(2026, 9);

Future<ShellHarness> _start(WidgetTester tester, {String? coldLink}) async {
  if (coldLink != null) {
    tester.platformDispatcher.defaultRouteNameTestValue = coldLink;
    addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
  }
  final db = openTestDatabase();
  await tester.runAsync(() => seedMockupOctober(db));
  return ShellHarness.start(tester, db: db);
}

Future<void> _sendLink(WidgetTester tester, String link) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.navigation.name,
    SystemChannels.navigation.codec.encodeMethodCall(
      MethodCall('pushRouteInformation', <String, Object?>{'location': link}),
    ),
    (_) {},
  );
  await tester.pumpAndSettle();
}

YearMonth _shownMonth(WidgetTester tester) =>
    tester.widget<MonthCard>(find.byType(MonthCard)).month;

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(MilionchikApp)));

Iterable<String> _nav(ShellHarness h, Level level) => h.records
    .where((r) => r.loggerName == 'nav' && r.level == level)
    .map((r) => r.message);

Future<void> _openDay(WidgetTester tester, String date) async {
  await tester.tap(find.bySemanticsLabel(RegExp('^$date')));
  await tester.pumpAndSettle();
  expect(find.byType(DaySheet), findsOneWidget);
}

void main() {
  testUnmounting('холодный старт по milionchik://add от системы: «Новая '
      'трата» поверх главной, в логе start=cold', (tester) async {
    final h = await _start(tester, coldLink: 'milionchik://add');

    expect(find.byType(NewExpenseScreen), findsOneWidget);
    expect(find.byType(MonthScreen, skipOffstage: false), findsOneWidget);
    expect(
      _nav(h, Level.INFO).first,
      'deep link milionchik://add start=cold → /expense/new over /month',
    );
    expect(_nav(h, Level.WARNING), isEmpty);
    expect(h.records.where((r) => r.level >= Level.SEVERE), isEmpty);

    await tester.tap(find.bySemanticsLabel('Закрыть'));
    await tester.pumpAndSettle();
    expect(find.byType(NewExpenseScreen), findsNothing);
    expect(h.activeTab, AppNavTab.month);
  });

  testUnmounting('холодный старт по milionchik://month: вкладка «Месяц» на '
      'текущем месяце, без «Новой траты»', (tester) async {
    final h = await _start(tester, coldLink: 'milionchik://month');

    expect(find.byType(NewExpenseScreen), findsNothing);
    expect(h.activeTab, AppNavTab.month);
    expect(_shownMonth(tester), _october);
    expect(
      _nav(h, Level.INFO).first,
      'deep link milionchik://month start=cold → /month on the current month',
    );
    expect(_nav(h, Level.WARNING), isEmpty);
    expect(h.records.where((r) => r.level >= Level.SEVERE), isEmpty);
  });

  testUnmounting('тёплый старт milionchik://month со «Статистики» при '
      'открытом сентябре: вкладка «Месяц», снова октябрь', (tester) async {
    final h = await _start(tester);
    await tester.tap(find.bySemanticsLabel('Предыдущий месяц'));
    await tester.pumpAndSettle();
    expect(_shownMonth(tester), _september);
    await h.tapTab('Статистика');
    expect(h.activeTab, AppNavTab.stats);

    await _sendLink(tester, 'milionchik://month');

    expect(h.activeTab, AppNavTab.month);
    expect(_shownMonth(tester), _october);
    expect(_container(tester).read(monthControllerProvider), _october);
    expect(
      _nav(h, Level.INFO),
      contains(
        'deep link milionchik://month start=warm from=/stats → /month on the '
        'current month',
      ),
    );
    expect(
      h.records
          .where((r) => r.loggerName == 'month' && r.level == Level.FINE)
          .map((r) => r.message),
      contains(
        'month 2026-09 → 2026-10 by=link (current month) '
        'today=2026-10-19',
      ),
    );
  });

  testUnmounting('тёплый старт milionchik://month при открытой шторке дня '
      'сентября: шторка закрыта, на главной октябрь', (tester) async {
    final h = await _start(tester);
    await tester.tap(find.bySemanticsLabel('Предыдущий месяц'));
    await tester.pumpAndSettle();
    await _openDay(tester, '5 сентября');

    await _sendLink(tester, 'milionchik://month');

    expect(find.byType(DaySheet), findsNothing);
    expect(_container(tester).read(openDaySheetProvider), isNull);
    expect(_shownMonth(tester), _october);
    expect(
      _nav(h, Level.FINE),
      contains(
        startsWith('deep link month: closed 1 sheet/dialog over the app'),
      ),
    );
  });

  testUnmounting('тёплый старт milionchik://add при открытой шторке дня: '
      '«Новая трата», после закрытия — главная без шторки', (tester) async {
    final h = await _start(tester);
    await _openDay(tester, '17 октября');

    await _sendLink(tester, 'milionchik://add?comment=QUERY-VALUE-ZULU');

    expect(find.byType(NewExpenseScreen), findsOneWidget);
    expect(
      _nav(h, Level.INFO),
      contains(
        'deep link milionchik://add start=warm from=/month query=ignored → '
        '/expense/new over /month',
      ),
    );
    await tester.tap(find.bySemanticsLabel('Закрыть'));
    await tester.pumpAndSettle();
    expect(find.byType(NewExpenseScreen), findsNothing);
    expect(find.byType(DaySheet), findsNothing);
    expect(find.byType(MonthScreen), findsOneWidget);
    for (final r in h.records) {
      expect(r.message, isNot(contains('QUERY-VALUE-ZULU')), reason: r.message);
    }
  });

  testUnmounting('чужие хосты и пути: главная без «Новой траты» и без ошибки, '
      'warn со схемой и путём без query', (tester) async {
    final h = await _start(tester);

    for (final link in [
      'milionchik://unknown?token=QUERY-VALUE-YANKEE',
      'milionchik://add/extra',
      'https://example.org/month',
    ]) {
      await h.tapTab('Статистика');
      await _sendLink(tester, link);
      expect(h.activeTab, AppNavTab.month, reason: link);
      expect(find.byType(NewExpenseScreen), findsNothing, reason: link);
      expect(find.byType(MonthScreen), findsOneWidget, reason: link);
    }

    expect(_nav(h, Level.WARNING), [
      'deep link milionchik://unknown start=warm from=/stats query=ignored: '
          'unknown link, known: milionchik://add, milionchik://month → /month',
      'deep link milionchik://add/extra start=warm from=/stats: unknown '
          'link, known: milionchik://add, milionchik://month → /month',
      'deep link https://example.org/month start=warm from=/stats: unknown '
          'link, known: milionchik://add, milionchik://month → /month',
    ]);
    expect(h.records.where((r) => r.level >= Level.SEVERE), isEmpty);
    for (final r in h.records) {
      expect(r.message, isNot(contains('QUERY-VALUE-YANKEE')));
    }
  });
  testUnmounting('ссылка при открытом диалоге «Не сохранять?»: диалог и '
      'начатая трата закрыты без ошибок, add открывает новую пустую', (
    tester,
  ) async {
    final h = await _start(tester);

    for (final link in ['milionchik://add', 'milionchik://month']) {
      await h.tapPlus();
      await typeKeys(tester, '1250');
      await tester.tap(find.bySemanticsLabel('Закрыть'));
      await tester.pumpAndSettle();
      expect(find.byType(AppDialog), findsOneWidget, reason: link);

      await _sendLink(tester, link);

      expect(find.byType(AppDialog), findsNothing, reason: link);
      expect(
        find.byType(NewExpenseScreen),
        link.endsWith('add') ? findsOneWidget : findsNothing,
        reason: link,
      );
      if (link.endsWith('add')) {
        expect(amountText(tester), '0');
        await tester.tap(find.bySemanticsLabel('Закрыть'));
        await tester.pumpAndSettle();
      }
      expect(find.byType(MonthScreen), findsOneWidget, reason: link);
    }
    expect(_nav(h, Level.WARNING), isEmpty);
    expect(h.records.where((r) => r.level >= Level.SEVERE), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
