import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/auth_gate.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:milionchik/features/auth/login_screen.dart';
import 'package:milionchik/features/profile/delete_account_screen.dart';
import 'package:milionchik/features/reminders/reminder_settings.dart';
import 'package:milionchik/ui/components/button.dart';
import 'package:milionchik/ui/components/dialog.dart';

import '../../data/api/fake_api_adapter.dart';
import '../auth/session_expired_fixture.dart' show testUnmounting;
import '../profile/profile_harness.dart';
import 'reminder_fakes.dart';
import 'reminders_harness.dart';

const _on = ReminderSettings(enabled: true, time: ReminderTime(21, 30));

FakeReply _server(FakeCall call) {
  if (call.path.endsWith('/auth/logout')) return const FakeReply(204);
  if (call.method == 'DELETE' && call.path.endsWith('/account')) {
    return const FakeReply(204);
  }
  throw StateError('unexpected ${call.method} ${call.path}');
}

Future<ProfileHarness> _start(
  WidgetTester tester,
  FakeReminderNotifications plugin,
) async {
  final h = await startWithReminders(
    tester,
    plugin,
    settings: _on,
    server: _server,
    overrides: [signInRequiredProvider.overrideWithValue(true)],
  );
  await tester.runAsync(() async {
    final prefs = DriftPrefsRepository(h.db);
    await prefs.setBool(PrefKeys.remindersEnabled, true);
    await prefs.setInt(PrefKeys.reminderMinutes, _on.time.minutes);
  });
  expect(plugin.pendingDays, octoberDays(19, 25));
  return h;
}

Future<void> _expectCancelledAndKept(
  ProfileHarness h,
  FakeReminderNotifications plugin,
  String reason,
) async {
  expect(find.byType(LoginScreen), findsOneWidget);
  expect(plugin.pending, isEmpty);
  expect(plugin.calls.last, 'cancelAll');
  expect(
    reminderLines(h, Level.INFO),
    contains(
      matches('^all reminders cancelled: $reason reason=$reason in \\d+ms\$'),
    ),
  );
  expect(await storedReminders(h), (true, 1290));
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testUnmounting('выход из аккаунта снимает все напоминания, а настройка '
      'напоминаний остаётся на телефоне', (tester) async {
    final plugin = FakeReminderNotifications();
    final h = await _start(tester, plugin);
    await h.openProfile();
    expect(h.valueOf('Напоминания'), 'В 21:30');

    await h.tap(h.row('Выйти'));
    await h.tap(
      find.descendant(
        of: find.byType(AppDialog),
        matching: find.widgetWithText(AppButton, 'Выйти'),
      ),
    );

    await _expectCancelledAndKept(h, plugin, 'sign-out');
  });

  testUnmounting('удаление аккаунта тоже снимает все напоминания', (
    tester,
  ) async {
    final plugin = FakeReminderNotifications();
    final h = await _start(tester, plugin);
    await h.openProfile();
    await h.tap(h.row('Удалить аккаунт'));
    expect(find.byType(DeleteAccountScreen), findsOneWidget);

    await h.enter('Введи пароль, чтобы подтвердить', 'parol-kilo-lima-mike');
    await h.tap(find.widgetWithText(AppButton, 'Удалить навсегда'));

    await _expectCancelledAndKept(h, plugin, 'account-delete');
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });
}
