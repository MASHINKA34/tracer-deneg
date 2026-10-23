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

  setUp(() async {
    logs = LogCapture();
    api = await AuthHarness.start();
    fixture = SharedBudgetFixture(api);
    olga = await registerTestUser(api, 'olga', displayName: 'Ольга');
    boris = await registerTestUser(api, 'boris', displayName: 'Борис');
    vera = await registerTestUser(api, 'vera', displayName: 'Вера');
    family = await createSharedBudget(api, olga);
    final code = await inviteCodeFor(api, olga, family.id);
    await joinBudget(api, boris, code);
    await joinBudget(api, vera, code);
    logs.clear();
  });

  test(
    'создатель исключает участника → 204: у исключённого '
    'removedBudgetIds, у остальных его leftAt, строка и траты остаются',
    () async {
      final food = await firstCategoryOf(api, family.id);
      final borisExpense = await fixture.expense(family.id, food, boris.id);
      final borisCursor = (await pullUntilDone(api, boris)).cursor;
      final veraCursor = (await pullUntilDone(api, vera)).cursor;
      logs.clear();

      final response = await removeMemberRaw(api, olga, family.id, boris.id);
      expect(response.status, 204, reason: response.text);
      final rid = response.headers['x-request-id']!;

      final row = (await memberRow(api, family.id, boris.id))!;
      expect(row.leftAt, isNotNull);
      expect(
        (await storedRow(api, 'expenses', borisExpense))!.deletedAt,
        isNull,
      );

      final borisPull = await pullUntilDone(api, boris, cursor: borisCursor);
      expect(borisPull.all((p) => p.removedBudgetIds), [family.id]);
      expect(borisPull.all((p) => p.budgets), isEmpty);
      expect(borisPull.all((p) => p.expenses), isEmpty);

      final veraPull = await pullUntilDone(api, vera, cursor: veraCursor);
      expect(veraPull.all((p) => p.removedBudgetIds), isEmpty);
      expect(
        veraPull
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
      expect((await createInviteRaw(api, boris, family.id)).status, 404);
      expect(
        logs.text,
        matches(
          RegExp(
            'INFO  \\[budgets\\] budget remove member ok budgetId=${family.id} '
            'userId=${olga.id} memberId=${boris.id} seq=\\d+ in \\d+ms '
            'rid=$rid',
          ),
        ),
      );
    },
  );

  test('исключать может только создатель: участник → 403, чужой → 404, '
      'ничего не изменилось', () async {
    final outsider = await registerTestUser(api, 'dima', displayName: 'Дима');
    final before = (await memberRow(api, family.id, vera.id))!.seq;

    final member = await removeMemberRaw(api, boris, family.id, vera.id);
    expect(member.status, 403, reason: member.text);
    expect(member.errorCode, ApiErrorCode.forbidden.code);
    final stranger = await removeMemberRaw(api, outsider, family.id, vera.id);
    expect(stranger.status, 404, reason: stranger.text);
    expect(stranger.errorCode, ApiErrorCode.notFound.code);

    final row = (await memberRow(api, family.id, vera.id))!;
    expect(row.leftAt, isNull);
    expect(row.seq, before);
    expect(
      logs.text,
      contains(
        'WARN  [budgets] budget remove member rejected by rights '
        'reason=forbidden budgetId=${family.id} userId=${boris.id} '
        'memberId=${vera.id} problem="only the owner can do this, role=member"',
      ),
    );
  });

  test('себя исключить нельзя → 400; не участник, уже исключённый и '
      'неверный id → 404 not_found', () async {
    final outsider = await registerTestUser(api, 'dima', displayName: 'Дима');

    final self = await removeMemberRaw(api, olga, family.id, olga.id);
    expect(self.status, 400, reason: self.text);
    expect(self.errorCode, ApiErrorCode.badRequest.code);
    expect((await memberRow(api, family.id, olga.id))!.leftAt, isNull);

    expect((await removeMemberRaw(api, olga, family.id, boris.id)).status, 204);
    for (final target in [outsider.id, boris.id, newId(), 'not-a-uuid']) {
      final response = await removeMemberRaw(api, olga, family.id, target);
      expect(response.status, 404, reason: '$target → ${response.text}');
      expect(response.errorCode, ApiErrorCode.notFound.code);
      expect(
        (response.json['error']! as Map<String, Object?>)['message'],
        'Участник не найден',
      );
    }
    expect(
      logs.text,
      contains(
        'WARN  [budgets] budget remove member rejected reason=bad_request '
        'budgetId=${family.id} userId=${olga.id} memberId=${olga.id}',
      ),
    );
    expect(
      logs.text,
      contains(
        'WARN  [budgets] budget remove member rejected reason=not_found '
        'budgetId=${family.id} userId=${olga.id} memberId=${boris.id} '
        'problem="not an active member of this budget"',
      ),
    );
  });
}
