import 'package:shared/shared.dart';

import 'auth_support.dart';

class TestUser {
  TestUser({
    required this.id,
    required this.login,
    required this.password,
    required this.accessToken,
    required this.refreshToken,
  });

  final String id;
  final String login;
  final String password;
  final String accessToken;
  final String refreshToken;
}

Future<TestUser> registerTestUser(
  AuthHarness api,
  String login, {
  String displayName = 'Участник',
  String password = 'secret-pass-1',
}) async {
  final response = await api.register(
    login: login,
    displayName: displayName,
    password: password,
  );
  if (response.status != 201) {
    throw StateError('register $login failed: $response');
  }
  final json = response.json;
  return TestUser(
    id: (json['user']! as Map<String, Object?>)['id']! as String,
    login: login,
    password: password,
    accessToken: json['accessToken']! as String,
    refreshToken: json['refreshToken']! as String,
  );
}

class SharedBudgetFixture {
  SharedBudgetFixture(this.api);

  final AuthHarness api;

  Future<String> budget({
    required String ownerId,
    String name = 'Семья',
  }) async {
    final id = newId();
    await api.db.execute(
      r'INSERT INTO budgets (id, kind, name, emoji, owner_id, created_at, '
      r"updated_at, updated_by) VALUES ($1::uuid, 'shared', $2, '🏠', "
      r"$3::uuid, now() - interval '10 days', now() - interval '10 days', "
      r'$3::uuid)',
      parameters: [id, name, ownerId],
    );
    return id;
  }

  Future<void> member(
    String budgetId,
    String userId, {
    required MemberRole role,
    required CategoryColor color,
    required int joinedDaysAgo,
  }) async {
    await api.db.execute(
      r'INSERT INTO budget_members (budget_id, user_id, role, avatar_color, '
      r'joined_at) VALUES ($1::uuid, $2::uuid, $3, $4, '
      r'now() - make_interval(days => $5::int))',
      parameters: [budgetId, userId, role.name, color.name, joinedDaysAgo],
    );
  }

  Future<String> category(String budgetId, String updatedBy) async {
    final id = newId();
    await api.db.execute(
      r'INSERT INTO categories (id, budget_id, name, emoji, color, '
      r"sort_order, updated_at, updated_by) VALUES ($1::uuid, $2::uuid, "
      r"'Еда', '🍔', 'green', 0, now(), $3::uuid)",
      parameters: [id, budgetId, updatedBy],
    );
    return id;
  }

  Future<String> expense(
    String budgetId,
    String categoryId,
    String authorId, {
    int kopecks = 64000,
  }) async {
    final id = newId();
    await api.db.execute(
      r'INSERT INTO expenses (id, budget_id, category_id, amount_kopecks, '
      r'spent_on, author_id, created_at, updated_at, updated_by) VALUES '
      r"($1::uuid, $2::uuid, $3::uuid, $4, '2026-10-20', $5::uuid, now(), "
      r'now(), $5::uuid)',
      parameters: [id, budgetId, categoryId, kopecks, authorId],
    );
    return id;
  }

  Future<String> recurring(
    String budgetId,
    String categoryId,
    String updatedBy,
  ) async {
    final id = newId();
    await api.db.execute(
      r'INSERT INTO recurring_rules (id, budget_id, category_id, title, '
      r'amount_kopecks, day_of_month, start_month, created_at, updated_at, '
      r"updated_by) VALUES ($1::uuid, $2::uuid, $3::uuid, 'Аренда', 100000, "
      r"5, '2026-10', now(), now(), $4::uuid)",
      parameters: [id, budgetId, categoryId, updatedBy],
    );
    return id;
  }

  Future<void> invite(String budgetId, String createdBy) async {
    await api.db.execute(
      r'INSERT INTO invites (code_hash, budget_id, created_by, expires_at) '
      r"VALUES ($1, $2::uuid, $3::uuid, now() + interval '1 day')",
      parameters: ['invite-hash-${newId()}', budgetId, createdBy],
    );
  }

  Future<String> personalBudgetOf(String userId) async {
    final rows = await api.db.execute(
      r"SELECT id FROM budgets WHERE owner_id = $1::uuid AND kind = 'personal'",
      parameters: [userId],
    );
    return rows.single.first! as String;
  }
}
