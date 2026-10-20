import 'dart:convert';

import 'package:shared/shared.dart';
import 'package:test/test.dart';

final created = DateTime.utc(2026, 10, 19, 15, 40, 12, 345);
final updated = DateTime.utc(2026, 10, 19, 16, 0, 0, 1);

/// Объект → JSON-строка → объект, как по сети.
T roundTrip<T>(Map<String, Object?> json, T Function(Object?) parse) =>
    parse(jsonDecode(jsonEncode(json)));

Expense expense({String comment = 'Кофе с собой'}) => Expense(
  id: 'e1',
  budgetId: 'b1',
  categoryId: 'c1',
  amount: const Money(14990),
  spentOn: LocalDate(2026, 10, 19),
  comment: comment,
  authorId: 'u1',
  recurringId: 'r1',
  recurringMonth: YearMonth(2026, 10),
  createdAt: created,
  updatedAt: updated,
  updatedBy: 'u1',
  seq: 42,
);

void main() {
  group('моменты времени', () {
    test('единый вид: UTC с миллисекундами', () {
      expect(encodeInstant(created), '2026-10-19T15:40:12.345Z');
      final withMicros = DateTime.utc(2026, 10, 19, 15, 40, 12, 345, 678);
      expect(normalizeInstant(withMicros), created);
      expect(encodeInstant(withMicros), '2026-10-19T15:40:12.345Z');
    });

    test('разбор со смещением переводится в UTC', () {
      expect(decodeInstant('2026-10-19T18:40:12.345+03:00'), created);
      expect(decodeInstant('2026-10-19T15:40:12.345Z'), created);
      expect(decodeInstant('2026-10-19T15:40:12.345678Z'), created);
    });

    test('без зоны — ошибка', () {
      expect(
        () => decodeInstant('2026-10-19T15:40:12.345'),
        throwsFormatException,
      );
    });
  });

  group('Expense', () {
    test('JSON: имена полей и форматы', () {
      expect(expense().toJson(), {
        'id': 'e1',
        'budgetId': 'b1',
        'categoryId': 'c1',
        'amountKopecks': 14990,
        'spentOn': '2026-10-19',
        'comment': 'Кофе с собой',
        'authorId': 'u1',
        'recurringId': 'r1',
        'recurringMonth': '2026-10',
        'createdAt': '2026-10-19T15:40:12.345Z',
        'updatedAt': '2026-10-19T16:00:00.001Z',
        'updatedBy': 'u1',
        'deletedAt': null,
        'seq': 42,
      });
    });

    test('туда и обратно без потерь', () {
      final original = expense();
      expect(roundTrip(original.toJson(), Expense.fromJson), original);
      expect(original.hashCode, expense().hashCode);
      expect(original.syncEntity, SyncEntity.expense);
    });

    test('необязательные поля и пустой комментарий', () {
      final json = expense().toJson()
        ..remove('comment')
        ..['recurringId'] = null
        ..['recurringMonth'] = null
        ..remove('seq');
      final parsed = Expense.fromJson(json);
      expect(parsed.comment, '');
      expect(parsed.recurringId, isNull);
      expect(parsed.recurringMonth, isNull);
      expect(parsed.seq, isNull);
    });

    test('время с микросекундами и не в UTC хранится в едином виде', () {
      final local = Expense(
        id: 'e',
        budgetId: 'b',
        categoryId: 'c',
        amount: const Money(1),
        spentOn: LocalDate(2026, 10, 19),
        authorId: 'u',
        createdAt: DateTime.utc(2026, 10, 19, 15, 40, 12, 345, 999).toLocal(),
        updatedAt: created,
        updatedBy: 'u',
      );
      expect(local.createdAt, created);
      expect(local.createdAt.isUtc, isTrue);
    });

    test('copyWith: надгробие ставится и снимается, прочее не меняется', () {
      final deletedAt = DateTime.utc(2026, 10, 20);
      final deleted = expense().copyWith(
        deletedAt: deletedAt,
        updatedAt: deletedAt,
      );
      expect(deleted.isDeleted, isTrue);
      expect(deleted.deletedAt, deletedAt);
      expect(deleted.amount, const Money(14990));
      expect(deleted.seq, 42);
      final restored = deleted.copyWith(deletedAt: null, seq: null);
      expect(restored.isDeleted, isFalse);
      expect(restored.seq, isNull);
      final moved = expense().copyWith(
        budgetId: 'b2',
        categoryId: 'c2',
        amount: const Money(100),
        spentOn: LocalDate(2026, 10, 1),
        comment: '',
        updatedBy: 'u2',
      );
      expect(moved.budgetId, 'b2');
      expect(moved.categoryId, 'c2');
      expect(moved.amount, const Money(100));
      expect(moved.spentOn, LocalDate(2026, 10, 1));
      expect(moved.comment, '');
      expect(moved.updatedBy, 'u2');
      expect(moved.id, 'e1');
      expect(moved.createdAt, created);
    });

    test('в toString нет суммы и комментария', () {
      final text = expense(comment: 'секрет').toString();
      expect(text, contains('e1'));
      expect(text, isNot(contains('секрет')));
      expect(text, isNot(contains('14990')));
    });

    test('ошибки разбора называют поле', () {
      final noAmount = expense().toJson()..remove('amountKopecks');
      expect(
        () => Expense.fromJson(noAmount),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'Expense.amountKopecks: expected int, got nothing',
          ),
        ),
      );
      final badType = expense().toJson()..['amountKopecks'] = '149,90';
      expect(
        () => Expense.fromJson(badType),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'Expense.amountKopecks: expected int, got String',
          ),
        ),
      );
      final badDate = expense().toJson()..['spentOn'] = '19.10.2026';
      expect(() => Expense.fromJson(badDate), throwsFormatException);
      final badMonth = expense().toJson()..['recurringMonth'] = '2026-13';
      expect(() => Expense.fromJson(badMonth), throwsFormatException);
      final naive = expense().toJson()..['updatedAt'] = '2026-10-19T16:00:00';
      expect(() => Expense.fromJson(naive), throwsFormatException);
      expect(() => Expense.fromJson('nope'), throwsFormatException);
      expect(() => Expense.fromJson(null), throwsFormatException);
    });
  });

  group('Budget и BudgetMember', () {
    final budget = Budget(
      id: 'b1',
      kind: BudgetKind.shared,
      name: 'Семья',
      emoji: '🏠',
      ownerId: 'u1',
      createdAt: created,
      updatedAt: updated,
      updatedBy: 'u1',
    );

    test('туда и обратно', () {
      expect(roundTrip(budget.toJson(), Budget.fromJson), budget);
      expect(budget.toJson()['kind'], 'shared');
      expect(
        budget.hashCode,
        roundTrip(budget.toJson(), Budget.fromJson).hashCode,
      );
      expect(budget.syncEntity, SyncEntity.budget);
      expect(budget.toString(), isNot(contains('Семья')));
    });

    test('copyWith', () {
      final renamed = budget.copyWith(
        kind: BudgetKind.personal,
        name: 'Дом',
        emoji: '🏡',
        ownerId: 'u2',
        updatedAt: created,
        updatedBy: 'u2',
        deletedAt: updated,
        seq: 7,
      );
      expect(renamed.name, 'Дом');
      expect(renamed.kind, BudgetKind.personal);
      expect(renamed.emoji, '🏡');
      expect(renamed.ownerId, 'u2');
      expect(renamed.updatedBy, 'u2');
      expect(renamed.isDeleted, isTrue);
      expect(renamed.seq, 7);
      expect(renamed.copyWith(), renamed);
    });

    test('неизвестный вид бюджета — ошибка', () {
      final json = budget.toJson()..['kind'] = 'family';
      expect(
        () => Budget.fromJson(json),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Budget.kind: unknown value "family"'),
          ),
        ),
      );
    });

    test('участник', () {
      final member = BudgetMember(
        budgetId: 'b1',
        userId: 'u2',
        role: MemberRole.member,
        avatarColor: CategoryColor.orange,
        joinedAt: created,
      );
      expect(roundTrip(member.toJson(), BudgetMember.fromJson), member);
      expect(member.isActive, isTrue);
      expect(member.toJson()['role'], 'member');
      final left = BudgetMember(
        budgetId: 'b1',
        userId: 'u2',
        role: MemberRole.member,
        avatarColor: CategoryColor.orange,
        joinedAt: created,
        leftAt: updated,
      );
      expect(left.isActive, isFalse);
      expect(roundTrip(left.toJson(), BudgetMember.fromJson), left);
      expect(left.hashCode, isNot(member.hashCode));
      expect(left.toString(), contains('active=false'));
    });
  });

  group('Category', () {
    final category = Category(
      id: 'c1',
      budgetId: 'b1',
      name: 'Кафе',
      emoji: '☕',
      color: CategoryColor.orange,
      sortOrder: 1,
      isSystem: false,
      updatedAt: updated,
      updatedBy: 'u1',
    );

    test('туда и обратно, «Другое» без цвета', () {
      expect(roundTrip(category.toJson(), Category.fromJson), category);
      final other = category.copyWith(color: null, name: 'Другое');
      expect(other.toJson()['color'], isNull);
      expect(roundTrip(other.toJson(), Category.fromJson), other);
      expect(category.hashCode, category.copyWith().hashCode);
      expect(category.syncEntity, SyncEntity.category);
      expect(category.toString(), isNot(contains('Кафе')));
    });

    test('copyWith', () {
      final changed = category.copyWith(
        emoji: '🍰',
        sortOrder: 3,
        updatedAt: created,
        updatedBy: 'u2',
        deletedAt: created,
        seq: 5,
      );
      expect(changed.emoji, '🍰');
      expect(changed.sortOrder, 3);
      expect(changed.updatedBy, 'u2');
      expect(changed.isDeleted, isTrue);
      expect(changed.seq, 5);
      expect(changed.color, CategoryColor.orange);
    });
  });

  group('RecurringRule', () {
    final rule = RecurringRule(
      id: 'r1',
      budgetId: 'b1',
      categoryId: 'c1',
      title: 'Интернет',
      amount: const Money.rubles(650),
      dayOfMonth: 24,
      startMonth: YearMonth(2026, 7),
      createdAt: created,
      updatedAt: updated,
      updatedBy: 'u1',
    );

    test('туда и обратно', () {
      expect(roundTrip(rule.toJson(), RecurringRule.fromJson), rule);
      expect(rule.toJson()['startMonth'], '2026-07');
      expect(rule.hashCode, rule.copyWith().hashCode);
      expect(rule.syncEntity, SyncEntity.recurring);
      expect(rule.toString(), isNot(contains('Интернет')));
    });

    test('copyWith', () {
      final changed = rule.copyWith(
        budgetId: 'b2',
        categoryId: 'c2',
        title: 'Связь',
        amount: const Money.rubles(700),
        dayOfMonth: 31,
        startMonth: YearMonth(2026, 8),
        updatedAt: created,
        updatedBy: 'u2',
        deletedAt: created,
        seq: 1,
      );
      expect(changed.title, 'Связь');
      expect(changed.dayOfMonth, 31);
      expect(changed.startMonth, YearMonth(2026, 8));
      expect(changed.amount, const Money.rubles(700));
      expect(changed.budgetId, 'b2');
      expect(changed.categoryId, 'c2');
      expect(changed.isDeleted, isTrue);
      expect(changed.seq, 1);
    });
  });

  group('MemberProfile', () {
    test('туда и обратно, с датой рождения и без', () {
      final withBirthday = MemberProfile(
        userId: 'u2',
        displayName: 'Дима',
        avatarColor: CategoryColor.teal,
        birthday: MonthDay(12, 2),
      );
      expect(withBirthday.toJson()['birthdayMonth'], 12);
      expect(withBirthday.toJson()['birthdayDay'], 2);
      expect(
        roundTrip(withBirthday.toJson(), MemberProfile.fromJson),
        withBirthday,
      );
      const without = MemberProfile(
        userId: 'u3',
        displayName: 'Аня',
        avatarColor: CategoryColor.rose,
      );
      expect(roundTrip(without.toJson(), MemberProfile.fromJson), without);
      expect(without.hashCode, isA<int>());
      expect(withBirthday.toString(), isNot(contains('Дима')));
    });
  });

  group('User', () {
    final user = User(
      id: 'u1',
      login: 'anna',
      displayName: 'Аня',
      birthday: MonthDay(10, 31),
      holidaysDisabled: {'women', 'labour'},
      createdAt: created,
    );

    test('туда и обратно, ключи праздников отсортированы', () {
      expect(user.toJson()['holidaysDisabled'], ['labour', 'women']);
      expect(user.toJson()['holidaysEnabled'], isTrue);
      expect(roundTrip(user.toJson(), User.fromJson), user);
      expect(user.hashCode, roundTrip(user.toJson(), User.fromJson).hashCode);
      expect(user.toString(), isNot(contains('anna')));
    });

    test('настройки праздников: неизвестные ключи пропускаются', () {
      final withUnknown = user.copyWith(
        holidaysDisabled: {'women', 'future_holiday'},
        holidaysEnabled: false,
      );
      expect(
        withUnknown.holidaySettings,
        HolidaySettings(
          enabled: false,
          disabled: {HolidayKey.women},
          birthday: MonthDay(10, 31),
        ),
      );
      // Ключ из будущей версии не теряется.
      expect(roundTrip(withUnknown.toJson(), User.fromJson).holidaysDisabled, {
        'women',
        'future_holiday',
      });
    });

    test('copyWith: дату рождения можно очистить', () {
      final cleared = user.copyWith(birthday: null, displayName: 'Анна');
      expect(cleared.birthday, isNull);
      expect(cleared.displayName, 'Анна');
      expect(cleared.toJson()['birthdayMonth'], isNull);
      expect(user.copyWith(), user);
    });

    test('дата рождения из одного поля — ошибка', () {
      final json = user.toJson()..['birthdayDay'] = null;
      expect(() => User.fromJson(json), throwsFormatException);
    });

    test('ключи праздников — список строк', () {
      final json = user.toJson()..['holidaysDisabled'] = ['women', 1];
      expect(() => User.fromJson(json), throwsFormatException);
    });
  });

  group('ClientErrorReport', () {
    const report = ClientErrorReport(
      appVersion: '1.0.0+1',
      androidSdk: 30,
      deviceModel: 'Pixel 5',
      kind: ClientErrorKind.userReport,
      message: 'StateError: boom',
      stack: '#0 main',
      logs: 'line',
    );

    test('туда и обратно, вид user_report', () {
      expect(report.toJson()['kind'], 'user_report');
      expect(roundTrip(report.toJson(), ClientErrorReport.fromJson), report);
      expect(report.hashCode, isA<int>());
      expect(report.toString(), contains('user_report'));
      expect(maxClientErrorLogsBytes, 204800);
    });

    test('неизвестный вид — ошибка', () {
      final json = report.toJson()..['kind'] = 'panic';
      expect(() => ClientErrorReport.fromJson(json), throwsFormatException);
      expect(ClientErrorKind.fromCode('crash'), ClientErrorKind.crash);
    });
  });
}
