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
    logs.clear();
  });

  Future<int> maxSeq() => api.count(
    'SELECT greatest((SELECT max(seq) FROM budgets), '
    '(SELECT max(seq) FROM budget_members), '
    '(SELECT max(seq) FROM categories), (SELECT max(seq) FROM expenses), '
    '(SELECT max(seq) FROM recurring_rules))::int',
  );

  test('вход по коду → 200 {budget}: участник с ролью member и следующим '
      'по порядку цветом, код работает для любого числа людей', () async {
    final code = await inviteCodeFor(api, olga, family.id);

    final response = await joinRaw(api, boris, code);
    expect(response.status, 200, reason: response.text);
    expect(response.headers['cache-control'], 'no-store');
    expect(response.json.keys, ['budget']);
    final budget = Budget.fromJson(response.json['budget']);
    expect(budget.id, family.id);
    expect(budget.kind, BudgetKind.shared);
    expect(budget.ownerId, olga.id);
    expect(budget.name, family.name);
    expect(budget.seq, greaterThan(family.seq!));

    final borisRow = (await memberRow(api, family.id, boris.id))!;
    expect(borisRow.role, MemberRole.member);
    expect(borisRow.color, CategoryColor.orange);
    expect(borisRow.leftAt, isNull);

    await joinBudget(api, vera, code.toLowerCase().replaceAll('-', ''));
    expect(
      (await memberRow(api, family.id, vera.id))!.color,
      CategoryColor.yellow,
    );
    expect((await memberRow(api, family.id, olga.id))!.role, MemberRole.owner);
  });

  test('после входа pull вступившего с его прежним курсором отдаёт всё '
      'содержимое бюджета: бюджет, участников, профили, категории, траты, '
      'регулярные', () async {
    final food = await firstCategoryOf(api, family.id);
    final kept = [
      await fixture.expense(family.id, food, olga.id, kopecks: 64000),
      await fixture.expense(family.id, food, olga.id, kopecks: 25050),
    ];
    final gone = await fixture.expense(family.id, food, olga.id);
    await api.db.execute(
      r'UPDATE expenses SET deleted_at = now() WHERE id = $1::uuid',
      parameters: [gone],
    );
    final rule = await fixture.recurring(family.id, food, olga.id);
    final custom = await fixture.category(family.id, olga.id);
    await api.db.execute(
      r'UPDATE categories SET deleted_at = now() WHERE id = $1::uuid',
      parameters: [custom],
    );
    final borisPersonal = await fixture.personalBudgetOf(boris.id);
    await pushAs(api, boris, [
      SyncChange.upsert(
        expenseRecord(
          budgetId: borisPersonal,
          categoryId: await firstCategoryOf(api, borisPersonal),
          authorId: boris.id,
        ),
      ),
    ]);
    final borisCursor = (await pullUntilDone(api, boris)).cursor;
    expect(borisCursor, greaterThanOrEqualTo(await maxSeq()));

    await joinBudget(api, boris, await inviteCodeFor(api, olga, family.id));

    for (final limit in [pullPageSize, 3]) {
      final pulled = await pullUntilDone(
        api,
        boris,
        cursor: borisCursor,
        limit: limit,
      );
      final reason = 'limit=$limit';
      expect(pulled.all((p) => p.budgets).map((b) => b.id), [
        family.id,
      ], reason: reason);
      expect(
        {
          for (final m in pulled.all((p) => p.members))
            if (m.budgetId == family.id) m.userId: m.role,
        },
        {olga.id: MemberRole.owner, boris.id: MemberRole.member},
        reason: reason,
      );
      expect(pulled.all((p) => p.profiles).map((p) => p.userId), [
        olga.id,
      ], reason: reason);
      final categories = pulled.all((p) => p.categories);
      expect(categories, hasLength(12), reason: reason);
      expect(categories.map((c) => c.budgetId).toSet(), {family.id});
      expect(
        categories.singleWhere((c) => c.id == custom).isDeleted,
        isTrue,
        reason: reason,
      );
      expect(
        pulled.all((p) => p.expenses).map((e) => e.id).toSet(),
        kept.toSet(),
        reason: reason,
      );
      expect(pulled.all((p) => p.recurring).map((r) => r.id), [
        rule,
      ], reason: reason);
      expect(pulled.all((p) => p.removedBudgetIds), isEmpty, reason: reason);
    }
  });

  test('после входа старый участник по своему курсору получает нового '
      'участника и его профиль; трата нового видна в pull создателя', () async {
    final olgaCursor = (await pullUntilDone(api, olga)).cursor;
    await joinBudget(api, boris, await inviteCodeFor(api, olga, family.id));

    final pulled = await pullUntilDone(api, olga, cursor: olgaCursor);
    expect(
      pulled.all((p) => p.members).map((m) => (m.userId, m.avatarColor)),
      containsAll([(boris.id, CategoryColor.orange)]),
    );
    expect(pulled.all((p) => p.profiles), [
      isA<MemberProfile>()
          .having((p) => p.userId, 'userId', boris.id)
          .having((p) => p.displayName, 'displayName', 'Борис')
          .having((p) => p.avatarColor, 'avatarColor', CategoryColor.orange),
    ]);

    final expense = expenseRecord(
      budgetId: family.id,
      categoryId: await firstCategoryOf(api, family.id),
      authorId: boris.id,
      kopecks: 31500,
    );
    final push = await pushAs(api, boris, [SyncChange.upsert(expense)]);
    expect(push.applied, [expense.id]);
    final after = await pullUntilDone(api, olga, cursor: pulled.cursor);
    expect(after.all((p) => p.expenses).map((e) => (e.id, e.authorId)), [
      (expense.id, boris.id),
    ]);
  });

  test(
    'повторный вход действующего участника → 200, ничего не записано',
    () async {
      final code = await inviteCodeFor(api, olga, family.id);
      await joinBudget(api, boris, code);
      final seq = await maxSeq();
      logs.clear();

      final again = await joinRaw(api, boris, code);
      expect(again.status, 200, reason: again.text);
      expect(Budget.fromJson(again.json['budget']).id, family.id);
      final owner = await joinRaw(api, olga, code);
      expect(owner.status, 200, reason: owner.text);
      expect(await maxSeq(), seq);
      expect(
        (await memberRow(api, family.id, olga.id))!.role,
        MemberRole.owner,
      );
      expect(
        logs.text,
        contains(
          'INFO  [budgets] budget join ok result=already_member, nothing '
          'written budgetId=${family.id} userId=${boris.id} code=MLN-****',
        ),
      );
    },
  );

  test('вышедший участник возвращается по новому коду: left_at снят, '
      'цвет свободный, pull снова отдаёт бюджет', () async {
    await joinBudget(api, boris, await inviteCodeFor(api, olga, family.id));
    await joinBudget(api, vera, await inviteCodeFor(api, olga, family.id));
    await api.db.execute(
      r'UPDATE budget_members SET left_at = now() '
      r'WHERE budget_id = $1::uuid AND user_id = $2::uuid',
      parameters: [family.id, boris.id],
    );
    final borisCursor = (await pullUntilDone(api, boris)).cursor;
    logs.clear();

    final back = await joinRaw(
      api,
      boris,
      await inviteCodeFor(api, olga, family.id),
    );
    expect(back.status, 200, reason: back.text);
    final row = (await memberRow(api, family.id, boris.id))!;
    expect(row.leftAt, isNull);
    expect(row.role, MemberRole.member);
    expect(row.color, CategoryColor.orange);
    expect(
      await api.count(
        r'SELECT count(*)::int FROM budget_members WHERE budget_id = $1::uuid',
        [family.id],
      ),
      3,
    );

    final pulled = await pullUntilDone(api, boris, cursor: borisCursor);
    expect(pulled.all((p) => p.budgets).map((b) => b.id), [family.id]);
    expect(pulled.all((p) => p.categories), hasLength(11));
    expect(pulled.all((p) => p.removedBudgetIds), isEmpty);
    expect(logs.text, contains('budget join ok result=rejoined'));
  });

  test('двое входят одновременно — разные цвета по порядку', () async {
    final code = await inviteCodeFor(api, olga, family.id);
    final responses = await Future.wait([
      joinRaw(api, boris, code),
      joinRaw(api, vera, code),
    ]);
    expect(responses.map((r) => r.status), [200, 200]);
    final colors = {
      (await memberRow(api, family.id, boris.id))!.color,
      (await memberRow(api, family.id, vera.id))!.color,
    };
    expect(colors, {CategoryColor.orange, CategoryColor.yellow});
  });

  test('неизвестный, неверный по формату, отозванный код и код удалённого '
      'бюджета → 404 invite_not_found; не строка → 400', () async {
    final code = await inviteCodeFor(api, olga, family.id);
    final dacha = await createSharedBudget(api, olga, name: 'Дача');
    final dachaCode = await inviteCodeFor(api, olga, dacha.id);
    await api.db.execute(
      r'UPDATE budgets SET deleted_at = now() WHERE id = $1::uuid',
      parameters: [dacha.id],
    );
    final unknown = code.endsWith('0')
        ? '${code.substring(0, 7)}1'
        : '${code.substring(0, 7)}0';
    logs.clear();

    for (final input in [unknown, 'MLN-12', 'MLN-UUUU', '', dachaCode]) {
      final response = await joinRaw(api, boris, input);
      expect(response.status, 404, reason: '"$input" → ${response.text}');
      expect(response.errorCode, ApiErrorCode.inviteNotFound.code);
    }
    for (final body in [
      5,
      null,
      ['MLN-1234'],
    ]) {
      final response = await joinRaw(api, boris, body);
      expect(response.status, 400, reason: '$body → ${response.text}');
      expect(response.errorCode, ApiErrorCode.badRequest.code);
    }
    expect(await memberRow(api, family.id, boris.id), isNull);
    expect(await memberRow(api, dacha.id, boris.id), isNull);
    expect(
      logs.text,
      contains(
        'WARN  [budgets] budget join rejected reason=invite_not_found '
        'userId=${boris.id} code=MLN-**** problem="no invite with this code"',
      ),
    );
    expect(
      logs.text,
      contains('problem="code is not MLN-XXXX in Crockford base32 (length 6)"'),
    );
    expect(
      logs.text,
      contains(
        'code=MLN-**** budgetId=${dacha.id} '
        'problem="budget of invite is deleted"',
      ),
    );
    expect(
      logs.text,
      contains(
        'WARN  [budgets] budget join rejected reason=bad_request '
        'userId=${boris.id} fields=code',
      ),
    );
  });

  test(
    'лог входа: budgetId, результат, цвет, сколько seq перевыдано, мс, rid',
    () async {
      final food = await firstCategoryOf(api, family.id);
      await fixture.expense(family.id, food, olga.id);
      await fixture.recurring(family.id, food, olga.id);
      final code = await inviteCodeFor(api, olga, family.id);
      logs.clear();

      final response = await joinRaw(api, boris, code);
      final rid = response.headers['x-request-id']!;
      expect(
        logs.text,
        matches(
          RegExp(
            'INFO  \\[budgets\\] budget join ok result=joined '
            'budgetId=${family.id} userId=${boris.id} code=MLN-\\*\\*\\*\\* '
            'role=member avatarColor=orange seqReissued=budget:1,members:2,'
            'categories:11,recurring:1,expenses:1 seq=\\d+ in \\d+ms rid=$rid',
          ),
        ),
      );
    },
  );
}
