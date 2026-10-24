import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milionchik/app.dart';
import 'package:milionchik/features/profile/theme_mode.dart';
import 'package:milionchik/ui/components/day_cell.dart';
import 'package:milionchik/ui/components/month_card.dart';
import 'package:milionchik/ui/decor/decor_painter.dart';
import 'package:milionchik/ui/theme/app_theme.dart';
import 'package:milionchik/ui/theme/mood_colors.dart';
import 'package:shared/shared.dart';

import '../../data/api/fake_api_adapter.dart' show LogCapture;
import '../../support/app_scope.dart';
import '../../support/test_fonts.dart';
import '../auth/session_expired_fixture.dart' show testUnmounting;
import 'holiday_banner_fixture.dart';
import 'holiday_decor_fixture.dart';

final RegExp _cachedLine = RegExp(
  r'^decor picture cached layer=(\S+) theme=(\S+) size=(\S+) shapes=\d+ '
  r'in \d+ms \(cache miss\)$',
);

List<String> _generated(LogCapture logs) => [
  for (final r in logs.records)
    if (r.loggerName == 'decor' && r.message.startsWith('decor picture cached'))
      _cachedLine.firstMatch(r.message)!.groups([1, 2, 3]).join(' '),
];

DecorPainter _decor(WidgetTester tester) => tester
    .widgetList<CustomPaint>(
      find.descendant(
        of: find.byType(MonthCard),
        matching: find.byType(CustomPaint),
      ),
    )
    .map((p) => p.painter)
    .whereType<DecorPainter>()
    .single;

MoodColors _cardColors(WidgetTester tester) =>
    MoodColors.of(tester.element(find.byType(DayCell).first));

Future<void> _throughThemeTransition(WidgetTester tester) async {
  await tester.pump();
  for (var t = Duration.zero; t <= AppTheme.transition; t += _frame) {
    await tester.pump(_frame);
  }
  await tester.pumpAndSettle();
}

const Duration _frame = Duration(milliseconds: 16);

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testUnmounting('Хеллоуин: тёмная тема телефона - жуткий слой, выбор светлой '
      'в настройках - снова милый, всё без перезапуска; картинка каждого '
      'слоя рисуется один раз за все кадры перехода', (tester) async {
    await loadTestFonts();
    DecorPainter.clearCache();
    addTearDown(DecorPainter.clearCache);
    final logs = LogCapture();
    addTearDown(logs.dispose);
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(360, 800);
    addTearDown(tester.view.reset);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    final example = figmaHolidayExamples.firstWhere(
      (e) => e.key == HolidayKey.halloween,
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
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MilionchikApp)),
    );
    final appState = tester.state(find.byType(MilionchikApp));

    expect(container.read(themeModeProvider), ThemeMode.system);
    expect(
      tester.widget<MonthCard>(find.byType(MonthCard)).mood,
      Mood.halloween,
    );
    expect(_decor(tester).layer.key, 'halloween-cute');
    expect(
      _cardColors(tester).soft,
      MoodColors.forMood(Mood.halloween, Brightness.light).soft,
    );
    expect(_generated(logs), ['halloween-cute light 336.0x423.0']);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await _throughThemeTransition(tester);

    expect(tester.state(find.byType(MilionchikApp)), same(appState));
    expect(_decor(tester).brightness, Brightness.dark);
    expect(_decor(tester).layer.key, 'halloween-spooky');
    expect(
      _cardColors(tester).soft,
      MoodColors.forMood(Mood.halloween, Brightness.dark).soft,
    );
    expect(_generated(logs), [
      'halloween-cute light 336.0x423.0',
      'halloween-spooky dark 336.0x423.0',
    ]);

    final saved = await tester.runAsync(
      () => container.read(themeModeProvider.notifier).set(ThemeMode.light),
    );
    expect(saved, isTrue);
    await _throughThemeTransition(tester);

    expect(tester.state(find.byType(MilionchikApp)), same(appState));
    expect(_decor(tester).brightness, Brightness.light);
    expect(_decor(tester).layer.key, 'halloween-cute');
    expect(
      _cardColors(tester).soft,
      MoodColors.forMood(Mood.halloween, Brightness.light).soft,
    );
    expect(_generated(logs), [
      'halloween-cute light 336.0x423.0',
      'halloween-spooky dark 336.0x423.0',
    ]);
    expect(DecorPainter.cachedPictures, 2);
  });
}
