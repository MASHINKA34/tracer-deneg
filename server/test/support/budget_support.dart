import 'package:shared/shared.dart';

import 'auth_support.dart';
import 'shared_budget_support.dart';

class ShiftedClock {
  Duration offset = Duration.zero;

  DateTime now() => DateTime.now().toUtc().add(offset);
}

Future<ApiResponse> createBudgetRaw(
  AuthHarness api,
  TestUser user,
  Object? body,
) => api.send('POST', '/budgets', body: body, bearer: user.accessToken);

Future<Budget> createSharedBudget(
  AuthHarness api,
  TestUser owner, {
  String? id,
  String name = 'Семья',
  String emoji = '🏠',
}) async {
  final response = await createBudgetRaw(api, owner, {
    'id': id ?? newId(),
    'name': name,
    'emoji': emoji,
  });
  if (response.status != 201) {
    throw StateError('create budget for ${owner.login} failed: $response');
  }
  return Budget.fromJson(response.json['budget']);
}

Future<ApiResponse> createInviteRaw(
  AuthHarness api,
  TestUser user,
  String budgetId,
) => api.send('POST', '/budgets/$budgetId/invites', bearer: user.accessToken);

Future<String> inviteCodeFor(
  AuthHarness api,
  TestUser owner,
  String budgetId,
) async {
  final response = await createInviteRaw(api, owner, budgetId);
  if (response.status != 201) {
    throw StateError('invite to $budgetId by ${owner.login} failed: $response');
  }
  return response.json['code']! as String;
}

Future<ApiResponse> joinRaw(AuthHarness api, TestUser user, Object? code) =>
    api.send(
      'POST',
      '/invites/join',
      body: {'code': code},
      bearer: user.accessToken,
    );

Future<Budget> joinBudget(AuthHarness api, TestUser user, String code) async {
  final response = await joinRaw(api, user, code);
  if (response.status != 200) {
    throw StateError('join by ${user.login} failed: $response');
  }
  return Budget.fromJson(response.json['budget']);
}

Future<ApiResponse> leaveRaw(AuthHarness api, TestUser user, String budgetId) =>
    api.send('POST', '/budgets/$budgetId/leave', bearer: user.accessToken);

Future<ApiResponse> removeMemberRaw(
  AuthHarness api,
  TestUser user,
  String budgetId,
  String memberId,
) => api.send(
  'DELETE',
  '/budgets/$budgetId/members/$memberId',
  bearer: user.accessToken,
);

Future<ApiResponse> deleteBudgetRaw(
  AuthHarness api,
  TestUser user,
  String budgetId,
) => api.send('DELETE', '/budgets/$budgetId', bearer: user.accessToken);

class MemberRow {
  MemberRow(this.values);

  final Map<String, Object?> values;

  MemberRole get role => MemberRole.values.byName(values['role']! as String);
  CategoryColor get color =>
      CategoryColor.values.byName(values['avatar_color']! as String);
  DateTime? get leftAt => values['left_at'] as DateTime?;
  int get seq => values['seq']! as int;
}

Future<MemberRow?> memberRow(
  AuthHarness api,
  String budgetId,
  String userId,
) async {
  final rows = await api.db.execute(
    r'SELECT * FROM budget_members WHERE budget_id = $1::uuid '
    r'AND user_id = $2::uuid',
    parameters: [budgetId, userId],
  );
  return rows.isEmpty ? null : MemberRow(rows.single.toColumnMap());
}
