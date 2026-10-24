import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milionchik/ui/components/bottom_nav.dart';
import 'package:milionchik/ui/components/fab.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';
import '../auth/session_expired_fixture.dart' show testUnmounting;
import '../month/month_fixture.dart';
import 'holiday_sticker_marks_fixture.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testUnmounting('31.10 - 🎃 на «+»: кружок 26 справа сверху; 1.11 - без '
      'наклейки', (tester) async {
    final db = await startHolidayApp(
      tester,
      now: () => DateTime(2026, 10, 31, 12),
    );

    expect(fabStickerOf(tester), '🎃');
    expect(fabStickerText, findsOneWidget);
    expect(tester.widget<Text>(fabStickerText).data, '🎃');
    final fab = tester.getRect(find.byType(AppFab));
    final sticker = tester.getRect(
      find.ancestor(of: fabStickerText, matching: find.byType(Container)).first,
    );
    expect(fab.size, const Size(60, 60));
    expect(sticker.size, const Size(26, 26));
    expect(sticker.left - fab.left, 40);
    expect(sticker.top - fab.top, -6);

    await tester.pumpWidget(const SizedBox.shrink());
    await startHolidayApp(
      tester,
      now: () => DateTime(2026, 11, 1, 12),
      database: db,
    );

    expect(fabStickerOf(tester), isNull);
    expect(fabStickerText, findsNothing);
  });

  testUnmounting('полночь 31.10 → 1.11 при открытом приложении - наклейка '
      'пропадает без перезапуска', (tester) async {
    var now = DateTime(2026, 10, 31, 23, 59, 50);
    await startHolidayApp(tester, now: () => now);
    expect(fabStickerOf(tester), '🎃');

    now = DateTime(2026, 11, 1);
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(fabStickerOf(tester), isNull);
    expect(fabStickerText, findsNothing);
  });

  testUnmounting('Хеллоуин выключен или все праздники выключены - без '
      'наклейки; выключен другой праздник - 🎃', (tester) async {
    final db = openTestDatabase();
    await tester.runAsync(() => seedMockupOctober(db));
    for (final (settings, sticker) in const [
      (HolidaySettings(disabled: {HolidayKey.halloween}), null),
      (HolidaySettings(enabled: false), null),
      (HolidaySettings(disabled: {HolidayKey.newyear}), '🎃'),
    ]) {
      await startHolidayApp(
        tester,
        now: () => DateTime(2026, 10, 28, 12),
        settings: settings,
        database: db,
      );
      expect(fabStickerOf(tester), sticker, reason: '$settings');
      expect(
        fabStickerText,
        sticker == null ? findsNothing : findsOneWidget,
        reason: '$settings',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testUnmounting('наклейка - эмодзи активного праздника: свой день рождения '
      'важнее Хеллоуина (🎂), 29.12 - 🎄; на вкладке «Статистика» та же', (
    tester,
  ) async {
    final db = await startHolidayApp(
      tester,
      now: () => DateTime(2026, 10, 31, 12),
      settings: HolidaySettings(birthday: MonthDay(11, 1)),
    );
    expect(fabStickerOf(tester), '🎂');

    await tester.tap(
      find.descendant(
        of: find.byType(AppBottomNav),
        matching: find.text('Статистика'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<AppBottomNav>(find.byType(AppBottomNav)).active,
      AppNavTab.stats,
    );
    expect(fabStickerOf(tester), '🎂');
    expect(tester.widget<Text>(fabStickerText).data, '🎂');

    await tester.pumpWidget(const SizedBox.shrink());
    await startHolidayApp(
      tester,
      now: () => DateTime(2026, 12, 29, 12),
      database: db,
    );
    expect(fabStickerOf(tester), '🎄');
  });

  testUnmounting('настройки аккаунта сменились при открытом приложении - '
      'наклейка меняется сразу, без перезапуска', (tester) async {
    await startHolidayApp(
      tester,
      now: () => DateTime(2026, 10, 31, 12),
      signedIn: true,
      settings: const HolidaySettings(),
    );
    expect(fabStickerOf(tester), '🎃');

    await applyAccountSettings(
      tester,
      const HolidaySettings(disabled: {HolidayKey.halloween}),
    );
    expect(fabStickerOf(tester), isNull);
    expect(fabStickerText, findsNothing);

    await applyAccountSettings(
      tester,
      HolidaySettings(birthday: MonthDay(10, 31)),
    );
    expect(fabStickerOf(tester), '🎂');
  });
}
