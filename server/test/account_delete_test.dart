import 'package:server/account/account_service.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/auth_support.dart';
import 'support/shared_budget_support.dart';
import 'support/test_support.dart';

void main() {
  late LogCapture logs;
  late AuthHarness api;
  late SharedBudgetFixture fixture;
  late TestUser olga;
  late TestUser boris;
  late TestUser vera;
  late String olgaSecondRefresh;
  late String personalId;
  late String familyId;
  late String soloId;
  late String friendsId;
  late List<String> olgaSharedExpenses;
  late String borisExpense;

  setUp(() async {
    logs = LogCapture();
    api = await AuthHarness.start();
    fixture = SharedBudgetFixture(api);
    olga = await registerTestUser(api, 'olga', displayName: 'Ольга');
    boris = await registerTestUser(api, 'boris', displayName: 'Борис');
    vera = await registerTestUser(api, 'vera', displayName: 'Вера');
    final secondLogin = await api.login(login: 'olga', deviceName: 'Tablet');
    olgaSecondRefresh = secondLogin.json['refreshToken']! as String;
    expect(
      (await api.send(
        'PATCH',
        '/me',
        body: {'birthdayMonth': 6, 'birthdayDay': 12},
        bearer: olga.accessToken,
      )).status,
      200,
    );

    personalId = await fixture.personalBudgetOf(olga.id);
    final personalCategory =
        (await api.db.execute(
              r'SELECT id FROM categories WHERE budget_id = $1::uuid LIMIT 1',
              parameters: [personalId],
            )).single.first!
            as String;
    await fixture.expense(personalId, personalCategory, olga.id);
    await fixture.recurring(personalId, personalCategory, olga.id);

    familyId = await fixture.budget(ownerId: olga.id, name: 'Семья');
    await fixture.member(
      familyId,
      olga.id,
      role: MemberRole.owner,
      color: CategoryColor.green,
      joinedDaysAgo: 5,
    );
    await fixture.member(
      familyId,
      vera.id,
      role: MemberRole.member,
      color: CategoryColor.yellow,
      joinedDaysAgo: 1,
    );
    await fixture.member(
      familyId,
      boris.id,
      role: MemberRole.member,
      color: CategoryColor.orange,
      joinedDaysAgo: 3,
    );
    final familyCategory = await fixture.category(familyId, olga.id);
    olgaSharedExpenses = [
      await fixture.expense(familyId, familyCategory, olga.id, kopecks: 64000),
      await fixture.expense(familyId, familyCategory, olga.id, kopecks: 25050),
    ];
    borisExpense = await fixture.expense(familyId, familyCategory, boris.id);
    await fixture.invite(familyId, olga.id);

    soloId = await fixture.budget(ownerId: olga.id, name: 'Отпуск');
    await fixture.member(
      soloId,
      olga.id,
      role: MemberRole.owner,
      color: CategoryColor.green,
      joinedDaysAgo: 4,
    );
    final soloCategory = await fixture.category(soloId, olga.id);
    await fixture.expense(soloId, soloCategory, olga.id);
    await fixture.recurring(soloId, soloCategory, olga.id);
    await fixture.invite(soloId, olga.id);

    friendsId = await fixture.budget(ownerId: vera.id, name: 'Друзья');
    await fixture.member(
      friendsId,
      vera.id,
      role: MemberRole.owner,
      color: CategoryColor.green,
      joinedDaysAgo: 6,
    );
    await fixture.member(
      friendsId,
      olga.id,
      role: MemberRole.member,
      color: CategoryColor.orange,
      joinedDaysAgo: 2,
    );
    final friendsCategory = await fixture.category(friendsId, vera.id);
    olgaSharedExpenses.add(
      await fixture.expense(friendsId, friendsCategory, olga.id),
    );
    logs.clear();
  });

  Future<ApiResponse> deleteAccount({String? password, String? bearer}) =>
      api.send(
        'DELETE',
        '/account',
        body: {'password': password ?? olga.password},
        bearer: bearer ?? olga.accessToken,
      );

  Future<Map<String, Object?>> snapshot() async {
    final rows = await api.db.execute(
      'SELECT '
      '(SELECT count(*)::int FROM budgets), '
      '(SELECT count(*)::int FROM budgets WHERE deleted_at IS NOT NULL), '
      '(SELECT count(*)::int FROM budget_members WHERE left_at IS NOT NULL), '
      "(SELECT count(*)::int FROM budget_members WHERE role = 'owner'), "
      '(SELECT count(*)::int FROM categories), '
      '(SELECT count(*)::int FROM expenses), '
      '(SELECT count(*)::int FROM expenses WHERE deleted_at IS NOT NULL), '
      '(SELECT count(*)::int FROM recurring_rules), '
      '(SELECT count(*)::int FROM invites WHERE revoked_at IS NOT NULL), '
      '(SELECT count(*)::int FROM sessions WHERE revoked_at IS NOT NULL), '
      '(SELECT count(*)::int FROM users WHERE deleted_at IS NOT NULL), '
      '(SELECT max(seq) FROM users)',
    );
    final row = rows.single;
    return {
      'budgets': row[0],
      'deletedBudgets': row[1],
      'leftMembers': row[2],
      'owners': row[3],
      'categories': row[4],
      'expenses': row[5],
      'deletedExpenses': row[6],
      'recurring': row[7],
      'revokedInvites': row[8],
      'revokedSessions': row[9],
      'deletedUsers': row[10],
      'usersSeq': row[11],
    };
  }

  Future<List<Object?>> member(String budgetId, String userId) async {
    final rows = await api.db.execute(
      r'SELECT role, left_at IS NOT NULL, seq FROM budget_members '
      r'WHERE budget_id = $1::uuid AND user_id = $2::uuid',
      parameters: [budgetId, userId],
    );
    return rows.single.toList();
  }

  Future<List<Object?>> budget(String id) async {
    final rows = await api.db.execute(
      r'SELECT owner_id, deleted_at IS NOT NULL, seq, updated_by '
      r'FROM budgets WHERE id = $1::uuid',
      parameters: [id],
    );
    return rows.single.toList();
  }

  test('неверный пароль → 401 bad_credentials, ничего не удалено', () async {
    final before = await snapshot();

    final response = await deleteAccount(password: 'wrong-pass-1');

    expect(response.status, 401);
    expect(response.json, {
      'error': {'code': 'bad_credentials', 'message': 'Неверный пароль'},
    });
    expect(await snapshot(), before);
    expect(
      (await api.send('GET', '/me', bearer: olga.accessToken)).status,
      200,
    );
    expect(
      logs.text,
      contains(
        RegExp(
          'WARN  \\[account\\] account deletion rejected '
          'reason=bad_credentials userId=${olga.id} sessionId=\\S+ '
          'cause=password_mismatch in \\d+ms',
        ),
      ),
    );
    expect(logs.text, isNot(contains('account deleted')));
  });

  test(
    'без пароля → 400 bad_request, без токена → 401, ничего не удалено',
    () async {
      final before = await snapshot();

      final noPassword = await api.send(
        'DELETE',
        '/account',
        body: <String, Object?>{},
        bearer: olga.accessToken,
      );
      final noToken = await api.send(
        'DELETE',
        '/account',
        body: {'password': olga.password},
      );

      expect(noPassword.status, 400);
      expect(noPassword.errorCode, 'bad_request');
      expect(noToken.status, 401);
      expect(noToken.errorCode, 'unauthorized');
      expect(await snapshot(), before);
      expect(
        logs.text,
        contains(
          'WARN  [account] account deletion rejected reason=bad_request '
          'userId=${olga.id} fields=password',
        ),
      );
    },
  );

  test(
    '204: личный бюджет удалён вместе с категориями, тратами и регулярными',
    () async {
      final response = await deleteAccount();

      expect(response.status, 204);
      expect(response.text, isEmpty);
      for (final table in ['budgets', 'budget_members']) {
        final column = table == 'budgets' ? 'id' : 'budget_id';
        expect(
          await api.count(
            'SELECT count(*)::int FROM $table WHERE $column = \$1::uuid',
            [personalId],
          ),
          0,
          reason: table,
        );
      }
      for (final table in ['categories', 'expenses', 'recurring_rules']) {
        expect(
          await api.count(
            'SELECT count(*)::int FROM $table WHERE budget_id = \$1::uuid',
            [personalId],
          ),
          0,
          reason: table,
        );
      }
      expect(
        await api.count(
          'SELECT count(*)::int FROM budgets WHERE kind = \'personal\'',
        ),
        2,
      );
    },
  );

  test('владение общим бюджетом переходит самому раннему участнику', () async {
    final familyBefore = await budget(familyId);
    final borisBefore = await member(familyId, boris.id);
    final olgaBefore = await member(familyId, olga.id);

    expect((await deleteAccount()).status, 204);

    final familyAfter = await budget(familyId);
    expect(familyAfter[0], boris.id);
    expect(familyAfter[1], false);
    expect(familyAfter[2]! as int, greaterThan(familyBefore[2]! as int));
    expect(familyAfter[3], olga.id);
    final borisAfter = await member(familyId, boris.id);
    expect(borisAfter.sublist(0, 2), ['owner', false]);
    expect(borisAfter[2]! as int, greaterThan(borisBefore[2]! as int));
    final olgaAfter = await member(familyId, olga.id);
    expect(olgaAfter.sublist(0, 2), ['member', true]);
    expect(olgaAfter[2]! as int, greaterThan(olgaBefore[2]! as int));
    expect((await member(familyId, vera.id)).sublist(0, 2), ['member', false]);
    expect(
      await api.count(
        'SELECT count(*)::int FROM invites '
        r'WHERE budget_id = $1::uuid AND revoked_at IS NULL',
        [familyId],
      ),
      0,
    );
    expect(
      logs.text,
      contains(
        'INFO  [account] account deletion: shared budget ownership transferred '
        'budgetId=$familyId userId=${olga.id} newOwnerId=${boris.id}',
      ),
    );
  });

  test(
    'траты в общих бюджетах остаются, автор — «Удалённый участник»',
    () async {
      final seqBefore = (await snapshot())['usersSeq']! as int;

      expect((await deleteAccount()).status, 204);

      final rows = await api.db.execute(
        r'SELECT id, author_id, deleted_at IS NULL FROM expenses '
        r'WHERE id = ANY($1::uuid[]) ORDER BY id',
        parameters: [
          [...olgaSharedExpenses, borisExpense],
        ],
      );
      expect(rows, hasLength(4));
      for (final row in rows) {
        expect(row[2], true, reason: 'expense ${row[0]} must stay alive');
        expect(
          row[1],
          row[0] == borisExpense ? boris.id : olga.id,
          reason: 'author of ${row[0]}',
        );
      }

      final user = await api.db.execute(
        r'SELECT display_name, birthday_month, birthday_day, '
        r'deleted_at IS NOT NULL, login, seq, password_hash, recovery_hash '
        r'FROM users WHERE id = $1::uuid',
        parameters: [olga.id],
      );
      final profile = user.single;
      expect(profile[0], deletedMemberName);
      expect(profile[0], 'Удалённый участник');
      expect(profile.sublist(1, 4), [null, null, true]);
      expect(profile[4], 'olga');
      expect(profile[5]! as int, greaterThan(seqBefore));
      expect(profile.sublist(6), ['', '']);
      expect(
        await api.count(
          r'SELECT count(*)::int FROM users WHERE deleted_at IS NULL',
        ),
        2,
      );

      final login = await api.login(login: 'olga');
      expect(login.status, 401);
      expect(login.errorCode, 'bad_credentials');
    },
  );

  test(
    'одиночный общий бюджет удаляется: траты, регулярные и категории стёрты, '
    'строки бюджета и участника остаются для синхронизации',
    () async {
      final soloBefore = await budget(soloId);

      expect((await deleteAccount()).status, 204);

      final soloAfter = await budget(soloId);
      expect(soloAfter[1], true);
      expect(soloAfter[2]! as int, greaterThan(soloBefore[2]! as int));
      for (final table in ['categories', 'expenses', 'recurring_rules']) {
        expect(
          await api.count(
            'SELECT count(*)::int FROM $table WHERE budget_id = \$1::uuid',
            [soloId],
          ),
          0,
          reason: '$table rows',
        );
      }
      expect((await member(soloId, olga.id))[1], true);
      expect(
        await api.count(
          'SELECT count(*)::int FROM invites '
          r'WHERE budget_id = $1::uuid AND revoked_at IS NULL',
          [soloId],
        ),
        0,
      );
      expect(
        logs.text,
        contains(
          'INFO  [account] account deletion: shared budget deleted, '
          'no members left budgetId=$soloId userId=${olga.id} '
          'erased categories=1 expenses=1 recurring=1',
        ),
      );
    },
  );

  test(
    'из чужого общего бюджета — просто выход, создатель не меняется',
    () async {
      expect((await deleteAccount()).status, 204);

      final friends = await budget(friendsId);
      expect(friends[0], vera.id);
      expect(friends[1], false);
      expect((await member(friendsId, olga.id)).sublist(0, 2), [
        'member',
        true,
      ]);
      expect((await member(friendsId, vera.id)).sublist(0, 2), [
        'owner',
        false,
      ]);
    },
  );

  test('все сессии стёрты вместе с названиями устройств: токены и refresh '
      'обоих устройств не работают', () async {
    expect(
      await api.count(
        r'SELECT count(*)::int FROM sessions '
        r'WHERE user_id = $1::uuid AND revoked_at IS NULL',
        [olga.id],
      ),
      2,
    );

    expect((await deleteAccount()).status, 204);

    expect(
      await api.count(
        r'SELECT count(*)::int FROM sessions WHERE user_id = $1::uuid',
        [olga.id],
      ),
      0,
    );
    expect(
      await api.count(
        r'SELECT count(*)::int FROM sessions WHERE user_id = $1::uuid',
        [boris.id],
      ),
      1,
    );
    final me = await api.send('GET', '/me', bearer: olga.accessToken);
    expect(me.status, 401);
    expect(me.errorCode, 'unauthorized');
    for (final refreshToken in [olga.refreshToken, olgaSecondRefresh]) {
      final refresh = await api.post(
        '/auth/refresh',
        body: {'refreshToken': refreshToken},
      );
      expect(refresh.status, 401);
      expect(refresh.errorCode, 'session_expired');
    }
    final again = await deleteAccount();
    expect(again.status, 401);
    expect(again.errorCode, 'unauthorized');
    expect(
      (await api.send('GET', '/me', bearer: boris.accessToken)).status,
      200,
    );
  });

  test(
    'итог в логе: сколько бюджетов удалено, передано, сколько сессий отозвано',
    () async {
      expect((await deleteAccount()).status, 204);

      expect(
        logs.text,
        contains(
          RegExp(
            'INFO  \\[account\\] account deleted userId=${olga.id} '
            'sessionId=\\S+ budgetsDeleted=2 \\(personal=1 shared=1\\) '
            'budgetsTransferred=1 budgetsLeft=1 sharedExpensesKept=3 '
            'invitesRevoked=2 sessionsDeleted=2 in \\d+ms',
          ),
        ),
      );
      expect(
        logs.text,
        contains(
          'INFO  [account] account deletion: personal budget deleted '
          'budgetId=$personalId userId=${olga.id}',
        ),
      );
      expect(
        logs.text,
        contains(
          'INFO  [account] account deletion: left shared budget '
          'budgetId=$friendsId userId=${olga.id} role=member',
        ),
      );
    },
  );
}
