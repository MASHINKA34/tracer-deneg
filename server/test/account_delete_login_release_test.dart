import 'package:server/account/account_service.dart';
import 'package:server/admin/admin_cli.dart';
import 'package:server/db/database.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/auth_support.dart';
import 'support/budget_support.dart';
import 'support/push_support.dart';
import 'support/shared_budget_support.dart';
import 'support/sync_support.dart';
import 'support/test_support.dart';
import 'support/web_support.dart';

const _oldPassword = 'Olga-Old-Pass-Sigma';
const _newPassword = 'Olga-New-Pass-Theta';

Future<String> _storedLogin(Database db, String userId) async {
  final rows = await db.execute(
    r'SELECT login FROM users WHERE id = $1::uuid',
    parameters: [userId],
  );
  return rows.single.first! as String;
}

void main() {
  late LogCapture logs;

  setUp(() => logs = LogCapture());

  test('служебный логин deleted.<id без дефисов> длиннее loginMaxLength и не '
      'проходит validateLogin', () {
    const id = '0b8f6a2e-4c1d-4e7a-9f3b-5d2c8e1a7b40';

    final login = deletedAccountLogin(id);

    expect(login, 'deleted.0b8f6a2e4c1d4e7a9f3b5d2c8e1a7b40');
    expect(login.length, greaterThan(loginMaxLength));
    expect(validateLogin(login), ValidationError.loginTooLong);
    expect(deletedAccountLogin(id.toUpperCase()), login);
  });

  group('приложение: DELETE /account', () {
    late AuthHarness api;
    late TestUser olga;
    late String olgaRecoveryCode;
    late TestUser boris;
    late String familyId;
    late String familyCategory;
    late List<String> olgaExpenses;
    late String borisExpense;

    Future<(TestUser, String)> register(String login, String password) async {
      final response = await api.register(
        login: login,
        displayName: 'Ольга',
        password: password,
      );
      expect(response.status, 201, reason: '$response');
      final json = response.json;
      return (
        TestUser(
          id: (json['user']! as Map<String, Object?>)['id']! as String,
          login: login,
          password: password,
          accessToken: json['accessToken']! as String,
          refreshToken: json['refreshToken']! as String,
        ),
        json['recoveryCode']! as String,
      );
    }

    Future<ApiResponse> deleteOlga() => api.send(
      'DELETE',
      '/account',
      body: {'password': _oldPassword},
      bearer: olga.accessToken,
    );

    Future<ApiResponse> recover(String code) => api.post(
      '/auth/recover',
      body: {
        'login': 'olga',
        'recoveryCode': code,
        'newPassword': 'Olga-Recovered-Pass-Mu',
        'deviceName': 'Pixel 7',
      },
    );

    setUp(() async {
      api = await AuthHarness.start();
      final fixture = SharedBudgetFixture(api);
      (olga, olgaRecoveryCode) = await register('olga', _oldPassword);
      boris = await registerTestUser(api, 'boris', displayName: 'Борис');

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
        boris.id,
        role: MemberRole.member,
        color: CategoryColor.orange,
        joinedDaysAgo: 3,
      );
      familyCategory = await fixture.category(familyId, olga.id);
      olgaExpenses = [
        await fixture.expense(familyId, familyCategory, olga.id),
        await fixture.expense(familyId, familyCategory, olga.id),
      ];
      borisExpense = await fixture.expense(familyId, familyCategory, boris.id);
      logs.clear();
    });

    test('логин заменён служебным, регистрация с тем же логином → 201 с '
        'новым id, в логе «login released» без логина', () async {
      expect((await deleteOlga()).status, 204);

      expect(await _storedLogin(api.db, olga.id), deletedAccountLogin(olga.id));
      final (newOlga, _) = await register('olga', _newPassword);
      expect(newOlga.id, isNot(olga.id));
      expect(
        await api.count(
          r'SELECT count(*)::int FROM users WHERE lower(login) = $1',
          ['olga'],
        ),
        1,
      );
      final me = await api.send('GET', '/me', bearer: newOlga.accessToken);
      expect(me.status, 200, reason: '$me');
      expect(me.json['id'], newOlga.id);
      expect(me.json['login'], 'olga');

      final serviceLogin = await api.register(
        login: deletedAccountLogin(olga.id),
        password: _newPassword,
      );
      expect(serviceLogin.status, 400, reason: '$serviceLogin');
      expect(serviceLogin.errorCode, ValidationError.loginTooLong.code);

      expect(
        logs.lines,
        contains(
          matches(
            'INFO  \\[account\\] account deletion: login released '
            'userId=${olga.id} rid=\\S+\$',
          ),
        ),
      );
      expect(
        logs.text,
        contains(
          'DEBUG [account] account deletion: released login=ol*** '
          'userId=${olga.id} → free for new registrations',
        ),
      );
      expect(
        logs.text,
        contains(RegExp('INFO  \\[auth\\] register ok userId=${newOlga.id} ')),
      );
      expect(logs.text, isNot(contains('olga')));
      expect(logs.text, isNot(contains(olga.id.replaceAll('-', ''))));
    });

    test('новый аккаунт не видит общий бюджет и траты старого; у Бориса траты '
        'на месте с автором «Удалённый участник»', () async {
      expect((await deleteOlga()).status, 204);
      final (newOlga, _) = await register('olga', _newPassword);

      final mine = await pullUntilDone(api, newOlga);
      final budgets = mine.all((p) => p.budgets);
      expect(budgets, hasLength(1));
      expect(budgets.single.kind, BudgetKind.personal);
      expect(budgets.single.ownerId, newOlga.id);
      expect(mine.all((p) => p.expenses), isEmpty);
      expect(mine.all((p) => p.profiles), isEmpty);
      expect(
        mine.all((p) => p.members).map((m) => m.budgetId),
        everyElement(budgets.single.id),
      );

      final intruder = expenseRecord(
        budgetId: familyId,
        categoryId: familyCategory,
        authorId: newOlga.id,
      );
      final push = await pushAs(api, newOlga, [SyncChange.upsert(intruder)]);
      expect(push.rejected, [
        SyncRejection(id: intruder.id, code: ApiErrorCode.notFound.code),
      ]);
      expect(await rowCount(api, 'expenses', intruder.id), 0);
      final invite = await createInviteRaw(api, newOlga, familyId);
      expect(invite.status, 404, reason: '$invite');

      final theirs = await pullUntilDone(api, boris);
      final family = theirs
          .all((p) => p.budgets)
          .singleWhere((b) => b.id == familyId);
      expect(family.ownerId, boris.id);
      final familyExpenses = {
        for (final e in theirs.all((p) => p.expenses))
          if (e.budgetId == familyId) e.id: e.authorId,
      };
      expect(familyExpenses, {
        olgaExpenses[0]: olga.id,
        olgaExpenses[1]: olga.id,
        borisExpense: boris.id,
      });
      final profiles = {
        for (final p in theirs.all((p) => p.profiles)) p.userId: p.displayName,
      };
      expect(profiles[olga.id], deletedMemberName);
      expect(profiles, isNot(contains(newOlga.id)));
    });

    test('старый код восстановления и старые токены не работают, код нового '
        'аккаунта работает', () async {
      expect((await deleteOlga()).status, 204);
      final (newOlga, newRecoveryCode) = await register('olga', _newPassword);
      expect(newRecoveryCode, isNot(olgaRecoveryCode));

      final old = await recover(olgaRecoveryCode);
      expect(old.status, 401, reason: '$old');
      expect(old.errorCode, 'bad_credentials');

      final oldMe = await api.send('GET', '/me', bearer: olga.accessToken);
      expect(oldMe.status, 401);
      final oldRefresh = await api.post(
        '/auth/refresh',
        body: {'refreshToken': olga.refreshToken},
      );
      expect(oldRefresh.status, 401);

      final fresh = await recover(newRecoveryCode);
      expect(fresh.status, 200, reason: '$fresh');
      expect((fresh.json['user']! as Map<String, Object?>)['id'], newOlga.id);
    });
  });

  test('веб-форма /delete-account освобождает логин: регистрация с ним снова '
      '→ 201 с новым id', () async {
    final web = await WebHarness.start();
    final first = await web.register('vera', _oldPassword);
    expect(first.status, 201, reason: '$first');
    final oldId =
        (first.json['user']! as Map<String, Object?>)['id']! as String;
    logs.clear();

    final page = await web.deleteByForm('vera', _oldPassword);

    expect(page.status, 200, reason: '$page');
    expect(await _storedLogin(web.db, oldId), deletedAccountLogin(oldId));
    expect(
      logs.text,
      contains(
        'INFO  [account] account deletion: login released '
        'userId=$oldId',
      ),
    );
    final again = await web.register('vera', _newPassword);
    expect(again.status, 201, reason: '$again');
    expect((again.json['user']! as Map<String, Object?>)['id'], isNot(oldId));
    expect((await web.login('vera', _newPassword)).status, 200);
    expect((await web.login('vera', _oldPassword)).status, 401);
  });

  test('admin delete-account --yes освобождает логин; план говорит об этом, '
      'после новой регистрации команда видит новый аккаунт', () async {
    final url = await createScratchDatabase();
    final api = await AuthHarness.start(databaseUrl: url);
    final olga = await registerTestUser(api, 'olga', password: _oldPassword);
    final out = <String>[];
    Future<int> admin(List<String> args) => runAdmin(
      ['delete-account', ...args],
      environment: {'DATABASE_URL': url},
      out: out.add,
    );

    expect(await admin(['olga']), adminExitOk);
    expect(
      out.last,
      '  profile: name, birthday, password and recovery code erased; login '
      'released, it can be registered again',
    );
    out.clear();
    logs.clear();

    expect(await admin(['olga', '--yes']), adminExitOk, reason: logs.text);
    expect(await _storedLogin(api.db, olga.id), deletedAccountLogin(olga.id));
    expect(
      logs.text,
      contains(
        'INFO  [account] account deletion: login released '
        'userId=${olga.id}',
      ),
    );
    expect(logs.text, isNot(contains('olga')));

    final newOlga = await registerTestUser(api, 'olga', password: _newPassword);
    expect(newOlga.id, isNot(olga.id));
    out.clear();
    expect(await admin(['olga']), adminExitOk);
    expect(
      out.first,
      'account olga userId=${newOlga.id}: nothing deleted yet, run again with '
      '--yes to delete',
    );
  });
}
