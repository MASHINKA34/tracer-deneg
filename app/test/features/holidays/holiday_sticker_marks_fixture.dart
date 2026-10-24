import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/app.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/holiday_settings.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/session/session.dart';
import 'package:milionchik/data/session/session_providers.dart';
import 'package:milionchik/data/session/session_state.dart';
import 'package:milionchik/ui/components/day_cell.dart';
import 'package:milionchik/ui/components/fab.dart';
import 'package:milionchik/ui/components/month_card.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';
import '../month/month_fixture.dart';

const SessionUser markUser = SessionUser(
  userId: 'user-marks-68',
  login: 'marks_68',
  displayName: 'Оля',
);

Future<AppDatabase> startHolidayApp(
  WidgetTester tester, {
  required DateTime Function() now,
  HolidaySettings? settings,
  bool signedIn = false,
  AppDatabase? database,
}) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(360, 800);
  addTearDown(tester.view.reset);
  final db = database ?? openTestDatabase();
  if (database == null) {
    await tester.runAsync(() => seedMockupOctober(db));
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(Clock(now: now)),
        if (signedIn) ...[
          sessionProvider.overrideWithBuild(
            (ref, _) => const SessionActive(markUser),
          ),
          if (settings != null)
            startupHolidaySettingsProvider.overrideWithValue(
              CachedHolidaySettings(
                userId: markUser.userId,
                settings: settings,
              ),
            ),
        ] else if (settings != null)
          holidaySettingsProvider.overrideWithValue(settings),
      ],
      child: const MilionchikApp(),
    ),
  );
  await tester.pumpAndSettle();
  return db;
}

Future<void> applyAccountSettings(
  WidgetTester tester,
  HolidaySettings settings,
) async {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(MilionchikApp)),
  );
  final applied = await tester.runAsync(
    () => container
        .read(accountHolidaySettingsProvider.notifier)
        .apply(
          User(
            id: markUser.userId,
            login: markUser.login,
            displayName: markUser.displayName,
            birthday: settings.birthday,
            holidaysEnabled: settings.enabled,
            holidaysDisabled: {for (final key in settings.disabled) key.key},
            createdAt: DateTime.utc(2026, 10, 1),
          ),
          source: 'test',
        ),
  );
  expect(applied, isTrue);
  await tester.pumpAndSettle();
}

String? fabStickerOf(WidgetTester tester) =>
    tester.widget<AppFab>(find.byType(AppFab)).stickerEmoji;

Finder get fabStickerText =>
    find.descendant(of: find.byType(AppFab), matching: find.byType(Text));

YearMonth shownMonth(WidgetTester tester) =>
    tester.widget<MonthCard>(find.byType(MonthCard)).month;

Map<int, String> dayMarks(WidgetTester tester) => {
  for (final cell in tester.widgetList<DayCell>(
    find.descendant(of: find.byType(MonthCard), matching: find.byType(DayCell)),
  ))
    if (cell.day != null && cell.holidayEmoji != null)
      cell.day!: cell.holidayEmoji!,
};
