import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/auth_support.dart';
import 'support/budget_support.dart';
import 'support/shared_budget_support.dart';
import 'support/test_support.dart';

void main() {
  late LogCapture logs;
  late AuthHarness api;
  late TestUser olga;
  late TestUser boris;
  late TestUser vera;
  late Budget family;
  late String code;

  setUp(() async {
    logs = LogCapture();
    api = await AuthHarness.start();
    olga = await registerTestUser(api, 'olga', displayName: 'Ольга');
    boris = await registerTestUser(api, 'boris', displayName: 'Борис');
    vera = await registerTestUser(api, 'vera', displayName: 'Вера');
    family = await createSharedBudget(api, olga);
    code = await inviteCodeFor(api, olga, family.id);
    await joinBudget(api, boris, code);
    logs.clear();
  });

  Future<int> activeInvites(String budgetId) => api.count(
    r'SELECT count(*)::int FROM invites WHERE budget_id = $1::uuid '
    'AND revoked_at IS NULL',
    [budgetId],
  );

  test('исключение отзывает действующий код: исключённый с прежним кодом → '
      '404 invite_not_found, новый код работает', () async {
    final removed = await removeMemberRaw(api, olga, family.id, boris.id);
    expect(removed.status, 204, reason: removed.text);
    final rid = removed.headers['x-request-id']!;
    expect(await activeInvites(family.id), 0);
    expect(
      logs.text,
      contains(
        'INFO  [budgets] budget remove member revoked invite codes '
        'budgetId=${family.id} memberId=${boris.id} invitesRevoked=1 → old '
        'code no longer works, owner issues a new one rid=$rid',
      ),
    );

    final back = await joinRaw(api, boris, code);
    expect(back.status, 404, reason: back.text);
    expect(back.errorCode, ApiErrorCode.inviteNotFound.code);
    expect((await memberRow(api, family.id, boris.id))!.leftAt, isNotNull);
    final late = await joinRaw(api, vera, code);
    expect(late.status, 404, reason: late.text);
    expect(late.errorCode, ApiErrorCode.inviteNotFound.code);

    final fresh = await inviteCodeFor(api, olga, family.id);
    expect(fresh, isNot(code));
    final rejoined = await joinRaw(api, boris, fresh);
    expect(rejoined.status, 200, reason: rejoined.text);
    expect((await memberRow(api, family.id, boris.id))!.leftAt, isNull);
    expect((await joinRaw(api, vera, fresh)).status, 200);

    for (final value in [code, fresh]) {
      expect(logs.text, isNot(contains(value)));
    }
  });

  test('отзываются только коды этого бюджета', () async {
    final dacha = await createSharedBudget(api, olga, name: 'Дача');
    final dachaCode = await inviteCodeFor(api, olga, dacha.id);

    expect((await removeMemberRaw(api, olga, family.id, boris.id)).status, 204);
    expect(await activeInvites(family.id), 0);
    expect(await activeInvites(dacha.id), 1);
    expect((await joinRaw(api, vera, dachaCode)).status, 200);
  });

  test('исключение не прошло → код продолжает работать', () async {
    final outsider = await registerTestUser(api, 'dima', displayName: 'Дима');

    final stranger = await removeMemberRaw(api, olga, family.id, outsider.id);
    expect(stranger.status, 404, reason: stranger.text);
    final notOwner = await removeMemberRaw(api, boris, family.id, olga.id);
    expect(notOwner.status, 403, reason: notOwner.text);

    expect(await activeInvites(family.id), 1);
    expect(logs.text, isNot(contains('revoked invite codes')));
    expect((await joinRaw(api, vera, code)).status, 200);
  });

  test('кода нет → исключение проходит, отзывать нечего', () async {
    await api.db.execute(
      r'UPDATE invites SET revoked_at = now() WHERE budget_id = $1::uuid',
      parameters: [family.id],
    );

    final removed = await removeMemberRaw(api, olga, family.id, boris.id);
    expect(removed.status, 204, reason: removed.text);
    expect(logs.text, isNot(contains('revoked invite codes')));
    expect(
      logs.text,
      contains(
        'DEBUG [budgets] budget remove member: no active invite code to '
        'revoke budgetId=${family.id} memberId=${boris.id}',
      ),
    );
  });
}
