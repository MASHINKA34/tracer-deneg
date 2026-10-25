import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/auth_support.dart';
import 'support/budget_support.dart';
import 'support/push_support.dart';
import 'support/shared_budget_support.dart';
import 'support/sync_support.dart';
import 'support/test_support.dart';

void main() {
  late LogCapture logs;
  late AuthHarness api;
  late SharedBudgetFixture fixture;
  late TestUser olga;
  late TestUser boris;
  late TestUser vera;
  late Budget family;
  late String food;

  setUp(() async {
    logs = LogCapture();
    api = await AuthHarness.start();
    fixture = SharedBudgetFixture(api);
    olga = await registerTestUser(api, 'olga', displayName: 'Ольга');
    boris = await registerTestUser(api, 'boris', displayName: 'Борис');
    vera = await registerTestUser(api, 'vera', displayName: 'Вера');
    family = await createSharedBudget(api, olga);
    food = await firstCategoryOf(api, family.id);
    logs.clear();
  });

  Future<void> join(TestUser user) async =>
      joinBudget(api, user, await inviteCodeFor(api, olga, family.id));

  Future<int> cursorOf(TestUser user) async =>
      (await pullUntilDone(api, user)).cursor;

  test('участник выходит → 204: строка остаётся с left_at, у вышедшего '
      'removedBudgetIds, у остальных — его leftAt; траты остаются', () async {
    await join(boris);
    await join(vera);
    final borisExpense = await fixture.expense(family.id, food, boris.id);
    final borisCursor = await cursorOf(boris);
    final olgaCursor = await cursorOf(olga);
    logs.clear();

    final response = await leaveRaw(api, boris, family.id);
    expect(response.status, 204, reason: response.text);

    final row = (await memberRow(api, family.id, boris.id))!;
    expect(row.leftAt, isNotNull);
    expect(row.role, MemberRole.member);
    expect((await storedRow(api, 'expenses', borisExpense))!.deletedAt, isNull);
    expect((await storedRow(api, 'budgets', family.id))!.deletedAt, isNull);

    final borisPull = await pullUntilDone(api, boris, cursor: borisCursor);
    expect(borisPull.all((p) => p.removedBudgetIds), [family.id]);
    expect(borisPull.all((p) => p.budgets), isEmpty);
    expect(
      (await pullUntilDone(api, boris)).all((p) => p.budgets).map((b) => b.id),
      isNot(contains(family.id)),
    );

    final olgaPull = await pullUntilDone(api, olga, cursor: olgaCursor);
    expect(olgaPull.all((p) => p.removedBudgetIds), isEmpty);
    expect(
      olgaPull
          .all((p) => p.members)
          .where((m) => m.userId == boris.id)
          .map((m) => m.isActive),
      [false],
    );

    final push = await pushAs(api, boris, [
      SyncChange.upsert(
        expenseRecord(
          budgetId: family.id,
          categoryId: food,
          authorId: boris.id,
        ),
      ),
    ]);
    expect(push.rejected.map((r) => r.code), [ApiErrorCode.notFound.code]);
    expect(
      logs.text,
      matches(
        RegExp(
          'INFO  \\[budgets\\] budget leave ok result=left '
          'budgetId=${family.id} userId=${boris.id} role=member '
          'in \\d+ms rid=',
        ),
      ),
    );
  });

  test('создатель выходит → владельцем становится самый ранний участник, '
      'прежние коды отменены', () async {
    await join(boris);
    await join(vera);
    final code = await inviteCodeFor(api, olga, family.id);
    final olgaCursor = await cursorOf(olga);
    final borisCursor = await cursorOf(boris);
    logs.clear();

    final response = await leaveRaw(api, olga, family.id);
    expect(response.status, 204, reason: response.text);

    expect((await storedRow(api, 'budgets', family.id))!['owner_id'], boris.id);
    final olgaRow = (await memberRow(api, family.id, olga.id))!;
    expect(olgaRow.role, MemberRole.member);
    expect(olgaRow.leftAt, isNotNull);
    expect((await memberRow(api, family.id, boris.id))!.role, MemberRole.owner);
    expect((await memberRow(api, family.id, vera.id))!.role, MemberRole.member);

    final olgaPull = await pullUntilDone(api, olga, cursor: olgaCursor);
    expect(olgaPull.all((p) => p.removedBudgetIds), [family.id]);

    final borisPull = await pullUntilDone(api, boris, cursor: borisCursor);
    expect(borisPull.all((p) => p.budgets).single.ownerId, boris.id);
    expect(
      {
        for (final m in borisPull.all((p) => p.members))
          m.userId: (m.role, m.isActive),
      },
      {olga.id: (MemberRole.member, false), boris.id: (MemberRole.owner, true)},
    );

    final stale = await joinRaw(
      api,
      await registerTestUser(api, 'dima', displayName: 'Дима'),
      code,
    );
    expect(stale.status, 404);
    expect(stale.errorCode, ApiErrorCode.inviteNotFound.code);
    expect((await createInviteRaw(api, boris, family.id)).status, 201);
    expect((await createInviteRaw(api, olga, family.id)).status, 404);
    expect(
      logs.text,
      matches(
        RegExp(
          'INFO  \\[budgets\\] budget leave ok result=transferred '
          'budgetId=${family.id} userId=${olga.id} role=owner '
          'newOwnerId=${boris.id} invitesRevoked=1 in \\d+ms rid=',
        ),
      ),
    );
  });

  test('последний участник выходит → бюджет помечен удалённым, траты, '
      'регулярные и категории стёрты, строки бюджета и участника '
      'остаются', () async {
    final expenses = [
      await fixture.expense(family.id, food, olga.id),
      await fixture.expense(family.id, food, olga.id),
    ];
    final rule = await fixture.recurring(family.id, food, olga.id);
    final code = await inviteCodeFor(api, olga, family.id);
    final olgaCursor = await cursorOf(olga);
    logs.clear();

    final response = await leaveRaw(api, olga, family.id);
    expect(response.status, 204, reason: response.text);

    final budget = (await storedRow(api, 'budgets', family.id))!;
    expect(budget.deletedAt, isNotNull);
    expect(budget.updatedBy, olga.id);
    for (final id in expenses) {
      expect(await storedRow(api, 'expenses', id), isNull);
    }
    expect(await storedRow(api, 'recurring_rules', rule), isNull);
    expect(
      await api.count(
        r'SELECT count(*)::int FROM categories WHERE budget_id = $1::uuid',
        [family.id],
      ),
      0,
    );
    expect((await memberRow(api, family.id, olga.id))!.leftAt, isNotNull);

    final pulled = await pullUntilDone(api, olga, cursor: olgaCursor);
    expect(pulled.all((p) => p.removedBudgetIds), [family.id]);
    expect(pulled.all((p) => p.categories), isEmpty);
    expect(pulled.all((p) => p.expenses), isEmpty);

    expect((await joinRaw(api, boris, code)).status, 404);
    expect(
      logs.text,
      matches(
        RegExp(
          'INFO  \\[budgets\\] budget leave ok result=deleted '
          'budgetId=${family.id} userId=${olga.id} no members left, budget '
          'deleted erased=categories:11,expenses:2,recurring:1 '
          'invitesRevoked=1 in \\d+ms rid=',
        ),
      ),
    );
  });

  test('из личного бюджета выйти нельзя → 403; не участник и повторный '
      'выход → 404', () async {
    await join(boris);
    final personalId = await fixture.personalBudgetOf(olga.id);
    logs.clear();

    final personal = await leaveRaw(api, olga, personalId);
    expect(personal.status, 403, reason: personal.text);
    expect(personal.errorCode, ApiErrorCode.forbidden.code);
    expect((await memberRow(api, personalId, olga.id))!.leftAt, isNull);

    final stranger = await leaveRaw(api, vera, family.id);
    expect(stranger.status, 404);
    expect(stranger.errorCode, ApiErrorCode.notFound.code);

    expect((await leaveRaw(api, boris, family.id)).status, 204);
    final twice = await leaveRaw(api, boris, family.id);
    expect(twice.status, 404);
    expect(twice.errorCode, ApiErrorCode.notFound.code);
    expect(
      logs.text,
      contains(
        'WARN  [budgets] budget leave rejected by rights reason=forbidden '
        'budgetId=$personalId userId=${olga.id} '
        'problem="personal budget is not shared"',
      ),
    );
  });
}
