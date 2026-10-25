import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/features/profile/profile_screen.dart';
import 'package:milionchik/features/reminders/reminder_settings.dart';
import 'package:milionchik/features/reminders/reminders_screen.dart';
import 'package:milionchik/ui/components/snackbar.dart';

import '../auth/session_expired_fixture.dart' show testUnmounting;
import 'reminder_fakes.dart';
import 'reminders_harness.dart';

const _on = ReminderSettings(enabled: true);

Finder _snackbar(String text) =>
    find.descendant(of: find.byType(AppSnackbar), matching: find.text(text));

Future<void> _waitSnackbarGone(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 6));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testUnmounting('Android 13+: включение → системный запрос → «Разрешить» → '
      'включено, в базе, 7 уведомлений, в профиле «В 21:00»', (tester) async {
    final plugin = FakeReminderNotifications(allowed: false);
    final h = await startWithReminders(tester, plugin);
    await h.openProfile();
    expect(h.valueOf('Напоминания'), 'Выкл');
    await h.tap(h.row('Напоминания'));

    expect(find.byType(RemindersScreen), findsOneWidget);
    expect(switchValue(tester), isFalse);
    expect(find.text('Напоминать о тратах'), findsOneWidget);
    expect(find.text('Только если за день ничего не записано'), findsOneWidget);
    expect(find.text('21:00'), findsOneWidget);
    expect(plugin.calls, isEmpty);

    await h.tap(find.text('Напоминать о тратах'));

    expect(switchValue(tester), isTrue);
    expect(plugin.calls, ['requestPermission', 'initialize', 'cancelPending']);
    expect(plugin.pendingDays, octoberDays(19, 25));
    expect(await storedReminders(h), (true, null));
    final info = reminderLines(h).where((l) => !l.startsWith('query'));
    expect(
      info,
      containsAllInOrder([
        'notification permission requested: reminders switch turned on',
        matches(r'^notification permission answer=granted in \d+ms$'),
        matches(
          r'^reminders settings changed to on time=21:00 previous=off '
          r'time=21:00 \(switch on, notifications allowed\) in \d+ms$',
        ),
        matches(
          r'^reminders planned count=7 dates=2026-10-19,.*,2026-10-25 '
          r'at=21:00 tz=Europe/Moscow today=2026-10-19 planned reason=settings '
          r'changed off time=21:00 → on time=21:00 in \d+ms$',
        ),
      ]),
    );
    expect(reminderLines(h, Level.WARNING), isEmpty);

    await tester.tap(find.bySemanticsLabel('Назад').last);
    await h.settle();
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(h.valueOf('Напоминания'), 'В 21:00');
  });

  testUnmounting('отказ: переключатель обратно «выкл», снекбар «Открыть '
      'настройки» открывает системные настройки', (tester) async {
    final plugin = FakeReminderNotifications(allowed: false, grant: false);
    final h = await startWithReminders(tester, plugin);
    await openReminders(h);

    await h.tap(find.text('Напоминать о тратах'));

    expect(switchValue(tester), isFalse);
    expect(await storedReminders(h), (null, null));
    expect(plugin.pending, isEmpty);
    expect(plugin.calls, ['requestPermission']);
    expect(
      _snackbar('Уведомления запрещены в настройках телефона'),
      findsOneWidget,
    );
    expect(
      reminderLines(h, Level.INFO),
      containsAllInOrder([
        'notification permission requested: reminders switch turned on',
        matches(r'^notification permission answer=denied in \d+ms$'),
        'reminders stay off: notification permission denied → switch back '
            'off, snackbar with "open settings"',
      ]),
    );

    await h.tap(find.text('Открыть настройки'));

    expect(plugin.calls, ['requestPermission', 'openSettings']);
    expect(
      reminderLines(h, Level.INFO).last,
      matches(r'^system notification settings opened in \d+ms$'),
    );
    expect(find.byType(RemindersScreen), findsOneWidget);
    await _waitSnackbarGone(tester);
  });

  testUnmounting('время: системный выбор → 07:30 → в базе 450 минут, '
      'напоминания перепланированы с завтрашнего', (tester) async {
    final plugin = FakeReminderNotifications();
    final h = await startWithReminders(tester, plugin, settings: _on);
    expect(plugin.pendingDays, octoberDays(19, 25));
    await openReminders(h);

    await h.tap(find.text('Время'));
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await h.tap(find.byTooltip('Перейти в режим ввода текста'));
    final fields = find.descendant(
      of: find.byType(TimePickerDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), '07');
    await tester.enterText(fields.at(1), '30');
    await h.tap(find.text('ОК'));

    expect(find.byType(TimePickerDialog), findsNothing);
    expect(find.text('07:30'), findsOneWidget);
    expect(await storedReminders(h), (null, 450));
    expect(plugin.pendingDays, octoberDays(20, 25));
    expect(plugin.pending.values.map((r) => (r.at.hour, r.at.minute)).toSet(), {
      (7, 30),
    });
    expect(
      reminderLines(h, Level.INFO).last,
      allOf(
        startsWith('reminders planned count=6 dates=2026-10-20,'),
        contains('at=07:30 '),
        contains('today=2026-10-19 skipped: time already passed'),
      ),
    );
  });

  testUnmounting('системный выбор времени закрыт без выбора - ничего не '
      'меняется', (tester) async {
    final plugin = FakeReminderNotifications();
    final h = await startWithReminders(tester, plugin, settings: _on);
    await openReminders(h);
    final calls = List.of(plugin.calls);

    await h.tap(find.text('Время'));
    await h.tap(find.text('Отмена'));

    expect(find.text('21:00'), findsOneWidget);
    expect(plugin.calls, [...calls]);
    expect(
      reminderLines(h),
      contains('time picker closed without a choice, keeping 21:00'),
    );
  });

  testUnmounting('выключение снимает все уведомления, в базе false', (
    tester,
  ) async {
    final plugin = FakeReminderNotifications();
    final h = await startWithReminders(tester, plugin, settings: _on);
    await openReminders(h);
    expect(plugin.pending, hasLength(7));

    await h.tap(find.text('Напоминать о тратах'));

    expect(switchValue(tester), isFalse);
    expect(plugin.pending, isEmpty);
    expect(plugin.calls.last, 'cancelAll');
    expect(await storedReminders(h), (false, null));
    expect(
      reminderLines(h, Level.INFO).last,
      startsWith('all reminders cancelled: reminders switched off'),
    );
  });

  testUnmounting('уведомления запрещены в системе, а напоминания включены: '
      'при открытии переключатель выкл и снекбар', (tester) async {
    final plugin = FakeReminderNotifications(allowed: false);
    final h = await startWithReminders(tester, plugin, settings: _on);
    await openReminders(h);

    expect(switchValue(tester), isFalse);
    expect(await storedReminders(h), (false, null));
    expect(plugin.pending, isEmpty);
    expect(
      _snackbar('Уведомления запрещены в настройках телефона'),
      findsOneWidget,
    );
    expect(
      reminderLines(h, Level.INFO),
      contains(
        'reminders on, but notifications are blocked in system settings '
        '(screen opened) → switch off, snackbar with "open settings"',
      ),
    );
    await _waitSnackbarGone(tester);
  });

  testUnmounting('строки не ниже 48 dp и при шрифте 2.0 на 320 dp всё '
      'помещается', (tester) async {
    final plugin = FakeReminderNotifications();
    final h = await startWithReminders(
      tester,
      plugin,
      settings: _on,
      size: const Size(320, 800),
    );
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    await openReminders(h);

    for (final text in ['Напоминать о тратах', 'Время']) {
      final row = find
          .ancestor(of: find.text(text), matching: find.byType(InkWell))
          .first;
      expect(
        tester.getSize(row).height,
        greaterThanOrEqualTo(48),
        reason: text,
      );
    }
    expect(tester.takeException(), isNull);
  });
}
