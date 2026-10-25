import 'package:server/account/account_service.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/test_support.dart';
import 'support/web_support.dart';

const _olgaPassword = 'Olga-Right-Pass-Omega';
const _borisPassword = 'Boris-Right-Pass-Delta';
const _wrong = 'Wrong-Pass-Zeta-Kappa';

void main() {
  late LogCapture logs;
  late WebHarness web;
  late String olgaId;
  late String olgaToken;
  late String borisId;
  late String familyId;

  Future<String> registered(String login, String password) async {
    final response = await web.register(login, password);
    expect(response.status, 201, reason: '$response');
    return response.json['accessToken']! as String;
  }

  Future<String> userId(String login) async {
    final rows = await web.db.execute(
      r'SELECT id FROM users WHERE login = $1',
      parameters: [login],
    );
    return rows.single.first! as String;
  }

  setUp(() async {
    logs = LogCapture();
    web = await WebHarness.start();
    olgaToken = await registered('olga', _olgaPassword);
    await registered('boris', _borisPassword);
    olgaId = await userId('olga');
    borisId = await userId('boris');

    familyId = newId();
    await web.db.execute(
      r'INSERT INTO budgets (id, kind, name, emoji, owner_id, created_at, '
      r"updated_at, updated_by) VALUES ($1::uuid, 'shared', 'Семья', '🏠', "
      r'$2::uuid, now(), now(), $2::uuid)',
      parameters: [familyId, olgaId],
    );
    for (final (member, role, color, days) in [
      (olgaId, MemberRole.owner, CategoryColor.green, 5),
      (borisId, MemberRole.member, CategoryColor.orange, 2),
    ]) {
      await web.db.execute(
        r'INSERT INTO budget_members (budget_id, user_id, role, '
        r'avatar_color, joined_at) VALUES ($1::uuid, $2::uuid, $3, $4, '
        r'now() - make_interval(days => $5::int))',
        parameters: [familyId, member, role.name, color.name, days],
      );
    }
    logs.clear();
  });

  Future<Map<String, Object?>> snapshot() async {
    final rows = await web.db.execute(
      'SELECT '
      '(SELECT count(*)::int FROM budgets), '
      '(SELECT count(*)::int FROM users WHERE deleted_at IS NOT NULL), '
      '(SELECT count(*)::int FROM sessions WHERE revoked_at IS NOT NULL), '
      '(SELECT count(*)::int FROM budget_members WHERE left_at IS NOT NULL), '
      '(SELECT count(*)::int FROM categories)',
    );
    final row = rows.single;
    return {
      'budgets': row[0],
      'deletedUsers': row[1],
      'revokedSessions': row[2],
      'leftMembers': row[3],
      'categories': row[4],
    };
  }

  void expectWebHeaders(WebPage page) {
    expect(page.contentType, 'text/html; charset=utf-8');
    expect(page.headers['cache-control'], 'no-store');
    expect(
      page.headers['content-security-policy'],
      contains("default-src 'none'"),
    );
    expect(page.headers['x-content-type-options'], 'nosniff');
    expect(page.html, isNot(contains('<script')));
    expect(page.html, isNot(contains('http://')));
    expect(page.html, isNot(contains('https://')));
  }

  test('GET /delete-account → страница с формой логин + пароль, POST на тот '
      'же адрес, debug-строка показа', () async {
    final page = await web.get('/delete-account');

    expect(page.status, 200, reason: '$page');
    expectWebHeaders(page);
    expect(
      page.html,
      contains('<form class="card" method="post" action="/delete-account">'),
    );
    expect(page.html, contains('name="login" type="text"'));
    expect(page.html, contains('name="password" type="password"'));
    expect(page.html, contains('autocomplete="current-password"'));
    expect(page.html, contains('<button type="submit">'));
    expect(page.html, contains('<a href="/privacy">'));
    expect(page.html, isNot(contains('role="alert"')));
    expect(
      logs.lines,
      contains(
        matches(
          r'DEBUG \[web\] page shown /delete-account status=200 '
          r'contact=empty bytes=\d+',
        ),
      ),
    );
  });

  test('верные логин и пароль → 200 «Аккаунт удалён»; та же логика, что '
      'DELETE /account: личный бюджет удалён, общий передан, профиль стёрт, '
      'сессии стёрты', () async {
    final page = await web.deleteByForm(' OLGA ', _olgaPassword);

    expect(page.status, 200, reason: '$page');
    expectWebHeaders(page);
    expect(page.text, contains('Аккаунт удалён'));
    expect(page.html, contains('role="status"'));

    final user = (await web.db.execute(
      r'SELECT deleted_at IS NOT NULL, display_name, password_hash, '
      r'recovery_hash FROM users WHERE id = $1::uuid',
      parameters: [olgaId],
    )).single;
    expect(user.toList(), [true, deletedMemberName, '', '']);
    expect(
      await web.count(
        r"SELECT count(*)::int FROM budgets WHERE owner_id = $1::uuid "
        r"AND kind = 'personal'",
        [olgaId],
      ),
      0,
    );
    final family = (await web.db.execute(
      r'SELECT owner_id, deleted_at IS NULL FROM budgets WHERE id = $1::uuid',
      parameters: [familyId],
    )).single;
    expect(family.toList(), [borisId, true]);
    expect(
      await web.count(
        r'SELECT count(*)::int FROM sessions WHERE user_id = $1::uuid',
        [olgaId],
      ),
      0,
    );
    final me = await web.api('GET', '/me', bearer: olgaToken);
    expect(me.status, 401, reason: '$me');

    expect(
      logs.text,
      contains(
        'INFO  [account] account deletion: shared budget ownership '
        'transferred budgetId=$familyId userId=$olgaId newOwnerId=$borisId',
      ),
    );
    expect(
      logs.lines,
      contains(
        matches(
          'INFO  \\[account\\] account deleted userId=$olgaId via=web '
          'login=ol\\*\\*\\* budgetsDeleted=1 \\(personal=1 shared=0\\) '
          'budgetsTransferred=1 budgetsLeft=0 ',
        ),
      ),
    );
    expect(
      logs.lines,
      contains(
        matches(
          r'INFO  \[web\] delete-account form: account deleted '
          r'login=ol\*\*\* ip=198\.51\.100\.1 budgetsDeleted=1 '
          r'budgetsTransferred=1 budgetsLeft=0 sessionsDeleted=1 in \d+ms',
        ),
      ),
    );
    expect(logs.text, contains('POST /delete-account 200'));
  });

  test('неверный пароль → 401 «Неверный логин или пароль», логин остаётся в '
      'форме, пароля в ответе нет, ничего не удалено', () async {
    final before = await snapshot();

    final page = await web.deleteByForm('olga', _wrong);

    expect(page.status, 401, reason: '$page');
    expectWebHeaders(page);
    expect(page.html, contains('role="alert">Неверный логин или пароль.</p>'));
    expect(page.html, contains('value="olga"'));
    expect(page.html, isNot(contains(_wrong)));
    expect(await snapshot(), before);
    expect((await web.api('GET', '/me', bearer: olgaToken)).status, 200);
    expect(
      logs.lines,
      contains(
        matches(
          'WARN  \\[account\\] account deletion rejected '
          'reason=bad_credentials userId=$olgaId via=web login=ol\\*\\*\\* '
          'cause=password_mismatch in \\d+ms',
        ),
      ),
    );
    expect(
      logs.lines,
      contains(
        matches(
          r'WARN  \[web\] delete-account form rejected '
          r'reason=bad_credentials login=ol\*\*\* failures=1/5 '
          r'ip=198\.51\.100\.1 in \d+ms',
        ),
      ),
    );
    expect(logs.text, isNot(contains('account deleted')));
  });

  test('неизвестный логин → та же страница, что при неверном пароле; в логе '
      'cause=user_not_found без userId', () async {
    final wrongPassword = await web.deleteByForm('olga', _wrong);
    final unknownLogin = await web.deleteByForm('nobody', _wrong);

    expect(unknownLogin.status, wrongPassword.status);
    expect(
      unknownLogin.html.replaceAll('value="nobody"', 'value="olga"'),
      wrongPassword.html,
    );
    expect(
      logs.lines,
      contains(
        matches(
          r'WARN  \[account\] account deletion rejected '
          r'reason=bad_credentials via=web login=no\*\*\* '
          r'cause=user_not_found in \d+ms',
        ),
      ),
    );
  });

  test('уже удалённый аккаунт → повтор формы получает «Неверный логин или '
      'пароль», повторно ничего не удаляется', () async {
    expect((await web.deleteByForm('olga', _olgaPassword)).status, 200);
    final after = await snapshot();

    final again = await web.deleteByForm('olga', _olgaPassword);

    expect(again.status, 401);
    expect(again.text, contains('Неверный логин или пароль'));
    expect(await snapshot(), after);
  });

  test('пустые поля, не форма, битая кодировка → 400-страница, попытки по '
      'логину не засчитаны', () async {
    final before = await snapshot();

    final empty = await web.postForm(
      '/delete-account',
      fields: {'login': '  ', 'password': ''},
    );
    final noPassword = await web.postForm(
      '/delete-account',
      fields: {'login': 'olga'},
    );
    final json = await web.postForm(
      '/delete-account',
      rawBody: '{"login":"olga","password":"$_olgaPassword"}',
      contentType: 'application/json',
    );
    final badEncoding = await web.postForm(
      '/delete-account',
      rawBody: 'login=olga&password=Bad%ZZ-Percent-Pass',
    );

    for (final page in [empty, noPassword]) {
      expect(page.status, 400, reason: '$page');
      expectWebHeaders(page);
      expect(page.html, contains('role="alert">Введи логин и пароль.</p>'));
    }
    expect(noPassword.html, contains('value="olga"'));
    for (final page in [json, badEncoding]) {
      expect(page.status, 400, reason: '$page');
      expectWebHeaders(page);
      expect(page.text, contains('Не получилось прочитать форму'));
      expect(page.html, contains('name="password"'));
    }
    expect(await snapshot(), before);
    expect(web.limits.loginFailures.count('olga'), 0);
    expect(
      logs.text,
      contains(
        'WARN  [web] delete-account form rejected reason=bad_request '
        'missing=login,password ip=198.51.100.1',
      ),
    );
    expect(
      logs.text,
      contains(
        'WARN  [web] delete-account form rejected reason=bad_request '
        'problem="content-type is application/json, not '
        'application/x-www-form-urlencoded',
      ),
    );
    expect(
      logs.text,
      contains(
        'WARN  [web] delete-account form rejected reason=bad_request '
        'problem="form encoding invalid:',
      ),
    );
  });

  test('сбой базы → 500-страница с кодом запроса, попытка не засчитана, '
      'стек в логе', () async {
    await web.db.execute('ALTER TABLE users RENAME TO users_moved');

    final page = await web.deleteByForm('olga', _olgaPassword);

    expect(page.status, 500, reason: '$page');
    expect(page.contentType, 'text/html; charset=utf-8');
    expect(page.headers['x-content-type-options'], 'nosniff');
    expect(page.text, contains('Что-то пошло не так'));
    final rid = page.headers['x-request-id']!;
    expect(page.text, contains('Код запроса: $rid'));
    expect(web.limits.loginFailures.count('olga'), 0);
    expect(
      logs.text,
      contains('ERROR [web] web page failed POST /delete-account → 500 page:'),
    );
    expect(logs.text, contains('delete_account_page.dart'));
    expect(logs.text, contains('POST /delete-account 500'));
  });
}
