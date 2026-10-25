import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/features/expense/new_expense_screen.dart';
import 'package:milionchik/features/month/month_screen.dart';
import 'package:milionchik/features/reminders/reminder_notifications.dart';
import 'package:milionchik/features/reminders/reminder_settings.dart';

import '../auth/session_expired_fixture.dart' show testUnmounting;
import 'reminder_fakes.dart';
import 'reminders_harness.dart';

const _on = ReminderSettings(enabled: true);

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testUnmounting('тап по напоминанию в открытом приложении (профиль) → '
      '«Новая трата» поверх главной', (tester) async {
    final plugin = FakeReminderNotifications();
    final h = await startWithReminders(tester, plugin, settings: _on);
    await h.openProfile();

    plugin.tap(20261019);
    await h.settle();

    expect(find.byType(NewExpenseScreen), findsOneWidget);
    expect(find.byType(MonthScreen, skipOffstage: false), findsOneWidget);
    expect(
      reminderLines(h, Level.INFO),
      contains(
        'reminder tapped id=20261019 day=2026-10-19 start=warm → '
        'milionchik://add',
      ),
    );
    expect(
      h.linesOf('nav', Level.INFO),
      contains(
        endsWith(
          'deep link milionchik://add start=warm from=/profile → '
          '/expense/new over /month',
        ),
      ),
    );
    expect(reminderLines(h, Level.WARNING), isEmpty);
  });

  testUnmounting('приложение запущено тапом по напоминанию → сразу «Новая '
      'трата»', (tester) async {
    final plugin = FakeReminderNotifications(
      launch: const ReminderTap(id: 20261018, payload: 'milionchik://add'),
    );
    final h = await startWithReminders(tester, plugin, settings: _on);

    expect(find.byType(NewExpenseScreen), findsOneWidget);
    expect(
      reminderLines(h, Level.INFO),
      containsAllInOrder([
        matches(
          r'^notifications plugin ready channel=reminders '
          r'launchedByReminder=true in \d+ms$',
        ),
        'reminder tapped id=20261018 day=2026-10-18 start=cold → '
            'milionchik://add',
      ]),
    );
  });

  testUnmounting('чужой payload - warn, всё равно «Новая трата»', (
    tester,
  ) async {
    final plugin = FakeReminderNotifications();
    final h = await startWithReminders(tester, plugin, settings: _on);

    plugin.tap(7, payload: 'something-else');
    await h.settle();

    expect(find.byType(NewExpenseScreen), findsOneWidget);
    expect(
      reminderLines(h, Level.WARNING).single,
      'notification tapped id=7 start=warm with unexpected payload length=14 '
      '→ opening milionchik://add anyway',
    );
  });
}
