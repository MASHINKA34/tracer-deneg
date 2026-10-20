import '../models/member_profile.dart';
import '../time/local_date.dart';

/// Через сколько дней (включительно) показываем плашку «Участник».
const int memberBirthdayWindowDays = 7;

/// Ближайший день рождения участника общего бюджета.
final class UpcomingBirthday {
  const UpcomingBirthday({
    required this.member,
    required this.date,
    required this.daysUntil,
  });

  final MemberProfile member;

  /// Дата дня рождения (29.02 в невисокосный год — 28.02).
  final LocalDate date;

  /// Через сколько дней: 0 — сегодня.
  final int daysUntil;

  bool get isToday => daysUntil == 0;

  @override
  bool operator ==(Object other) =>
      other is UpcomingBirthday &&
      other.member == member &&
      other.date == date &&
      other.daysUntil == daysUntil;

  @override
  int get hashCode => Object.hash(member, date, daysUntil);

  @override
  String toString() =>
      'UpcomingBirthday(${member.userId} on $date in $daysUntil d)';
}

/// Дни рождения участников [members] в ближайшие 0–[withinDays] дней от
/// [today] (00-spec §7.6.5), без участника [excludeUserId] (себя).
/// Сортировка: ближайшие первыми, при равенстве — по userId.
List<UpcomingBirthday> upcomingBirthdays(
  Iterable<MemberProfile> members,
  LocalDate today, {
  String? excludeUserId,
  int withinDays = memberBirthdayWindowDays,
}) {
  final result = <UpcomingBirthday>[];
  for (final member in members) {
    final birthday = member.birthday;
    if (birthday == null || member.userId == excludeUserId) continue;
    final date = birthday.nextOnOrAfter(today);
    final days = today.daysUntil(date);
    if (days <= withinDays) {
      result.add(UpcomingBirthday(member: member, date: date, daysUntil: days));
    }
  }
  result.sort((a, b) {
    final byDays = a.daysUntil.compareTo(b.daysUntil);
    return byDays != 0 ? byDays : a.member.userId.compareTo(b.member.userId);
  });
  return result;
}
