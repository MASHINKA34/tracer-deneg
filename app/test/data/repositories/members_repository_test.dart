import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

import 'repository_harness.dart';

void main() {
  late RepositoryHarness h;

  setUp(() => h = RepositoryHarness());

  tearDown(() => h.dispose());

  BudgetMember member(
    String userId, {
    DateTime? joinedAt,
    DateTime? leftAt,
    MemberRole role = MemberRole.member,
  }) => BudgetMember(
    budgetId: 'b1',
    userId: userId,
    role: role,
    avatarColor: CategoryColor.orange,
    joinedAt: joinedAt ?? DateTime.utc(2026, 10, 1),
    leftAt: leftAt,
  );

  test(
    'участники из синхронизации: только текущие, по порядку вступления',
    () async {
      final owner = member(
        'u-owner',
        role: MemberRole.owner,
        joinedAt: DateTime.utc(2026, 9, 1),
      );
      final friend = member('u-friend', joinedAt: DateTime.utc(2026, 10, 2));
      final left = member('u-left', leftAt: DateTime.utc(2026, 10, 10));
      await h.members.applyMembersFromServer([friend, left, owner]);

      expect(await h.members.watchByBudget('b1').first, [owner, friend]);
      expect(await h.members.watchByBudget('b2').first, isEmpty);
      expect(await h.outboxRows(), isEmpty);
    },
  );

  test(
    'повторное применение заменяет запись, в том числе снимает leftAt',
    () async {
      await h.members.applyMembersFromServer([
        member('u1', leftAt: DateTime.utc(2026, 10, 10)),
      ]);
      expect(await h.members.watchByBudget('b1').first, isEmpty);

      final back = member('u1', joinedAt: DateTime.utc(2026, 10, 15));
      await h.members.applyMembersFromServer([back]);

      expect(await h.members.watchByBudget('b1').first, [back]);
      expect(await h.db.select(h.db.budgetMembers).get(), hasLength(1));
    },
  );

  test(
    'профили из синхронизации, день рождения снимается повторным применением',
    () async {
      final dima = MemberProfile(
        userId: 'u-dima',
        displayName: 'Дима',
        avatarColor: CategoryColor.green,
        birthday: MonthDay(10, 23),
      );
      await h.members.applyProfilesFromServer([dima]);
      expect(await h.members.watchProfile('u-dima').first, dima);

      const noBirthday = MemberProfile(
        userId: 'u-dima',
        displayName: 'Дима',
        avatarColor: CategoryColor.green,
      );
      await h.members.applyProfilesFromServer([noBirthday]);

      expect(await h.members.watchProfiles().first, [noBirthday]);
      expect(await h.members.watchProfile('u-missing').first, isNull);
      expect(await h.outboxRows(), isEmpty);
    },
  );
}
