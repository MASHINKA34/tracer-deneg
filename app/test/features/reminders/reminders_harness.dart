import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/reminder_triggers_scope.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:milionchik/features/reminders/reminder_notifications.dart';
import 'package:milionchik/features/reminders/reminder_settings.dart';
import 'package:milionchik/features/reminders/reminders_screen.dart';
import 'package:milionchik/ui/components/toggle.dart';
import 'package:shared/shared.dart';

import '../../data/api/fake_api_adapter.dart';
import '../profile/profile_harness.dart';
import 'reminder_fakes.dart';

Future<ProfileHarness> startWithReminders(
  WidgetTester tester,
  FakeReminderNotifications plugin, {
  ReminderSettings settings = ReminderSettings.standard,
  FakeHandler server = noServer,
  AppDatabase? db,
  bool seed = true,
  List<Override> overrides = const [],
  Size size = const Size(360, 800),
}) => ProfileHarness.start(
  tester,
  server: server,
  db: db,
  seed: seed,
  size: size,
  overrides: [
    reminderNotificationsProvider.overrideWithValue(plugin),
    reminderSettingsProvider.overrideWithBuild((ref, _) => settings),
    ...overrides,
  ],
  wrap: (app) => ReminderTriggersScope(child: app),
);

Future<void> openReminders(ProfileHarness h) async {
  await h.openProfile();
  await h.tap(h.row('Напоминания'));
  expect(find.byType(RemindersScreen), findsOneWidget);
}

bool switchValue(WidgetTester tester) =>
    tester.widget<AppToggle>(find.byType(AppToggle)).value;

Future<(bool?, int?)> storedReminders(ProfileHarness h) async =>
    (await h.tester.runAsync(() async {
      final prefs = DriftPrefsRepository(h.db);
      return (
        await prefs.getBool(PrefKeys.remindersEnabled),
        await prefs.getInt(PrefKeys.reminderMinutes),
      );
    }))!;

List<String> reminderLines(ProfileHarness h, [Level from = Level.ALL]) => [
  for (final r in h.logs.records)
    if (r.loggerName == 'reminders' && r.level >= from) r.message,
];

List<LocalDate> octoberDays(int from, int to) => [
  for (var d = from; d <= to; d++) LocalDate(2026, 10, d),
];
