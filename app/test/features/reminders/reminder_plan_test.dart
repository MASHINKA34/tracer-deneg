import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/features/reminders/reminder_plan.dart';
import 'package:milionchik/features/reminders/reminder_settings.dart';
import 'package:shared/shared.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  late tz.Location moscow;
  late tz.Location berlin;

  setUpAll(() {
    tzdata.initializeTimeZones();
    moscow = tz.getLocation('Europe/Moscow');
    berlin = tz.getLocation('Europe/Berlin');
  });

  ReminderPlan plan(
    tz.TZDateTime now, {
    ReminderTime time = ReminderTime.standard,
    bool todayHasExpense = false,
  }) => planReminders(
    now: now,
    time: time,
    todayHasExpense: todayHasExpense,
    zone: now.location,
  );

  test('7 дней вперёд с сегодняшнего, 21:00 по поясу телефона, id - дата', () {
    final result = plan(tz.TZDateTime(moscow, 2026, 10, 19, 18, 40));

    expect(result.todayReminder, TodayReminder.planned);
    expect(result.days, [
      for (var d = 19; d <= 25; d++) LocalDate(2026, 10, d),
    ]);
    expect(result.reminders.map((r) => r.id), [
      for (var d = 19; d <= 25; d++) 20261000 + d,
    ]);
    for (final r in result.reminders) {
      expect(r.at.location, moscow);
      expect((r.at.hour, r.at.minute), (21, 0));
      expect(LocalDate(r.at.year, r.at.month, r.at.day), r.day);
    }
    expect(result.reminders.first.at.toUtc(), DateTime.utc(2026, 10, 19, 18));
  });

  test('трата сегодня: сегодняшнего нет, остальные 6 дней на месте', () {
    final result = plan(
      tz.TZDateTime(moscow, 2026, 10, 19, 9),
      todayHasExpense: true,
    );

    expect(result.todayReminder, TodayReminder.expenseRecorded);
    expect(result.days.first, LocalDate(2026, 10, 20));
    expect(result.days, hasLength(6));
    expect(result.days.last, LocalDate(2026, 10, 25));
  });

  test('время уже прошло: сегодняшнего нет; ровно в 21:00 - тоже нет', () {
    for (final now in [
      tz.TZDateTime(moscow, 2026, 10, 19, 21, 30),
      tz.TZDateTime(moscow, 2026, 10, 19, 21),
    ]) {
      final result = plan(now);
      expect(result.todayReminder, TodayReminder.timePassed, reason: '$now');
      expect(result.days.first, LocalDate(2026, 10, 20), reason: '$now');
      expect(result.days, hasLength(6), reason: '$now');
    }
  });

  test('своё время 07:05 и переход через месяц и год', () {
    final result = plan(
      tz.TZDateTime(moscow, 2026, 12, 29, 6, 59),
      time: const ReminderTime(7, 5),
    );

    expect(result.days, [
      LocalDate(2026, 12, 29),
      LocalDate(2026, 12, 30),
      LocalDate(2026, 12, 31),
      LocalDate(2027, 1, 1),
      LocalDate(2027, 1, 2),
      LocalDate(2027, 1, 3),
      LocalDate(2027, 1, 4),
    ]);
    expect(result.reminders.map((r) => r.id), contains(20270101));
    expect(result.reminders.map((r) => (r.at.hour, r.at.minute)).toSet(), {
      (7, 5),
    });
  });

  test('переход на зимнее время в Берлине: 21:00 по часам в оба дня', () {
    final result = plan(tz.TZDateTime(berlin, 2026, 10, 24, 12));

    final saturday = result.reminders[0].at;
    final sunday = result.reminders[1].at;
    expect((saturday.hour, sunday.hour), (21, 21));
    expect(saturday.toUtc(), DateTime.utc(2026, 10, 24, 19));
    expect(sunday.toUtc(), DateTime.utc(2026, 10, 25, 20));
  });

  test('пояс неизвестен: время по часам телефона, момент в UTC', () {
    final now = DateTime(2026, 10, 19, 18, 40);
    final result = planReminders(
      now: now,
      time: ReminderTime.standard,
      todayHasExpense: false,
      zone: null,
    );

    expect(result.reminders, hasLength(7));
    expect(result.reminders.first.at.location, tz.UTC);
    expect(
      result.reminders.first.at.toUtc(),
      DateTime(2026, 10, 19, 21).toUtc(),
    );
  });

  test('день по id уведомления: верный - дата, мусор - null', () {
    expect(reminderDayOf(20261019), LocalDate(2026, 10, 19));
    expect(
      reminderDayOf(reminderIdFor(LocalDate(2027, 2, 28))),
      LocalDate(2027, 2, 28),
    );
    expect(reminderDayOf(null), isNull);
    expect(reminderDayOf(0), isNull);
    expect(reminderDayOf(20260230), isNull);
    expect(reminderDayOf(20261300), isNull);
  });

  test('время напоминания: минуты от полуночи туда и обратно, 24:00 нет', () {
    expect(ReminderTime.fromMinutes(1260), ReminderTime.standard);
    expect(ReminderTime.fromMinutes(0), const ReminderTime(0, 0));
    expect(ReminderTime.fromMinutes(1439), const ReminderTime(23, 59));
    expect(ReminderTime.fromMinutes(1440), isNull);
    expect(ReminderTime.fromMinutes(-1), isNull);
    expect(const ReminderTime(7, 5).minutes, 425);
    expect('${const ReminderTime(7, 5)}', '07:05');
  });
}
