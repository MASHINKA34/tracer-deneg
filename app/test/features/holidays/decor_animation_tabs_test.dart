import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milionchik/app.dart';
import 'package:milionchik/features/expense/new_expense_screen.dart';
import 'package:milionchik/ui/components/bottom_nav.dart';
import 'package:milionchik/ui/components/fab.dart';
import 'package:milionchik/ui/components/month_card.dart';
import 'package:milionchik/ui/decor/decor_painter.dart';
import 'package:shared/shared.dart';

import '../../data/api/fake_api_adapter.dart' show LogCapture;
import '../../support/app_scope.dart';
import '../auth/session_expired_fixture.dart' show testUnmounting;
import 'holiday_banner_fixture.dart';
import 'holiday_decor_fixture.dart';

const Duration _frame = Duration(milliseconds: 16);

final RegExp _stateLine = RegExp(
  r'^decor animation (started|paused|not started|stopped) ',
);

ui.Picture? _decorPicture(WidgetTester tester) {
  final paint = find.descendant(
    of: find.byType(MonthCard, skipOffstage: false),
    matching: find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is DecorPainter,
      skipOffstage: false,
    ),
  );
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find
        .ancestor(
          of: paint,
          matching: find.byType(RepaintBoundary, skipOffstage: false),
        )
        .first,
  );
  return (boundary.debugLayer?.firstChild as PictureLayer?)?.picture;
}

Future<int> _decorFrames(WidgetTester tester, [int frames = 12]) async {
  var changed = 0;
  var last = _decorPicture(tester);
  for (var i = 0; i < frames; i++) {
    await tester.pump(_frame);
    final now = _decorPicture(tester);
    if (!identical(now, last)) changed++;
    last = now;
  }
  return changed;
}

Finder _nav(String label) =>
    find.descendant(of: find.byType(AppBottomNav), matching: find.text(label));

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testUnmounting('Новый год на главной: анимация идёт, пока главная на '
      'экране; вкладка «Статистика» и экран новой траты сверху ставят её на '
      'паузу, возврат на главную - снова старт', (tester) async {
    DecorPainter.clearCache();
    addTearDown(DecorPainter.clearCache);
    final logs = LogCapture();
    addTearDown(logs.dispose);
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(360, 800);
    addTearDown(tester.view.reset);

    final example = figmaHolidayExamples.firstWhere(
      (e) => e.key == HolidayKey.newyear,
    );
    final db = openTestDatabase();
    await tester.runAsync(() => seedFigmaHolidayCard(db, example));
    await tester.pumpWidget(
      ProviderScope(
        overrides: holidayOverrides(db, example.key, () => example.now),
        child: const MilionchikApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<MonthCard>(find.byType(MonthCard)).mood, Mood.newyear);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(await _decorFrames(tester), 12);

    await tester.tap(_nav('Статистика'));
    await tester.pumpAndSettle();
    expect(find.byType(MonthCard), findsNothing);
    expect(await _decorFrames(tester), 0);

    await tester.tap(_nav('Месяц'));
    await tester.pump();
    expect(await _decorFrames(tester), 12);

    await tester.tap(find.byType(AppFab));
    for (var i = 0; i < 40; i++) {
      await tester.pump(_frame);
    }
    expect(find.byType(NewExpenseScreen), findsOneWidget);
    await tester.pump();
    expect(await _decorFrames(tester), 0);
    expect(tester.binding.hasScheduledFrame, isFalse);

    await tester.binding.handlePopRoute();
    for (var i = 0; i < 40; i++) {
      await tester.pump(_frame);
    }
    expect(find.byType(NewExpenseScreen), findsNothing);
    expect(await _decorFrames(tester), 12);

    final lines = [
      for (final r in logs.records)
        if (r.loggerName == 'decor' && _stateLine.hasMatch(r.message))
          r.message,
    ];
    expect(lines, [
      'decor animation not started holiday=newyear layer=newyear '
          'reason=app lifecycle unknown → static picture',
      'decor animation started holiday=newyear layer=newyear cycle=6000ms '
          'trigger=app resumed',
      matches(
        r'^decor animation paused holiday=newyear layer=newyear '
        r'reason=screen hidden \(another tab or screen on top\) after \d+ms$',
      ),
      'decor animation started holiday=newyear layer=newyear cycle=6000ms '
          'trigger=screen visible again',
      matches(
        r'^decor animation paused holiday=newyear layer=newyear '
        r'reason=screen hidden \(another tab or screen on top\) after \d+ms$',
      ),
      'decor animation started holiday=newyear layer=newyear cycle=6000ms '
          'trigger=screen visible again',
    ]);
  });
}
