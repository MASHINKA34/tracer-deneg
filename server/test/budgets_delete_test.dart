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
    await joinBudget(api, boris, await inviteCodeFor(api, olga, family.id));
    logs.clear();
  });

  Future<Map<String, int>> counts() async {
    final rows = await api.db.execute(
      'SELECT '
      r'(SELECT count(*)::int FROM categories WHERE budget_id = $1::uuid), '
      r'(SELECT count(*)::int FROM categories WHERE budget_id = $1::uuid '
      'AND deleted_at IS NULL), '
      r'(SELECT count(*)::int FROM expenses WHERE budget_id = $1::uuid), '
      r'(SELECT count(*)::int FROM expenses WHERE budget_id = $1::uuid '
      'AND deleted_at IS NULL), '
      r'(SELECT count(*)::int FROM recurring_rules WHERE budget_id = $1::uuid), '
      r'(SELECT count(*)::int FROM recurring_rules WHERE budget_id = $1::uuid '
      'AND deleted_at IS NULL), '
      r'(SELECT count(*)::int FROM budget_members WHERE budget_id = $1::uuid), '
      r'(SELECT count(*)::int FROM invites WHERE budget_id = $1::uuid '
      'AND revoked_at IS NULL)',
      parameters: [family.id],
    );
    final row = rows.single;
    return {
      'categories': row[0]! as int,
      'liveCategories': row[1]! as int,
      'expenses': row[2]! as int,
      'liveExpenses': row[3]! as int,
      'recurring': row[4]! as int,
      'liveRecurring': row[5]! as int,
      'members': row[6]! as int,
      'activeInvites': row[7]! as int,
    };
  }

  test('создатель удаляет бюджет → 204: бюджет помечен удалённым, траты, '
      'регулярные и категории стёрты (и ранее удалённые тоже), участники '
      'остаются, коды отменены, у всех участников removedBudgetIds', () async {
    final expenses = [
      await fixture.expense(family.id, food, olga.id),
      await fixture.expense(family.id, food, boris.id),
    ];
    final old = await fixture.expense(family.id, food, boris.id);
    await api.db.execute(
      r"UPDATE expenses SET deleted_at = now() - interval '1 day' "
      r'WHERE id = $1::uuid',
      parameters: [old],
    );
    final oldDeletedAt = (await storedRow(api, 'expenses', old))!.deletedAt;
    await fixture.recurring(family.id, food, boris.id);
    final code = await inviteCodeFor(api, olga, family.id);
    final olgaCursor = (await pullUntilDone(api, olga)).cursor;
    final borisCursor = (await pullUntilDone(api, boris)).cursor;
    logs.clear();

    final response = await deleteBudgetRaw(api, olga, family.id);
    expect(response.status, 204, reason: response.text);
    final rid = response.headers['x-request-id']!;

    final budget = (await storedRow(api, 'budgets', family.id))!;
    expect(budget.deletedAt, isNotNull);
    expect(budget.updatedBy, olga.id);
    expect(await counts(), {
      'categories': 0,
      'liveCategories': 0,
      'expenses': 0,
      'liveExpenses': 0,
      'recurring': 0,
      'liveRecurring': 0,
      'members': 2,
      'activeInvites': 0,
    });
    for (final id in [...expenses, old]) {
      expect(await storedRow(api, 'expenses', id), isNull);
    }
    expect(oldDeletedAt, isNotNull);

    for (final (user, cursor) in [(olga, olgaCursor), (boris, borisCursor)]) {
      final pulled = await pullUntilDone(api, user, cursor: cursor);
      expect(pulled.all((p) => p.removedBudgetIds), [family.id]);
      expect(pulled.all((p) => p.budgets), isEmpty);
      expect(pulled.all((p) => p.expenses), isEmpty);
      expect(pulled.all((p) => p.categories), isEmpty);
    }

    expect((await joinRaw(api, vera, code)).status, 404);
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
          'INFO  \\[budgets\\] budget delete ok budgetId=${family.id} '
          'userId=${olga.id} members=2 erased=categories:11,expenses:3,'
          'recurring:1 invitesRevoked=1 in \\d+ms rid=$rid',
        ),
      ),
    );
  });

  test('удалять может только создатель: участник → 403, чужой → 404, '
      'личный → 403, удалённый → 404; ничего не изменилось', () async {
    await fixture.expense(family.id, food, boris.id);
    final personalId = await fixture.personalBudgetOf(olga.id);
    final before = await counts();
    logs.clear();

    final member = await deleteBudgetRaw(api, boris, family.id);
    expect(member.status, 403, reason: member.text);
    expect(member.errorCode, ApiErrorCode.forbidden.code);
    expect(
      (member.json['error']! as Map<String, Object?>)['message'],
      'Это может сделать только создатель бюджета',
    );

    final stranger = await deleteBudgetRaw(api, vera, family.id);
    expect(stranger.status, 404, reason: stranger.text);
    expect(stranger.errorCode, ApiErrorCode.notFound.code);

    final personal = await deleteBudgetRaw(api, olga, personalId);
    expect(personal.status, 403, reason: personal.text);
    expect(personal.errorCode, ApiErrorCode.forbidden.code);
    expect((await storedRow(api, 'budgets', personalId))!.deletedAt, isNull);

    expect(await counts(), before);
    expect((await storedRow(api, 'budgets', family.id))!.deletedAt, isNull);

    expect((await deleteBudgetRaw(api, olga, family.id)).status, 204);
    final again = await deleteBudgetRaw(api, olga, family.id);
    expect(again.status, 404);
    expect(again.errorCode, ApiErrorCode.notFound.code);
    expect(
      logs.text,
      contains(
        'WARN  [budgets] budget delete rejected by rights reason=not_found '
        'budgetId=${family.id} userId=${olga.id} problem="budget is deleted"',
      ),
    );
  });
}
