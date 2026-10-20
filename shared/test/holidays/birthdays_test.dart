import 'package:shared/shared.dart';
import 'package:test/test.dart';

MemberProfile member(String id, MonthDay? birthday) => MemberProfile(
  userId: id,
  displayName: 'Участник $id',
  avatarColor: CategoryColor.blue,
  birthday: birthday,
);

void main() {
  group('upcomingBirthdays', () {
    final today = LocalDate(2026, 11, 29);

    test('0–7 дней, без себя и без даты, ближайшие первыми', () {
      final result = upcomingBirthdays(
        [
          member('dima', MonthDay(12, 2)),
          member('anya', MonthDay(11, 29)),
          member('late', MonthDay(12, 7)),
          member('none', null),
          member('me', MonthDay(11, 30)),
          member('edge', MonthDay(12, 6)),
        ],
        today,
        excludeUserId: 'me',
      );
      expect(result.map((b) => '${b.member.userId}:${b.daysUntil}'), [
        'anya:0',
        'dima:3',
        'edge:7',
      ]);
      expect(result.first.isToday, isTrue);
      expect(result[1].date, LocalDate(2026, 12, 2));
      expect(result[1].isToday, isFalse);
    });

    test('через Новый год', () {
      final result = upcomingBirthdays([
        member('jan', MonthDay(1, 2)),
      ], LocalDate(2026, 12, 28));
      expect(result.single.date, LocalDate(2027, 1, 2));
      expect(result.single.daysUntil, 5);
    });

    test('29 февраля в невисокосный год — 28-го', () {
      final result = upcomingBirthdays([
        member('leap', MonthDay(2, 29)),
      ], LocalDate(2027, 2, 25));
      expect(result.single.date, LocalDate(2027, 2, 28));
      expect(result.single.daysUntil, 3);
    });

    test('при равном сроке — по userId', () {
      final result = upcomingBirthdays([
        member('b', MonthDay(12, 1)),
        member('a', MonthDay(12, 1)),
      ], today);
      expect(result.map((b) => b.member.userId), ['a', 'b']);
    });

    test('равенство и текст', () {
      final a = upcomingBirthdays([member('x', MonthDay(12, 1))], today);
      final b = upcomingBirthdays([member('x', MonthDay(12, 1))], today);
      expect(a.single, b.single);
      expect(a.single.hashCode, b.single.hashCode);
      expect(a.single.toString(), 'UpcomingBirthday(x on 2026-12-01 in 2 d)');
    });
  });
}
