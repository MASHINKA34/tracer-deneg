import 'package:shared/shared.dart' show LocalDate, daysInMonth;
import 'package:timezone/timezone.dart' as tz;

import 'reminder_notifications.dart';
import 'reminder_settings.dart';

const int reminderDaysAhead = 7;

int reminderIdFor(LocalDate day) =>
    day.year * 10000 + day.month * 100 + day.day;

LocalDate? reminderDayOf(int? id) {
  if (id == null) return null;
  final year = id ~/ 10000;
  final month = id ~/ 100 % 100;
  final day = id % 100;
  if (year < 1 || year > 9999 || month < 1 || month > 12 || day < 1) {
    return null;
  }
  if (day > daysInMonth(year, month)) return null;
  return LocalDate(year, month, day);
}

enum TodayReminder {
  planned('planned'),
  expenseRecorded('skipped: expense recorded today'),
  timePassed('skipped: time already passed');

  const TodayReminder(this.label);

  final String label;
}

final class ReminderPlan {
  const ReminderPlan({
    required this.today,
    required this.todayReminder,
    required this.reminders,
  });

  final LocalDate today;
  final TodayReminder todayReminder;
  final List<ReminderRequest> reminders;

  List<LocalDate> get days => [for (final r in reminders) r.day];
}

tz.TZDateTime reminderAt(LocalDate day, ReminderTime time, tz.Location? zone) {
  if (zone != null) {
    return tz.TZDateTime(
      zone,
      day.year,
      day.month,
      day.day,
      time.hour,
      time.minute,
    );
  }
  final local = DateTime(day.year, day.month, day.day, time.hour, time.minute);
  return tz.TZDateTime.from(local, tz.UTC);
}

ReminderPlan planReminders({
  required DateTime now,
  required ReminderTime time,
  required bool todayHasExpense,
  required tz.Location? zone,
  int days = reminderDaysAhead,
}) {
  final today = LocalDate.fromDateTime(now);
  var todayReminder = TodayReminder.planned;
  final reminders = <ReminderRequest>[];
  for (var i = 0; i < days; i++) {
    final day = today.addDays(i);
    final at = reminderAt(day, time, zone);
    if (i == 0) {
      if (todayHasExpense) {
        todayReminder = TodayReminder.expenseRecorded;
        continue;
      }
      if (!at.isAfter(now)) {
        todayReminder = TodayReminder.timePassed;
        continue;
      }
    }
    reminders.add(ReminderRequest(id: reminderIdFor(day), day: day, at: at));
  }
  return ReminderPlan(
    today: today,
    todayReminder: todayReminder,
    reminders: reminders,
  );
}
