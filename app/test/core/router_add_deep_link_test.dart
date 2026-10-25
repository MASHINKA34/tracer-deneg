import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/router.dart';
import 'package:milionchik/features/expense/new_expense_screen.dart';
import 'package:milionchik/features/month/month_screen.dart';
import 'package:milionchik/l10n/app_localizations.dart';
import 'package:milionchik/ui/components/bottom_nav.dart';
import 'package:milionchik/ui/theme/app_theme.dart';
import 'package:shared/shared.dart' show Mood;

import '../support/app_scope.dart';

Future<(GoRouter, List<LogRecord>)> _start(
  WidgetTester tester, {
  String initialLocation = AppRoutes.month,
}) async {
  final records = <LogRecord>[];
  final previous = Logger.root.level;
  Logger.root.level = Level.ALL;
  final sub = Logger.root.onRecord.listen(records.add);
  addTearDown(() async {
    await sub.cancel();
    Logger.root.level = previous;
  });
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(360, 800);
  addTearDown(tester.view.reset);

  final router = buildRouter(initialLocation: initialLocation);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    withDatabase(
      openTestDatabase(),
      MaterialApp.router(
        theme: AppTheme.build(Brightness.light, Mood.autumn),
        locale: const Locale('ru'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (router, records);
}

AppNavTab _tab(WidgetTester tester) => tester
    .widget<AppBottomNav>(find.byType(AppBottomNav, skipOffstage: false))
    .active;

Iterable<String> _nav(List<LogRecord> records, Level level) => records
    .where((r) => r.loggerName == 'nav' && r.level == level)
    .map((r) => r.message);

void main() {
  test('milionchik://add распознаётся, другие хосты, схемы и пути — нет', () {
    expect(isAddExpenseLink(Uri.parse('milionchik://add')), isTrue);
    expect(isAddExpenseLink(Uri.parse('milionchik://add/')), isTrue);
    expect(isAddExpenseLink(Uri.parse('milionchik://add?from=widget')), isTrue);
    expect(isAddExpenseLink(Uri.parse('milionchik://month')), isFalse);
    expect(isAddExpenseLink(Uri.parse('https://add')), isFalse);
    expect(isAddExpenseLink(Uri.parse('/add')), isFalse);
    expect(isAddExpenseLink(Uri.parse(AppRoutes.newExpense)), isFalse);
  });

  testWidgets('холодный старт по milionchik://add — «Новая трата» поверх '
      'главной, крестик возвращает на месяц', (tester) async {
    final (router, records) = await _start(
      tester,
      initialLocation: 'milionchik://add',
    );

    expect(find.byType(NewExpenseScreen), findsOneWidget);
    expect(find.byType(MonthScreen, skipOffstage: false), findsOneWidget);
    expect(router.state.uri.toString(), AppRoutes.newExpense);
    expect(router.canPop(), isTrue);

    await tester.tap(find.bySemanticsLabel('Закрыть'));
    await tester.pumpAndSettle();
    expect(find.byType(NewExpenseScreen), findsNothing);
    expect(find.byType(MonthScreen), findsOneWidget);
    expect(_tab(tester), AppNavTab.month);
    expect(_nav(records, Level.INFO), [
      'deep link milionchik://add start=cold → /expense/new over /month',
      'push shell (from -)',
      'push month (from -)',
      'push newExpense (from shell)',
      'pop newExpense (back to shell)',
    ]);
    expect(
      _nav(records, Level.FINE),
      contains('deep link add: /month is shown, pushing /expense/new'),
    );
    expect(records.where((r) => r.level >= Level.WARNING), isEmpty);
  });

  testWidgets('тёплый старт со «Статистики» — вкладка «Месяц» и «Новая трата» '
      'поверх; query ссылки в лог не попадает', (tester) async {
    final (router, records) = await _start(
      tester,
      initialLocation: AppRoutes.stats,
    );
    expect(_tab(tester), AppNavTab.stats);

    router.go('milionchik://add?code=MLN-7Q2X');
    await tester.pumpAndSettle();

    expect(find.byType(NewExpenseScreen), findsOneWidget);
    expect(_tab(tester), AppNavTab.month);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(NewExpenseScreen), findsNothing);
    expect(find.byType(MonthScreen), findsOneWidget);
    expect(
      _nav(records, Level.INFO),
      contains(
        'deep link milionchik://add start=warm from=/stats query=ignored '
        '→ /expense/new over /month',
      ),
    );
    for (final r in records) {
      expect(r.message, isNot(contains('MLN-7Q2X')), reason: r.message);
    }
  });

  testWidgets('чужой хост milionchik://unknown — главная с warn, без «Новой '
      'траты»', (tester) async {
    final (router, records) = await _start(tester);

    router.go('milionchik://unknown');
    await tester.pumpAndSettle();

    expect(find.byType(NewExpenseScreen), findsNothing);
    expect(find.byType(MonthScreen), findsOneWidget);
    expect(
      records.where((r) => r.level == Level.WARNING).map((r) => r.message),
      [
        'deep link milionchik://unknown start=warm from=/month: unknown link, '
            'known: milionchik://add, milionchik://month → /month',
      ],
    );
  });
}
