import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/features/reminders/reminder_notifications.dart';
import 'package:milionchik/features/reminders/reminder_scheduler.dart';
import 'package:milionchik/features/reminders/reminder_settings.dart';
import 'package:shared/shared.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../data/api/fake_api_adapter.dart' show LogCapture;
import 'reminder_fakes.dart';

const _texts = ReminderTexts(
  title: 'Милиончик',
  body: 'Запишешь траты за сегодня?',
  channelName: 'Напоминания',
  channelDescription: 'Вечернее напоминание записать траты за день',
);

final class _Rig {
  _Rig({
    DateTime? now,
    this.settings = const ReminderSettings(enabled: true),
    FakeReminderNotifications? plugin,
  }) : now = now ?? DateTime(2026, 10, 19, 18, 40),
       plugin = plugin ?? FakeReminderNotifications() {
    scheduler = ReminderScheduler(
      notifications: this.plugin,
      clock: () => Clock(now: () => this.now),
      settings: () => settings,
      accountActive: () => signedIn,
      ownExpenseOn: (day) async {
        checkedDays.add(day);
        final error = expenseCheckError;
        if (error != null) throw error;
        return expenseDays.contains(day);
      },
      texts: _texts,
      taps: taps,
      loadTimeZones: () => zonesLoaded++,
    );
    taps.attach(opened.add);
  }

  DateTime now;
  ReminderSettings settings;
  bool signedIn = true;
  final FakeReminderNotifications plugin;
  final Set<LocalDate> expenseDays = {};
  final List<LocalDate> checkedDays = [];
  Object? expenseCheckError;
  final ReminderTaps taps = ReminderTaps();
  final List<Uri> opened = [];
  int zonesLoaded = 0;
  late final ReminderScheduler scheduler;

  List<LocalDate> days(int from, int to) => [
    for (var d = from; d <= to; d++) LocalDate(2026, 10, d),
  ];
}

void main() {
  late LogCapture logs;

  setUpAll(tzdata.initializeTimeZones);

  setUp(() => logs = LogCapture());

  tearDown(() => logs.dispose());

  Iterable<String> messages([Level level = Level.ALL]) => logs.records
      .where((r) => r.loggerName == 'reminders' && r.level >= level)
      .map((r) => r.message);

  Iterable<String> info() => logs.records
      .where((r) => r.loggerName == 'reminders' && r.level == Level.INFO)
      .map((r) => r.message);

  test('старт: 7 уведомлений с сегодняшнего на 21:00 по Москве, тексты и '
      'id-даты, info со списком дат', () async {
    final rig = _Rig();

    await rig.scheduler.start();

    expect(rig.plugin.pendingDays, rig.days(19, 25));
    final moscow = tz.getLocation('Europe/Moscow');
    for (final request in rig.plugin.pending.values) {
      expect(request.at.location, moscow);
      expect((request.at.hour, request.at.minute), (21, 0));
      expect(request.id, 20261000 + request.day.day);
    }
    expect(rig.plugin.texts, same(_texts));
    expect(rig.plugin.calls, ['initialize', 'cancelPending']);
    expect(rig.checkedDays, [LocalDate(2026, 10, 19)]);
    expect(rig.zonesLoaded, 1);
    expect(
      info().last,
      matches(
        r'^reminders planned count=7 dates=2026-10-19,2026-10-20,2026-10-21,'
        r'2026-10-22,2026-10-23,2026-10-24,2026-10-25 at=21:00 '
        r'tz=Europe/Moscow today=2026-10-19 planned reason=startup in \d+ms$',
      ),
    );
    expect(messages(Level.WARNING), isEmpty);
  });

  test('трата сегодня в любом бюджете отменяет только сегодняшнее, '
      'причина в info', () async {
    final rig = _Rig();
    await rig.scheduler.start();

    await rig.scheduler.cancelToday(
      'expense saved for today: expense create id=e1 budgetId=b-family '
      'day=2026-10-19',
    );

    expect(rig.plugin.pendingDays, rig.days(20, 25));
    expect(rig.plugin.calls.last, 'cancel 20261019');
    expect(
      info().last,
      matches(
        r'^reminder for today 2026-10-19 cancelled id=20261019: expense '
        r'saved for today: expense create id=e1 budgetId=b-family '
        r'day=2026-10-19 in \d+ms$',
      ),
    );
  });

  test('трата сегодня уже есть при старте: сегодняшнего нет сразу, '
      'в логе причина', () async {
    final rig = _Rig()..expenseDays.add(LocalDate(2026, 10, 19));

    await rig.scheduler.start();

    expect(rig.plugin.pendingDays, rig.days(20, 25));
    expect(info().last, contains('count=6 dates=2026-10-20,'));
    expect(
      info().last,
      contains('today=2026-10-19 skipped: expense recorded today'),
    );
  });

  test('смена времени перепланирует: старые сняты, 7 новых на 07:30 с '
      'завтрашнего', () async {
    final rig = _Rig();
    await rig.scheduler.start();

    rig.settings = const ReminderSettings(
      enabled: true,
      time: ReminderTime(7, 30),
    );
    await rig.scheduler.reschedule('settings changed');

    expect(rig.plugin.pendingDays, rig.days(20, 25));
    expect(
      rig.plugin.pending.values.map((r) => (r.at.hour, r.at.minute)).toSet(),
      {(7, 30)},
    );
    expect(rig.plugin.calls, ['initialize', 'cancelPending', 'cancelPending']);
    expect(
      info().last,
      allOf(
        contains('count=6 '),
        contains('at=07:30 '),
        contains('today=2026-10-19 skipped: time already passed'),
        contains('reason=settings changed'),
      ),
    );
  });

  test('выключили - все уведомления сняты; выключено с запуска - плагин '
      'не трогаем', () async {
    final rig = _Rig();
    await rig.scheduler.start();

    rig.settings = const ReminderSettings();
    await rig.scheduler.reschedule('settings changed');

    expect(rig.plugin.pending, isEmpty);
    expect(rig.plugin.calls.last, 'cancelAll');
    expect(
      info().last,
      matches(
        r'^all reminders cancelled: reminders switched off '
        r'reason=settings changed in \d+ms$',
      ),
    );

    final off = _Rig(settings: const ReminderSettings());
    await off.scheduler.start();
    await off.scheduler.cancelToday('expense saved for today: x');
    await off.scheduler.cancelAll('sign-out');
    expect(off.plugin.calls, isEmpty);
    expect(off.checkedDays, isEmpty);
  });

  test('выход из аккаунта снимает все; без аккаунта при старте ничего не '
      'планируется', () async {
    final rig = _Rig();
    await rig.scheduler.start();

    await rig.scheduler.cancelAll('sign-out');

    expect(rig.plugin.pending, isEmpty);
    expect(
      info().last,
      matches(r'^all reminders cancelled: sign-out reason=sign-out in \d+ms$'),
    );

    final signedOut = _Rig()..signedIn = false;
    await signedOut.scheduler.start();
    expect(signedOut.plugin.calls, ['initialize', 'cancelAll']);
    expect(signedOut.plugin.pending, isEmpty);
    expect(
      info().last,
      contains('all reminders cancelled: no signed-in account reason=startup'),
    );
  });

  test('после входа - снова 7 дней', () async {
    final rig = _Rig()..signedIn = false;
    await rig.scheduler.start();

    rig.signedIn = true;
    await rig.scheduler.reschedule('signed in absent→active');

    expect(rig.plugin.pendingDays, rig.days(19, 25));
  });

  test('возврат в приложение: тот же день и пояс - без перепланирования; '
      'новый день или пояс - заново', () async {
    final rig = _Rig();
    await rig.scheduler.start();
    final before = List.of(rig.plugin.calls);

    await rig.scheduler.refreshIfStale('app resumed');
    expect(rig.plugin.calls, before);
    expect(
      messages().last,
      'app resumed: reminders planned today 2026-10-19 in tz=Europe/Moscow → '
      'nothing to refresh',
    );

    rig.now = DateTime(2026, 10, 20, 8);
    await rig.scheduler.refreshIfStale('app resumed');
    expect(rig.plugin.pendingDays, rig.days(20, 26));
    expect(
      info().last,
      contains('reason=app resumed, day changed 2026-10-19 → 2026-10-20'),
    );

    rig.plugin.zone = 'Asia/Yekaterinburg';
    await rig.scheduler.refreshIfStale('app resumed');
    expect(
      rig.plugin.pending.values.first.at.location,
      tz.getLocation('Asia/Yekaterinburg'),
    );
    expect(
      info().last,
      contains(
        'tz=Asia/Yekaterinburg today=2026-10-20 planned reason=app resumed, '
        'time zone changed Europe/Moscow → Asia/Yekaterinburg',
      ),
    );
  });

  test('неизвестный пояс: план по часам телефона в UTC и warn', () async {
    final rig = _Rig(plugin: FakeReminderNotifications(zone: 'Mars/Olympus'));

    await rig.scheduler.start();

    expect(rig.plugin.pending, hasLength(7));
    expect(rig.plugin.pending.values.first.at.location, tz.UTC);
    expect(
      messages(Level.WARNING).single,
      startsWith('time zone Mars/Olympus is not in the time zone database'),
    );
    expect(info().last, contains('tz=UTC(phone offset, Mars/Olympus)'));
  });

  test('ошибка плагина при запуске - severe, без падения; следующее '
      'изменение пробует снова', () async {
    final plugin = FakeReminderNotifications()
      ..initError = StateError('channel is not ready');
    final rig = _Rig(plugin: plugin);

    await rig.scheduler.start();

    expect(rig.plugin.pending, isEmpty);
    final severe = logs.records.where(
      (r) => r.loggerName == 'reminders' && r.level == Level.SEVERE,
    );
    expect(severe.single.message, contains('notifications plugin init failed'));
    expect(severe.single.message, contains('channel is not ready'));
    expect(severe.single.stackTrace, isNotNull);

    plugin.initError = null;
    await rig.scheduler.reschedule('settings changed');
    expect(rig.plugin.pending, hasLength(7));
  });

  test('ошибка одного уведомления - severe с датой, итог warn с числом '
      'неудач', () async {
    final plugin = FakeReminderNotifications()
      ..scheduleError = ArgumentError('Invalid icon');
    final rig = _Rig(plugin: plugin);

    await rig.scheduler.start();

    final severe = logs.records
        .where((r) => r.loggerName == 'reminders' && r.level == Level.SEVERE)
        .map((r) => r.message);
    expect(severe, hasLength(7));
    expect(
      severe.first,
      startsWith('reminder for 2026-10-19 not planned id=20261019'),
    );
    expect(
      messages(Level.WARNING).last,
      contains('reminders planned count=0 dates=- '),
    );
    expect(messages(Level.WARNING).last, contains('failed=7 (errors above)'));
  });

  test('проверка траты упала - сегодняшнее остаётся, warn', () async {
    final rig = _Rig()..expenseCheckError = StateError('database is locked');

    await rig.scheduler.start();

    expect(rig.plugin.pendingDays, rig.days(19, 25));
    expect(
      messages(Level.WARNING).single,
      startsWith(
        'reminders: expense check for today 2026-10-19 failed → today\'s '
        'reminder kept',
      ),
    );
  });

  test('тап по уведомлению: тёплый и холодный старт открывают '
      'milionchik://add, в info день и id', () async {
    final rig = _Rig();
    await rig.scheduler.start();

    rig.plugin.tap(20261019);

    expect(rig.opened, [Uri.parse('milionchik://add')]);
    expect(
      info().last,
      'reminder tapped id=20261019 day=2026-10-19 start=warm → '
      'milionchik://add',
    );

    final cold = _Rig(
      plugin: FakeReminderNotifications(
        launch: const ReminderTap(id: 20261018, payload: 'milionchik://add'),
      ),
    );
    await cold.scheduler.start();
    expect(cold.opened, [Uri.parse('milionchik://add')]);
    expect(
      info(),
      contains(
        'reminder tapped id=20261018 day=2026-10-18 start=cold → '
        'milionchik://add',
      ),
    );
  });

  test('тап до того, как приложение показано, ждёт его', () async {
    final taps = ReminderTaps();
    final opened = <Uri>[];

    taps.deliver(Uri.parse('milionchik://add'));
    expect(opened, isEmpty);
    taps.attach(opened.add);

    expect(opened, [Uri.parse('milionchik://add')]);
  });

  test('часы телефона позади плана (debug-подмена даты): прошедшие дни не '
      'планируются, в итоге их число', () async {
    final plugin = FakeReminderNotifications(
      now: () => DateTime(2026, 10, 22, 12),
    );
    final rig = _Rig(plugin: plugin);

    await rig.scheduler.start();

    expect(rig.plugin.pendingDays, rig.days(22, 25));
    expect(
      info().last,
      contains('pastByPhoneClock=3 (2026-10-19,2026-10-20,2026-10-21)'),
    );
  });
}
