import 'package:test/test.dart';

import 'support/auth_support.dart';
import 'support/shared_budget_support.dart';
import 'support/test_support.dart';

const _login = 'tainyilogin.akkaunt';
const _displayName = 'Тайное Имя Аккаунта';
const _newName = 'Тайное Новое Имя';
const _failingName = 'Тайное Имя Сбоя';
const _password = 'Пароль-Удаления-Тайный-36';
const _wrongPassword = 'Пароль-Удаления-Неверный-36';

void main() {
  late LogCapture logs;
  late AuthHarness api;
  late TestUser user;

  setUp(() async {
    logs = LogCapture();
    api = await AuthHarness.start();
    user = await registerTestUser(
      api,
      _login,
      displayName: _displayName,
      password: _password,
    );
  });

  Future<ApiResponse> patchMe(Object? body) =>
      api.send('PATCH', '/me', body: body, bearer: user.accessToken);

  Future<ApiResponse> deleteAccount(String password) => api.send(
    'DELETE',
    '/account',
    body: {'password': password},
    bearer: user.accessToken,
  );

  void expectNoSecrets() {
    for (final secret in [
      _login,
      _displayName,
      _newName,
      _failingName,
      _password,
      _wrongPassword,
    ]) {
      expect(
        logs.text.toLowerCase(),
        isNot(contains(secret.toLowerCase())),
        reason: 'secret in log: $secret',
      );
    }
    expect(logs.text, isNot(contains(r'$argon2id$')));
    expect(logs.text, isNot(contains('MonthDay(')));
    expect(logs.text, isNot(contains(RegExp(r'"birthday(Month|Day)"\s*:'))));
    expect(
      logs.text,
      isNot(contains(RegExp(r'birthday(Month|Day)?[=:]\s*\d'))),
    );
    expect(logs.text, isNot(contains(RegExp(r'Failing row contains \([^…]'))));
  }

  test('PATCH /me: имя и дата рождения не попадают в лог ни при успехе, ни при отказе, ни при ошибке базы', () async {
    expect(
      (await patchMe({
        'displayName': _newName,
        'birthdayMonth': 11,
        'birthdayDay': 17,
      })).status,
      200,
    );
    expect(
      (await patchMe({'birthdayMonth': 4, 'birthdayDay': 31})).errorCode,
      'birthday_invalid',
    );
    expect(
      (await patchMe({'displayName': _newName * 3})).errorCode,
      'name_too_long',
    );
    expect(
      (await api.send(
        'PATCH',
        '/me',
        rawBody: '{"displayName": "$_newName", "birthdayMonth": 11',
        bearer: user.accessToken,
      )).errorCode,
      'bad_request',
    );

    await api.db.execute(
      'ALTER TABLE users ADD CONSTRAINT test_reject_name '
      "CHECK (display_name <> '$_failingName')",
    );
    final failed = await patchMe({
      'displayName': _failingName,
      'birthdayMonth': 12,
      'birthdayDay': 24,
    });

    expect(failed.status, 500);
    expect(logs.text, contains('query update profile failed'));
    expect(logs.text, contains('23514'));
    expect(logs.text, contains('test_reject_name'));
    final stored = await api.db.execute(
      r'SELECT display_name, birthday_month, birthday_day FROM users '
      r'WHERE id = $1::uuid',
      parameters: [user.id],
    );
    expect(stored.single.toList(), [_newName, 11, 17]);
    expectNoSecrets();
  });

  test('DELETE /account: пароль и логин не попадают в лог при отказе, ошибке базы и успехе; ошибка базы откатывает всё', () async {
    expect((await deleteAccount(_wrongPassword)).errorCode, 'bad_credentials');
    expect(
      (await api.send(
        'DELETE',
        '/account',
        rawBody: '{"password": "$_password"',
        bearer: user.accessToken,
      )).errorCode,
      'bad_request',
    );

    await api.db.execute(
      'ALTER TABLE users ADD CONSTRAINT test_keep_alive '
      'CHECK (deleted_at IS NULL)',
    );
    final failed = await deleteAccount(_password);

    expect(failed.status, 500);
    expect(
      logs.text,
      contains('query mark user deleted and clear profile failed'),
    );
    expect(logs.text, contains('23514'));
    expect(logs.text, contains('transaction delete account rolled back'));
    expect(logs.text, isNot(contains('account deletion: personal budget')));
    expect(
      await api.count(
        r'SELECT count(*)::int FROM budgets WHERE owner_id = $1::uuid',
        [user.id],
      ),
      1,
    );
    expect(
      await api.count(
        r'SELECT count(*)::int FROM sessions '
        r'WHERE user_id = $1::uuid AND revoked_at IS NULL',
        [user.id],
      ),
      1,
    );
    expect(
      await api.count(
        r'SELECT count(*)::int FROM users '
        r'WHERE id = $1::uuid AND deleted_at IS NULL AND display_name = $2',
        [user.id, _displayName],
      ),
      1,
    );

    await api.db.execute('ALTER TABLE users DROP CONSTRAINT test_keep_alive');
    expect((await deleteAccount(_password)).status, 204);
    expect(logs.text, contains('account deleted userId=${user.id}'));
    expectNoSecrets();
  });
}
