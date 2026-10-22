import 'package:server/auth/auth_service.dart';
import 'package:server/auth/password_hasher.dart';
import 'package:server/auth/tokens.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/auth_support.dart';
import 'support/test_support.dart';

void main() {
  late LogCapture logs;
  late AuthHarness api;

  setUp(() async {
    logs = LogCapture();
    api = await AuthHarness.start();
  });

  group('POST /auth/register', () {
    test('201: пользователь, токены и код восстановления один раз', () async {
      final response = await api.register(login: '  Anna.K  ');

      expect(response.status, 201);
      expect(response.headers['cache-control'], 'no-store');
      final body = response.json;
      final user = User.fromJson(body['user']);
      expect(user.login, 'anna.k');
      expect(user.displayName, 'Аня');
      expect(user.holidaysEnabled, isTrue);
      expect(user.birthday, isNull);
      expect(
        body['recoveryCode'],
        matches(RegExp(r'^[0-9A-Z]{4}-[0-9A-Z]{4}-[0-9A-Z]{4}$')),
      );
      expect(normalizeRecoveryCode(body['recoveryCode']! as String), isNotNull);
      expect(body['refreshToken'], matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));

      final claims = api.auth.accessTokens.verify(
        body['accessToken']! as String,
      );
      expect(claims.rejection, isNull);
      expect(claims.claims!.userId, user.id);

      final rows = await api.db.execute(
        r'SELECT login, display_name, password_hash, recovery_hash '
        r'FROM users WHERE id = $1::uuid',
        parameters: [user.id],
      );
      final row = rows.single;
      expect(row[0], 'anna.k');
      expect(row[1], 'Аня');
      final hasher = PasswordHasher();
      expect(row[2], startsWith(r'$argon2id$v=19$m=19456,t=2,p=1$'));
      expect(
        await hasher.verify(
          'secret-pass-1',
          row[2]! as String,
          purpose: 'test',
        ),
        isTrue,
      );
      expect(row[3], startsWith(r'$argon2id$v=19$m=19456,t=2,p=1$'));
      expect(
        await hasher.verify(
          normalizeRecoveryCode(body['recoveryCode']! as String)!,
          row[3]! as String,
          purpose: 'test',
        ),
        isTrue,
      );
      expect(row[2], isNot(contains('secret-pass-1')));
    });

    test('у нового пользователя личный бюджет, он создатель и 11 готовых категорий', () async {
      final response = await api.register();
      final userId =
          (response.json['user']! as Map<String, Object?>)['id']! as String;

      final budgets = await api.db.execute(
        r'SELECT id, kind, name, emoji, owner_id, updated_by, deleted_at '
        r'FROM budgets WHERE owner_id = $1::uuid',
        parameters: [userId],
      );
      expect(budgets, hasLength(1));
      final budget = budgets.single;
      final budgetId = budget[0]! as String;
      expect(budget.sublist(1), [
        'personal',
        personalBudgetName,
        personalBudgetEmoji,
        userId,
        userId,
        null,
      ]);
      expect(personalBudgetName, 'Личный бюджет');
      expect(personalBudgetEmoji, '👛');

      final members = await api.db.execute(
        r'SELECT user_id, role, avatar_color, left_at FROM budget_members '
        r'WHERE budget_id = $1::uuid',
        parameters: [budgetId],
      );
      expect(members.map((r) => r.toList()), [
        [userId, 'owner', 'green', null],
      ]);

      final categories = await api.db.execute(
        r'SELECT name, emoji, color, sort_order, is_system, updated_by, deleted_at '
        r'FROM categories WHERE budget_id = $1::uuid ORDER BY sort_order',
        parameters: [budgetId],
      );
      expect(categories, hasLength(11));
      expect(categories.map((r) => r.toList()), [
        for (final preset in presetCategories)
          [
            preset.name,
            preset.emoji,
            preset.color?.name,
            preset.sortOrder,
            preset.isSystem,
            userId,
            null,
          ],
      ]);
      expect(categories.where((r) => r[4] == true).map((r) => r[0]), [
        'Другое',
      ]);

      final sessions = await api.db.execute(
        r'SELECT device_name, refresh_hash, revoked_at, '
        r"expires_at > now() + interval '89 days', "
        r"expires_at < now() + interval '91 days' "
        r'FROM sessions WHERE user_id = $1::uuid',
        parameters: [userId],
      );
      expect(sessions.single.toList(), [
        'Pixel 7',
        hashRefreshToken(response.json['refreshToken']! as String),
        null,
        true,
        true,
      ]);
    });

    test('логин занят без учёта регистра → 409 login_taken, второй пользователь не создан', () async {
      expect((await api.register(login: 'anna')).status, 201);

      final again = await api.register(login: 'ANNA', displayName: 'Другая');
      expect(again.status, 409);
      expect(again.json, {
        'error': {'code': 'login_taken', 'message': 'Такой логин уже занят'},
      });
      expect(await api.count('SELECT count(*)::int FROM users'), 1);
      expect(await api.count('SELECT count(*)::int FROM budgets'), 1);
      expect(await api.count('SELECT count(*)::int FROM sessions'), 1);
      expect(
        logs.text,
        contains(
          'INFO  [auth] register rejected reason=login_taken login=an***',
        ),
      );
    });

    test('логин заняли одновременно: один 201, второй 409, без 500', () async {
      final results = await Future.wait([
        api.register(login: 'twin'),
        api.register(login: 'TWIN'),
      ]);
      expect(results.map((r) => r.status), unorderedEquals([201, 409]));
      expect(await api.count('SELECT count(*)::int FROM users'), 1);
      expect(await api.count('SELECT count(*)::int FROM categories'), 11);
    });

    for (final (name, fields, code) in <(String, Map<String, String>, String)>[
      ('логин короче 3', {'login': 'an'}, 'login_too_short'),
      ('логин длиннее 32', {'login': 'a' * 33}, 'login_too_long'),
      ('логин с кириллицей', {'login': 'аня'}, 'login_invalid_chars'),
      ('логин пустой', {'login': '   '}, 'login_empty'),
      ('пароль короче 6', {'password': '12345'}, 'password_too_short'),
      ('пароль длиннее 128', {'password': 'p' * 129}, 'password_too_long'),
      ('имя пустое', {'displayName': '  '}, 'name_empty'),
      ('имя длиннее 40', {'displayName': 'я' * 41}, 'name_too_long'),
    ]) {
      test(
        'валидация как в shared: $name → 400 $code, ничего не создано',
        () async {
          final response = await api.register(
            login: fields['login'] ?? 'anna',
            displayName: fields['displayName'] ?? 'Аня',
            password: fields['password'] ?? 'secret-pass-1',
          );
          expect(response.status, 400);
          expect(response.errorCode, code);
          expect(
            (response.json['error']! as Map)['message'],
            isA<String>().having((m) => m.isNotEmpty, 'not empty', isTrue),
          );
          expect(await api.count('SELECT count(*)::int FROM users'), 0);
        },
      );
    }

    test('пароль ровно 6 и логин ровно 3 — граница допустима', () async {
      final response = await api.register(login: 'ann', password: '123456');
      expect(response.status, 201);
    });

    test(
      'нет поля или неверный тип → 400 bad_request с именами полей',
      () async {
        final response = await api.post(
          '/auth/register',
          body: {'login': 'anna', 'password': 123, 'displayName': 'Аня'},
        );
        expect(response.status, 400);
        expect(response.errorCode, 'bad_request');
        expect(
          (response.json['error']! as Map)['message'],
          contains('password, deviceName'),
        );
        expect(
          logs.text,
          contains(
            'register rejected reason=bad_request fields=password,deviceName',
          ),
        );
        expect(await api.count('SELECT count(*)::int FROM users'), 0);
      },
    );

    test('тело не JSON или не объект → 400 bad_request', () async {
      final notJson = await api.post('/auth/register', rawBody: '{login: anna');
      expect(notJson.status, 400);
      expect(notJson.errorCode, 'bad_request');
      final array = await api.post('/auth/register', rawBody: '[1, 2]');
      expect(array.status, 400);
      expect(array.errorCode, 'bad_request');
    });

    test('пустое имя устройства → 400 bad_request', () async {
      final response = await api.register(deviceName: '   ');
      expect(response.status, 400);
      expect(response.errorCode, 'bad_request');
    });
  });

  test('регистрация на info: userId, sessionId, мс; хеширование на debug с временем', () async {
    final response = await api.register();
    final userId = (response.json['user']! as Map<String, Object?>)['id'];
    final sessionId = api.auth.accessTokens
        .verify(response.json['accessToken']! as String)
        .claims!
        .sessionId;
    expect(
      logs.text,
      contains(
        RegExp(
          'INFO  \\[auth\\] register ok userId=$userId sessionId=$sessionId '
          r'budgetId=[0-9a-f-]{36} categories=11 in \d+ms',
        ),
      ),
    );
    expect(
      logs.text,
      contains(
        RegExp(
          r'DEBUG \[auth\] argon2id hash purpose=password m=19456,t=2,p=1 in \d+ms',
        ),
      ),
    );
    expect(
      logs.text,
      contains(
        RegExp(
          r'DEBUG \[auth\] argon2id hash purpose=recovery_code m=19456,t=2,p=1 in \d+ms',
        ),
      ),
    );
    expect(AuthFailureReason.loginTaken.code, 'login_taken');
  });
}
