import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milionchik/features/month/month_header.dart';
import 'package:milionchik/l10n/app_localizations.dart';
import 'package:milionchik/ui/theme/app_theme.dart';
import 'package:shared/shared.dart';

import '../../support/test_fonts.dart';

Future<void> _pumpHeader(
  WidgetTester tester, {
  required double width,
  required double scale,
  LocalDate? debugToday,
}) async {
  tester.view
    ..devicePixelRatio = 3
    ..physicalSize = Size(width, 800) * 3;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ru'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: AppTheme.build(Brightness.light, Mood.halloween),
      home: Scaffold(
        body: MonthHeaderView(
          budgetName: 'Личный бюджет',
          budgetEmoji: '👛',
          avatarLetter: 'Л',
          onBudgetTap: () {},
          onSearchTap: () {},
          onAvatarTap: () {},
          debugToday: debugToday,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _label() => find.descendant(
  of: find.byType(MonthHeaderView),
  matching: find.textContaining('debug '),
);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
    await loadTestFonts();
  });

  for (final width in const [320.0, 360.0]) {
    for (final scale in const [1.0, 2.0]) {
      testWidgets('${width.toInt()} dp, шрифт $scale: метка «debug 31.10» '
          'между бюджетом и поиском, без переполнения', (tester) async {
        await _pumpHeader(
          tester,
          width: width,
          scale: scale,
          debugToday: LocalDate(2026, 10, 31),
        );

        expect(tester.takeException(), isNull);
        expect(_label(), findsOneWidget);
        expect(tester.widget<Text>(_label()).data, startsWith('debug 31.10'));
        expect(find.bySemanticsLabel(RegExp(r'^debug 31\.10')), findsOne);
        final label = tester.getRect(_label());
        final budget = tester.getRect(find.text('Личный бюджет'));
        final search = tester.getRect(find.bySemanticsLabel('Поиск'));
        expect(label.left, greaterThanOrEqualTo(budget.right));
        expect(label.right, lessThanOrEqualTo(search.left));
        expect(label.top, greaterThanOrEqualTo(0));
        expect(label.bottom, lessThanOrEqualTo(52));
      });
    }
  }

  testWidgets('подмены нет — метки нет', (tester) async {
    await _pumpHeader(tester, width: 360, scale: 1);

    expect(tester.takeException(), isNull);
    expect(_label(), findsNothing);
  });

  testWidgets('подмена на другой год — год в метке', (tester) async {
    final year = DateTime.now().year - 1;
    await _pumpHeader(
      tester,
      width: 360,
      scale: 1,
      debugToday: LocalDate(year, 12, 31),
    );

    expect(tester.widget<Text>(_label()).data, 'debug 31.12.$year');
  });
}
