import 'package:server/admin/admin_cli.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/auth_support.dart';
import 'support/shared_budget_support.dart';
import 'support/test_support.dart';

void main() {
  late LogCapture logs;
  late List<String> out;
  late String url;
  late AuthHarness api;
  late TestUser olga;
  late TestUser boris;
  late String personalId;
  late String familyId;
  late String soloId;
  late int personalCategories;

  setUp(() async {
    logs = LogCapture();
    out = [];
    url = await createScratchDatabase();
    api = await AuthHarness.start(databaseUrl: url);
    final fixture = SharedBudgetFixture(api);
    olga = await registerTestUser(api, 'olga', displayName: 'Ольга');
    boris = await registerTestUser(api, 'boris', displayName: 'Борис');

    personalId = await fixture.personalBudgetOf(olga.id);
    personalCategories = await api.count(
      r'SELECT count(*)::int FROM categories WHERE budget_id = $1::uuid',
      [personalId],
    );
    final personalCategory =
        (await api.db.execute(
              r'SELECT id FROM categories WHERE budget_id = $1::uuid LIMIT 1',
              parameters: [personalId],
            )).single.first!
            as String;
    await fixture.expense(personalId, personalCategory, olga.id);
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
      boris.id,
      role: MemberRole.member,
      color: CategoryColor.orange,
      joinedDaysAgo: 3,
    );
    final familyCategory = await fixture.category(familyId, olga.id);
    await fixture.expense(familyId, familyCategory, olga.id);
    await fixture.expense(familyId, familyCategory, boris.id);

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
    logs.clear();
  });

  Future<int> admin(List<String> args) => runAdmin(
    ['delete-account', ...args],
    environment: {'DATABASE_URL': url},
    out: out.add,
  );

  Future<List<Object?>> snapshot() async => (await api.db.execute(
    'SELECT '
    '(SELECT count(*)::int FROM users WHERE deleted_at IS NULL), '
    '(SELECT count(*)::int FROM budgets WHERE deleted_at IS NULL), '
    '(SELECT count(*)::int FROM expenses), '
    '(SELECT count(*)::int FROM sessions), '
    '(SELECT count(*)::int FROM budget_members WHERE left_at IS NULL)',
  )).single.toList();

  test(
    'без --yes: план в stdout, в базе ничего не изменилось, код 0',
    () async {
      final before = await snapshot();

      final code = await admin(['olga']);

      expect(code, adminExitOk, reason: logs.text);
      expect(await snapshot(), before);
      expect(
        out.first,
        'account olga userId=${olga.id}: nothing deleted yet, run again with '
        '--yes to delete',
      );
      expect(
        out.sublist(1),
        unorderedEquals([
          '  personal budget $personalId: erased with 2 expenses, 1 recurring, '
              '$personalCategories categories',
          '  shared budget $familyId: owner, 1 other member → ownership passes '
              'to the earliest member, own expenses stay: 1',
          '  shared budget $soloId: owner, no other members → erased with 1 '
              'expense',
          '  sessions: 1 → deleted',
          '  profile: name, birthday, password and recovery code erased; login '
              'released, it can be registered again',
        ]),
      );
      expect(
        logs.text,
        contains(
          RegExp(
            r'INFO  \[admin\] admin delete-account plan shown login=ol\*\*\* '
            'userId=${olga.id} personal=1 shared=2 sessions=1 '
            r'in \d+ms → exit 0',
          ),
        ),
      );
    },
  );

  test('--yes: удалён той же логикой, что в приложении, вход невозможен, '
      'код 0', () async {
    final code = await admin(['--yes', ' OLGA ']);

    expect(code, adminExitOk, reason: logs.text);
    expect(out, [
      'account olga userId=${olga.id} deleted: budgetsDeleted=2 '
          '(personal=1 shared=1) budgetsTransferred=1 budgetsLeft=0 '
          'sharedExpensesKept=1 invitesRevoked=0 sessionsDeleted=1',
    ]);
    expect(
      await api.count(
        r'SELECT count(*)::int FROM users WHERE id = $1::uuid '
        'AND deleted_at IS NOT NULL',
        [olga.id],
      ),
      1,
    );
    expect(
      await api.count(
        r'SELECT count(*)::int FROM budgets WHERE id = $1::uuid',
        [personalId],
      ),
      0,
    );
    expect(
      (await api.db.execute(
        r'SELECT owner_id FROM budgets WHERE id = $1::uuid',
        parameters: [familyId],
      )).single.first,
      boris.id,
    );
    expect(
      await api.count(
        r'SELECT count(*)::int FROM expenses WHERE budget_id = $1::uuid',
        [soloId],
      ),
      0,
    );
    expect(
      await api.count(
        r'SELECT count(*)::int FROM sessions WHERE user_id = $1::uuid',
        [olga.id],
      ),
      0,
    );
    final login = await api.login(login: 'olga');
    expect(login.status, 401);
    expect(
      logs.text,
      contains(
        RegExp(
          r'INFO  \[account\] account deleted userId=\S+ via=admin '
          r'login=ol\*\*\* budgetsDeleted=2 ',
        ),
      ),
    );
    expect(
      logs.text,
      contains(
        RegExp(
          r'INFO  \[admin\] admin delete-account done login=ol\*\*\* '
          'userId=${olga.id} in \\d+ms → exit 0',
        ),
      ),
    );
  });

  test('нет такого логина или аккаунт уже удалён → код 1, понятная строка, '
      'ничего не удалено', () async {
    final before = await snapshot();

    expect(await admin(['nobody']), adminExitFailure);
    expect(await admin(['nobody', '--yes']), adminExitFailure);
    expect(await snapshot(), before);
    expect(out, [
      'no account with login nobody',
      'no account with login nobody',
    ]);
    expect(
      logs.text,
      contains(
        'ERROR [admin] admin delete-account: no account with login no*** '
        '→ nothing deleted, exit 1',
      ),
    );

    out.clear();
    expect(await admin(['olga', '--yes']), adminExitOk);
    out.clear();
    expect(await admin(['olga']), adminExitFailure);
    expect(await admin(['olga', '--yes']), adminExitFailure);
    expect(out, ['no account with login olga', 'no account with login olga']);
  });

  test('неверные аргументы → справка и код 64, база не открывается', () async {
    for (final args in [
      <String>[],
      ['olga', 'boris'],
      ['--force', 'olga'],
      ['o!'],
    ]) {
      out.clear();
      expect(await admin(args), adminExitUsage, reason: '$args');
      expect(out.join('\n'), contains('delete-account <login> [--yes]'));
    }
    expect(
      logs.text,
      contains('ERROR [admin] delete-account: needs exactly one <login>'),
    );
    expect(
      logs.text,
      contains('ERROR [admin] delete-account: unknown option "--force"'),
    );
    expect(
      logs.text,
      contains(
        'ERROR [admin] delete-account: login "***" is not valid '
        '(3-32 characters a-z 0-9 _ .)',
      ),
    );
    expect(logs.text, isNot(contains('admin delete-account login=')));
  });

  test('справка admin описывает delete-account', () async {
    final code = await runAdmin(['help'], environment: const {}, out: out.add);

    expect(code, adminExitOk);
    expect(out.single, contains('delete-account <login> [--yes]'));
    expect(out.single, contains('PRIVACY_CONTACT'));
  });

  test('в логе маска логина, без имени и пароля', () async {
    await admin(['olga']);
    await admin(['olga', '--yes']);

    expect(logs.text, contains('login=ol***'));
    expect(logs.text, isNot(contains('login=olga')));
    expect(logs.text, isNot(contains('Ольга')));
    expect(logs.text, isNot(contains(olga.password)));
  });
}
