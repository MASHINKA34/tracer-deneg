import 'package:test/test.dart';

import 'support/test_support.dart';
import 'support/web_support.dart';

const _margoPassword = 'Margo-Secret-Pass-Theta';
const _valyaPassword = 'Valya-Secret-Pass-Iota';
const _wrongPassword = 'Wrong-Secret-Pass-Kappa';

void main() {
  late LogCapture logs;
  late WebHarness web;

  setUp(() async {
    logs = LogCapture();
    web = await WebHarness.start();
    expect((await web.register('margarita', _margoPassword)).status, 201);
    expect((await web.register('valentina', _valyaPassword)).status, 201);
  });

  Future<String> passwordHash(String login) async {
    final rows = await web.db.execute(
      r'SELECT password_hash FROM users WHERE login = $1',
      parameters: [login],
    );
    return rows.single.first! as String;
  }

  test('на debug ни пароль, ни хэш, ни полный логин не попадают в лог: '
      'показ формы, неверный пароль, неизвестный логин, битая форма, '
      'JSON, удаление, сбой базы', () async {
    final margoHash = await passwordHash('margarita');
    final valyaHash = await passwordHash('valentina');
    logs.clear();

    expect((await web.get('/delete-account')).status, 200);
    expect((await web.deleteByForm('margarita', _wrongPassword)).status, 401);
    expect(
      (await web.deleteByForm('zinovy_unknown', _wrongPassword)).status,
      401,
    );
    expect(
      (await web.postForm(
        '/delete-account',
        rawBody: 'login=margarita&password=$_margoPassword%ZZ',
      )).status,
      400,
    );
    expect(
      (await web.postForm(
        '/delete-account',
        rawBody: '{"login":"margarita","password":"$_margoPassword"}',
        contentType: 'application/json',
      )).status,
      400,
    );
    expect((await web.deleteByForm('Margarita', _margoPassword)).status, 200);

    await web.db.execute(
      'ALTER TABLE users ADD CONSTRAINT users_keep_password '
      "CHECK (password_hash <> '') NOT VALID",
    );
    expect((await web.deleteByForm('valentina', _valyaPassword)).status, 500);

    final text = logs.text;
    for (final secret in [
      _margoPassword,
      _valyaPassword,
      _wrongPassword,
      margoHash,
      valyaHash,
      'margarita',
      'Margarita',
      'valentina',
      'zinovy_unknown',
    ]) {
      expect(text, isNot(contains(secret)), reason: secret);
    }
    expect(text, contains('login=ma***'));
    expect(text, contains('login=va***'));
    expect(text, contains('login=zi***'));
    expect(text, contains('find user by login for account deletion'));
    expect(text, contains('ERROR [web] web page failed POST /delete-account'));
    expect(text, contains('constraint users_keep_password'));
    expect(text, contains('Failing row contains (…)'));
  });
}
