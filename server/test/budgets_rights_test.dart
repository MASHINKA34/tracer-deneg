import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/auth_support.dart';
import 'support/budget_support.dart';
import 'support/shared_budget_support.dart';
import 'support/test_support.dart';

typedef _Call = Future<ApiResponse> Function(
  TestUser user,
  String budgetId,
  String other,
);

void main() {
  late LogCapture logs;
  late AuthHarness api;
  late TestUser olga;
  late TestUser boris;
  late TestUser vera;
  late String familyId;
  late String veraBudgetId;

  setUp(() async {
    logs = LogCapture();
    api = await AuthHarness.start();
    olga = await registerTestUser(api, 'olga', displayName: 'Ольга');
    boris = await registerTestUser(api, 'boris', displayName: 'Борис');
    vera = await registerTestUser(api, 'vera', displayName: 'Вера');
    familyId = (await createSharedBudget(api, olga)).id;
    await joinBudget(api, boris, await inviteCodeFor(api, olga, familyId));
    veraBudgetId = (await createSharedBudget(api, vera, name: 'Вера')).id;
    logs.clear();
  });

  Map<String, _Call> calls() => {
    'invite': (user, id, _) => createInviteRaw(api, user, id),
    'leave': (user, id, _) => leaveRaw(api, user, id),
    'remove member': (user, id, other) => removeMemberRaw(api, user, id, other),
    'delete': (user, id, _) => deleteBudgetRaw(api, user, id),
  };

  Future<int> changes() => api.count(
    'SELECT (SELECT count(*)::int FROM invites) + '
    '(SELECT count(*)::int FROM budget_members WHERE left_at IS NOT NULL) + '
    '(SELECT count(*)::int FROM budgets WHERE deleted_at IS NOT NULL)',
  );

  test('не участник: чужой, несуществующий, удалённый бюджет и неверный id '
      '→ 404 not_found на каждой операции, ничего не записано', () async {
    final deletedId = (await createSharedBudget(api, vera, name: 'Старый')).id;
    expect((await deleteBudgetRaw(api, vera, deletedId)).status, 204);
    final before = await changes();
    logs.clear();

    final targets = {
      'foreign': (veraBudgetId, 'not an active member'),
      'missing': (newId(), 'no such budget'),
      'deleted': (deletedId, 'budget is deleted'),
      'not uuid': ('family', 'budget id is not a uuid'),
    };
    for (final MapEntry(key: action, value: call) in calls().entries) {
      for (final MapEntry(key: kind, value: (id, problem)) in targets.entries) {
        final userId = kind == 'deleted' ? vera.id : olga.id;
        final user = kind == 'deleted' ? vera : olga;
        final response = await call(user, id, vera.id);
        final reason = '$action $kind → ${response.text}';
        expect(response.status, 404, reason: reason);
        expect(response.errorCode, ApiErrorCode.notFound.code, reason: reason);
        expect(
          (response.json['error']! as Map<String, Object?>)['message'],
          'Бюджет не найден',
          reason: reason,
        );
        expect(
          logs.text,
          contains(
            'WARN  [budgets] budget $action rejected by rights '
            'reason=not_found budgetId=$id userId=$userId',
          ),
          reason: reason,
        );
        expect(logs.text, contains('problem="$problem"'), reason: reason);
      }
    }
    expect(await changes(), before);
  });

  test('не создатель: приглашение, исключение и удаление → 403 forbidden '
      '(warn), выйти может', () async {
    final before = await changes();
    for (final action in ['invite', 'remove member', 'delete']) {
      logs.clear();
      final response = await calls()[action]!(boris, familyId, olga.id);
      expect(response.status, 403, reason: '$action → ${response.text}');
      expect(response.errorCode, ApiErrorCode.forbidden.code);
      expect(
        logs.text,
        contains(
          'WARN  [budgets] budget $action rejected by rights reason=forbidden '
          'budgetId=$familyId userId=${boris.id}',
        ),
      );
    }
    expect(await changes(), before);
    expect((await leaveRaw(api, boris, familyId)).status, 204);
  });

  test('без токена или с чужим access → 401 до проверки бюджета', () async {
    for (final (method, path) in [
      ('POST', '/budgets/$familyId/invites'),
      ('POST', '/budgets/$familyId/leave'),
      ('DELETE', '/budgets/$familyId/members/${boris.id}'),
      ('DELETE', '/budgets/$familyId'),
      ('POST', '/invites/join'),
    ]) {
      final none = await api.send(method, path, body: {'code': 'MLN-1234'});
      expect(none.status, 401, reason: '$method $path');
      final forged = await api.send(
        method,
        path,
        body: {'code': 'MLN-1234'},
        bearer: 'not-a-jwt',
      );
      expect(forged.status, 401, reason: '$method $path');
    }
    expect((await memberRow(api, familyId, boris.id))!.leftAt, isNull);
  });
}
