import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/auth_support.dart';
import 'support/budget_support.dart';
import 'support/shared_budget_support.dart';
import 'support/sync_support.dart';
import 'support/test_support.dart';

void main() {
  late LogCapture logs;
  late AuthHarness api;
  late TestUser olga;
  late TestUser boris;

  setUp(() async {
    logs = LogCapture();
    api = await AuthHarness.start();
    olga = await registerTestUser(api, 'olga', displayName: 'Ольга');
    boris = await registerTestUser(api, 'boris', displayName: 'Борис');
    logs.clear();
  });

  Future<int> maxSeq() => api.count(
    'SELECT greatest((SELECT max(seq) FROM budgets), '
    '(SELECT max(seq) FROM budget_members), '
    '(SELECT max(seq) FROM categories))::int',
  );

  Future<int> budgetsCount() =>
      api.count("SELECT count(*)::int FROM budgets WHERE kind = 'shared'");

  test('POST /budgets → 201: общий бюджет, создатель-владелец с первым цветом, '
      'копия 11 готовых категорий в порядке 00-spec §7.4', () async {
    final id = newId();
    final before = DateTime.now().toUtc().subtract(const Duration(seconds: 1));
    final response = await createBudgetRaw(api, olga, {
      'id': id,
      'name': '  Семья  ',
      'emoji': ' 🏠 ',
    });

    expect(response.status, 201, reason: response.text);
    expect(response.headers['cache-control'], 'no-store');
    final budget = Budget.fromJson(response.json['budget']);
    expect(budget.id, id);
    expect(budget.kind, BudgetKind.shared);
    expect(budget.name, 'Семья');
    expect(budget.emoji, '🏠');
    expect(budget.ownerId, olga.id);
    expect(budget.updatedBy, olga.id);
    expect(budget.deletedAt, isNull);
    expect(budget.seq, isPositive);
    expect(budget.createdAt.isAfter(before), isTrue);
    expect(budget.updatedAt, budget.createdAt);

    final owner = (await memberRow(api, id, olga.id))!;
    expect(owner.role, MemberRole.owner);
    expect(owner.color, CategoryColor.green);
    expect(owner.leftAt, isNull);
    expect(
      await api.count(
        r'SELECT count(*)::int FROM budget_members WHERE budget_id = $1::uuid',
        [id],
      ),
      1,
    );

    final rows = await api.db.execute(
      r'SELECT name, emoji, color, sort_order, is_system, updated_by, '
      r'deleted_at FROM categories WHERE budget_id = $1::uuid '
      'ORDER BY sort_order',
      parameters: [id],
    );
    expect(rows, hasLength(presetCategories.length));
    expect(rows, hasLength(11));
    for (var i = 0; i < presetCategories.length; i++) {
      final preset = presetCategories[i];
      expect(rows[i].toList(), [
        preset.name,
        preset.emoji,
        preset.color?.name,
        preset.sortOrder,
        preset.isSystem,
        olga.id,
        null,
      ], reason: preset.toString());
    }
    final personalId = await SharedBudgetFixture(api).personalBudgetOf(olga.id);
    final shared = await api.db.execute(
      r'SELECT id FROM categories WHERE budget_id = $1::uuid',
      parameters: [id],
    );
    final personal = await api.db.execute(
      r'SELECT id FROM categories WHERE budget_id = $1::uuid',
      parameters: [personalId],
    );
    expect(
      {for (final r in shared) r[0]}
          .intersection({for (final r in personal) r[0]}),
      isEmpty,
    );
  });

  test('pull создателя отдаёт новый бюджет, его участника и 11 категорий; '
      'чужой пользователь бюджета не видит', () async {
    final cursor = (await pullUntilDone(api, olga)).cursor;
    final borisCursor = (await pullUntilDone(api, boris)).cursor;
    final budget = await createSharedBudget(api, olga);

    final pulled = await pullUntilDone(api, olga, cursor: cursor);
    expect(pulled.all((p) => p.budgets).map((b) => b.id), [budget.id]);
    expect(pulled.all((p) => p.members), [
      isA<BudgetMember>()
          .having((m) => m.budgetId, 'budgetId', budget.id)
          .having((m) => m.userId, 'userId', olga.id)
          .having((m) => m.role, 'role', MemberRole.owner)
          .having((m) => m.avatarColor, 'avatarColor', CategoryColor.green),
    ]);
    final categories = pulled.all((p) => p.categories);
    expect(categories, hasLength(11));
    expect(categories.map((c) => c.budgetId).toSet(), {budget.id});
    expect(categories.where((c) => c.isSystem).map((c) => c.name), ['Другое']);
    expect(pulled.cursor, greaterThan(cursor));

    final strangers = await pullUntilDone(api, boris, cursor: borisCursor);
    expect(strangers.all((p) => p.budgets), isEmpty);
    expect(strangers.all((p) => p.categories), isEmpty);
  });

  test('повтор с тем же id тем же создателем → 200, тот же бюджет, '
      'ничего не записано (ответ потерялся в сети)', () async {
    final id = newId();
    final first = await createBudgetRaw(api, olga, {
      'id': id,
      'name': 'Семья',
      'emoji': '🏠',
    });
    expect(first.status, 201);
    final seq = await maxSeq();
    logs.clear();

    final again = await createBudgetRaw(api, olga, {
      'id': id,
      'name': 'Дача',
      'emoji': '🌳',
    });
    expect(again.status, 200, reason: again.text);
    expect(again.json['budget'], first.json['budget']);
    expect(await maxSeq(), seq);
    expect(
      await api.count(
        r'SELECT count(*)::int FROM categories WHERE budget_id = $1::uuid',
        [id],
      ),
      11,
    );
    expect(
      logs.text,
      matches(
        RegExp(
          'INFO  \\[budgets\\] budget create replayed: already created by '
          'this user, nothing written budgetId=$id userId=${olga.id} '
          'seq=\\d+ in \\d+ms',
        ),
      ),
    );
  });

  test('id чужого общего или своего личного бюджета → 409 conflict, '
      'ничего не изменилось', () async {
    final borisBudget = await createSharedBudget(api, boris);
    final personalId = await SharedBudgetFixture(api).personalBudgetOf(olga.id);
    final seq = await maxSeq();
    logs.clear();

    for (final id in [borisBudget.id, personalId]) {
      final response = await createBudgetRaw(api, olga, {
        'id': id,
        'name': 'Семья',
        'emoji': '🏠',
      });
      expect(response.status, 409, reason: response.text);
      expect(response.errorCode, ApiErrorCode.conflict.code);
      expect(
        (response.json['error']! as Map<String, Object?>)['message'],
        'Бюджет с таким id уже есть',
      );
    }
    expect(await maxSeq(), seq);
    expect(await memberRow(api, borisBudget.id, olga.id), isNull);
    expect(
      logs.text,
      contains(
        'WARN  [budgets] budget create rejected reason=conflict '
        'budgetId=${borisBudget.id} userId=${olga.id} '
        'problem="id belongs to another budget kind=shared sameOwner=false '
        'deleted=false activeOwner=false"',
      ),
    );
    expect(
      logs.text,
      contains(
        'problem="id belongs to another budget kind=personal sameOwner=true '
        'deleted=false activeOwner=true"',
      ),
    );
  });

  test('проверка полей: id, название 1–30, один эмодзи, NUL, не JSON → 400 '
      'с кодом, ничего не создано', () async {
    final cases = <(Object?, int, String)>[
      (
        {'id': 'not-a-uuid', 'name': 'Семья', 'emoji': '🏠'},
        400,
        'bad_request',
      ),
      (
        {'id': newId().toUpperCase(), 'name': 'Семья', 'emoji': '🏠'},
        400,
        'bad_request',
      ),
      ({'name': 'Семья', 'emoji': '🏠'}, 400, 'bad_request'),
      ({'id': newId(), 'name': 5, 'emoji': '🏠'}, 400, 'bad_request'),
      ({'id': newId(), 'name': 'Семья'}, 400, 'bad_request'),
      ({'id': newId(), 'name': '   ', 'emoji': '🏠'}, 400, 'budget_name_empty'),
      (
        {'id': newId(), 'name': 'я' * 31, 'emoji': '🏠'},
        400,
        'budget_name_too_long',
      ),
      ({'id': newId(), 'name': 'Семья', 'emoji': ''}, 400, 'emoji_empty'),
      ({'id': newId(), 'name': 'Семья', 'emoji': 'ab'}, 400, 'emoji_invalid'),
      (
        {'id': newId(), 'name': 'Се\u0000мья', 'emoji': '🏠'},
        400,
        'validation_failed',
      ),
      (['id'], 400, 'bad_request'),
    ];
    for (final (body, status, code) in cases) {
      final response = await createBudgetRaw(api, olga, body);
      expect(response.status, status, reason: '$body → ${response.text}');
      expect(response.errorCode, code, reason: '$body');
    }
    final notJson = await api.send(
      'POST',
      '/budgets',
      rawBody: '{oops',
      bearer: olga.accessToken,
    );
    expect(notJson.status, 400);
    expect(notJson.errorCode, 'bad_request');

    final ok = await createBudgetRaw(api, olga, {
      'id': newId(),
      'name': 'я' * 30,
      'emoji': '👨‍👩‍👧',
    });
    expect(ok.status, 201, reason: ok.text);
    expect(await budgetsCount(), 1);
  });

  test('без токена → 401, бюджет не создан', () async {
    final response = await api.send(
      'POST',
      '/budgets',
      body: {'id': newId(), 'name': 'Семья', 'emoji': '🏠'},
    );
    expect(response.status, 401);
    expect(await budgetsCount(), 0);
  });

  test('лог создания: budgetId, действие, результат, мс, rid; '
      'название бюджета не пишется даже на debug', () async {
    final id = newId();
    final response = await createBudgetRaw(api, olga, {
      'id': id,
      'name': 'Дача Кукушкино',
      'emoji': '🌳',
    });
    expect(response.status, 201);
    final rid = response.headers['x-request-id']!;
    expect(
      logs.text,
      matches(
        RegExp(
          'INFO  \\[budgets\\] budget create ok budgetId=$id '
          'userId=${olga.id} kind=shared role=owner avatarColor=green '
          'categories=11 seq=\\d+ in \\d+ms rid=$rid',
        ),
      ),
    );
    expect(logs.text, isNot(contains('Кукушкино')));

    final invalid = await createBudgetRaw(api, olga, {
      'id': id,
      'name': 'Кукушкино ${'я' * 40}',
      'emoji': '🌳',
    });
    expect(invalid.status, 400);
    expect(
      logs.text,
      contains(
        'WARN  [budgets] budget create rejected '
        'reason=budget_name_too_long userId=${olga.id} budgetId=$id '
        'field=name',
      ),
    );
    expect(logs.text, isNot(contains('Кукушкино')));
  });
}
