import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/auth_support.dart';
import 'support/shared_budget_support.dart';
import 'support/sync_support.dart';
import 'support/test_support.dart';

Map<String, MemberProfile> _byUser(Iterable<MemberProfile> profiles) => {
  for (final profile in profiles) profile.userId: profile,
};

void main() {
  late AuthHarness api;
  late SharedBudgetFixture fixture;
  late TestUser anna;
  late TestUser boris;
  late TestUser vera;
  late String early;
  late String later;

  setUp(() async {
    LogCapture();
    api = await AuthHarness.start();
    fixture = SharedBudgetFixture(api);
    anna = await registerTestUser(api, 'anna', displayName: 'Аня');
    boris = await registerTestUser(api, 'boris', displayName: 'Борис');
    vera = await registerTestUser(api, 'vera', displayName: 'Вера');
  });

  Future<void> createBudgets({required bool annaOwnsEarly}) async {
    final earlyOwner = annaOwnsEarly ? anna : vera;
    final earlyMember = annaOwnsEarly ? vera : anna;
    early = await fixture.budget(ownerId: earlyOwner.id, name: 'Дача');
    await fixture.member(
      early,
      earlyOwner.id,
      role: MemberRole.owner,
      color: annaOwnsEarly ? CategoryColor.yellow : CategoryColor.green,
      joinedDaysAgo: 10,
    );
    await fixture.member(
      early,
      earlyMember.id,
      role: MemberRole.member,
      color: annaOwnsEarly ? CategoryColor.green : CategoryColor.yellow,
      joinedDaysAgo: 9,
    );
    await fixture.member(
      early,
      boris.id,
      role: MemberRole.member,
      color: CategoryColor.red,
      joinedDaysAgo: 8,
    );

    later = await fixture.budget(ownerId: vera.id);
    await fixture.member(
      later,
      vera.id,
      role: MemberRole.owner,
      color: CategoryColor.purple,
      joinedDaysAgo: 7,
    );
    await fixture.member(
      later,
      anna.id,
      role: MemberRole.member,
      color: CategoryColor.orange,
      joinedDaysAgo: 6,
    );
    await fixture.member(
      later,
      boris.id,
      role: MemberRole.member,
      color: CategoryColor.blue,
      joinedDaysAgo: 3,
    );
  }

  Future<void> leave(String budgetId, String userId) => api.db.execute(
    'UPDATE budget_members SET left_at = now() '
    r'WHERE budget_id = $1::uuid AND user_id = $2::uuid',
    parameters: [budgetId, userId],
  );

  Future<void> leaveAsOwner(String budgetId, String userId) async {
    final heir = await api.db.execute(
      'SELECT user_id FROM budget_members '
      r'WHERE budget_id = $1::uuid AND user_id <> $2::uuid '
      'AND left_at IS NULL ORDER BY joined_at, user_id LIMIT 1',
      parameters: [budgetId, userId],
    );
    final heirId = heir.single.first! as String;
    await api.db.execute(
      "UPDATE budget_members SET role = 'owner' "
      r'WHERE budget_id = $1::uuid AND user_id = $2::uuid',
      parameters: [budgetId, heirId],
    );
    await api.db.execute(
      "UPDATE budget_members SET role = 'member', left_at = now() "
      r'WHERE budget_id = $1::uuid AND user_id = $2::uuid',
      parameters: [budgetId, userId],
    );
    await api.db.execute(
      r'UPDATE budgets SET owner_id = $2::uuid, updated_at = now(), '
      r'updated_by = $3::uuid WHERE id = $1::uuid',
      parameters: [budgetId, heirId, userId],
    );
  }

  Future<void> deleteBudget(String budgetId, String by) => api.db.execute(
    'UPDATE budgets SET deleted_at = now(), updated_at = now(), '
    r'updated_by = $2::uuid WHERE id = $1::uuid',
    parameters: [budgetId, by],
  );

  Future<void> expectIncrementalMatchesFull({
    required Future<void> Function() exit,
    required bool earlyRemovedForAnna,
  }) async {
    final start = await pullAs(api, anna);
    expect(
      _byUser(start.profiles)[boris.id]?.avatarColor,
      CategoryColor.red,
      reason: 'Борис раньше всего вступил в «Дачу» — цвет оттуда',
    );

    await exit();

    final incremental = await pullUntilDone(api, anna, cursor: start.cursor);
    final full = await pullAs(api, anna);
    final fullProfiles = _byUser(full.profiles);
    expect(fullProfiles[boris.id]?.avatarColor, CategoryColor.blue);

    final changed = _byUser(incremental.all((p) => p.profiles));
    expect(changed[boris.id], fullProfiles[boris.id]);
    expect({..._byUser(start.profiles), ...changed}, fullProfiles);
    expect(
      incremental.all((p) => p.removedBudgetIds),
      earlyRemovedForAnna ? [early] : isEmpty,
    );

    final again = await pullAs(api, anna, cursor: incremental.cursor);
    expect(again.totalCount, 0);
  }

  group('профиль участника в pull по курсору совпадает с полной загрузкой', () {
    test('участник ушёл из бюджета, куда вступил раньше всего', () async {
      await createBudgets(annaOwnsEarly: false);
      await expectIncrementalMatchesFull(
        exit: () => leave(early, boris.id),
        earlyRemovedForAnna: false,
      );
    });

    test('я ушла из этого бюджета, передав права создателя', () async {
      await createBudgets(annaOwnsEarly: true);
      await expectIncrementalMatchesFull(
        exit: () => leaveAsOwner(early, anna.id),
        earlyRemovedForAnna: true,
      );
    });

    test('меня исключили из этого бюджета', () async {
      await createBudgets(annaOwnsEarly: false);
      await expectIncrementalMatchesFull(
        exit: () => leave(early, anna.id),
        earlyRemovedForAnna: true,
      );
    });

    test('этот бюджет удалён', () async {
      await createBudgets(annaOwnsEarly: false);
      await expectIncrementalMatchesFull(
        exit: () => deleteBudget(early, vera.id),
        earlyRemovedForAnna: true,
      );
    });
  });
}
