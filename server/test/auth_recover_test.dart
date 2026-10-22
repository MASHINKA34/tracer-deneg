import 'dart:math';

import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/auth_support.dart';
import 'support/test_support.dart';

final _codeShape = RegExp(
  r'^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$',
);

void main() {
  late LogCapture logs;
  late AuthHarness api;
  late String userId;
  late String recoveryCode;
  late String firstRefresh;

  setUp(() async {
    logs = LogCapture();
    api = await AuthHarness.start();
    final registered = await api.register(login: 'anna');
    userId =
        (registered.json['user']! as Map<String, Object?>)['id']! as String;
    recoveryCode = registered.json['recoveryCode']! as String;
    firstRefresh = registered.json['refreshToken']! as String;
    logs.clear();
  });

  Future<ApiResponse> recover({
    String login = 'anna',
    String? code,
    String newPassword = 'new-secret-pass-2',
    String deviceName = 'Redmi Note 13',
  }) => api.post(
    '/auth/recover',
    body: {
      'login': login,
      'recoveryCode': code ?? recoveryCode,
      'newPassword': newPassword,
      'deviceName': deviceName,
    },
  );

  Future<List<Object?>> storedHashes() async {
    final rows = await api.db.execute(
      r'SELECT password_hash, recovery_hash FROM users WHERE id = $1::uuid',
      parameters: [userId],
    );
    return rows.single.toList();
  }

  String otherValidCode() {
    final random = Random(35);
    while (true) {
      final candidate = generateRecoveryCode(random);
      if (candidate != recoveryCode) return candidate;
    }
  }

  group('POST /auth/recover', () {
    test('верный код в нижнем регистре с дефисами → 200: новый пароль, новый код, прочие сессии отозваны', () async {
      final second = await api.login(deviceName: 'Galaxy S24');
      expect(second.status, 200);
      final secondRefresh = second.json['refreshToken']! as String;

      final response = await recover(code: recoveryCode.toLowerCase());

      expect(response.status, 200);
      expect(response.headers['cache-control'], 'no-store');
      final body = response.json;
      expect(
        body.keys,
        unorderedEquals([
          'user',
          'accessToken',
          'refreshToken',
          'recoveryCode',
        ]),
      );
      final user = User.fromJson(body['user']);
      expect(user.id, userId);
      expect(user.login, 'anna');
      expect(user.displayName, 'Аня');
      final newCode = body['recoveryCode']! as String;
      expect(newCode, matches(_codeShape));
      expect(newCode, isNot(recoveryCode));

      final claims = api.auth.accessTokens
          .verify(body['accessToken']! as String)
          .claims!;
      expect(claims.userId, userId);
      final sessions = await api.db.execute(
        r'SELECT id, device_name, revoked_at IS NOT NULL FROM sessions '
        r'WHERE user_id = $1::uuid ORDER BY created_at',
        parameters: [userId],
      );
      expect(sessions, hasLength(3));
      expect(sessions[0][2], isTrue);
      expect(sessions[1][2], isTrue);
      expect(sessions[2].toList(), [claims.sessionId, 'Redmi Note 13', false]);

      for (final old in [firstRefresh, secondRefresh]) {
        final refreshed = await api.post(
          '/auth/refresh',
          body: {'refreshToken': old},
        );
        expect(refreshed.status, 401);
        expect(refreshed.errorCode, 'session_expired');
      }
      final fresh = await api.post(
        '/auth/refresh',
        body: {'refreshToken': body['refreshToken']},
      );
      expect(fresh.status, 200);

      expect((await api.login()).status, 401);
      expect((await api.login(password: 'new-secret-pass-2')).status, 200);

      expect(
        logs.text,
        contains(
          RegExp(
            'INFO  \\[auth\\] recover ok userId=$userId '
            'sessionId=${claims.sessionId} revokedSessions=2 in \\d+ms',
          ),
        ),
      );
    });

    test('после восстановления старый код не работает, новый работает без дефисов и в нижнем регистре', () async {
      final first = await recover();
      expect(first.status, 200);
      final newCode = first.json['recoveryCode']! as String;

      final withOldCode = await recover(newPassword: 'third-pass-3');
      expect(withOldCode.status, 401);
      expect(withOldCode.errorCode, 'bad_credentials');
      expect(
        logs.text,
        contains(
          'WARN  [auth] recover rejected reason=bad_credentials login=an*** '
          'userId=$userId cause=code_mismatch',
        ),
      );

      final withNewCode = await recover(
        code: newCode.replaceAll('-', '').toLowerCase(),
        newPassword: 'third-pass-3',
      );
      expect(withNewCode.status, 200);
      expect(withNewCode.json['recoveryCode'], isNot(newCode));
      expect(
        logs.text,
        contains(RegExp('recover ok userId=$userId .* revokedSessions=1 in')),
      );
      expect((await api.login(password: 'third-pass-3')).status, 200);
    });

    test('неверный код, неверный формат кода и несуществующий логин — одинаковый ответ 401 bad_credentials, ничего не изменилось', () async {
      final hashesBefore = await storedHashes();

      final wrongCode = await recover(code: otherValidCode());
      final malformedCode = await recover(code: 'UUUU-UUUU-UUUU');
      final noSuchLogin = await recover(login: 'nobody');

      expect(wrongCode.status, 401);
      expect(wrongCode.json, {
        'error': {
          'code': 'bad_credentials',
          'message': 'Неверный логин или код восстановления',
        },
      });
      for (final other in [malformedCode, noSuchLogin]) {
        expect(other.status, 401);
        expect(other.text, wrongCode.text);
        expect(
          other.headers['content-type'],
          wrongCode.headers['content-type'],
        );
        expect(
          other.headers['cache-control'],
          wrongCode.headers['cache-control'],
        );
      }

      expect(await storedHashes(), hashesBefore);
      expect(await api.count('SELECT count(*)::int FROM sessions'), 1);
      expect(
        await api.count(
          'SELECT count(*)::int FROM sessions WHERE revoked_at IS NOT NULL',
        ),
        0,
      );
      expect(
        (await api.post(
          '/auth/refresh',
          body: {'refreshToken': firstRefresh},
        )).status,
        200,
      );

      expect(
        logs.text,
        contains(
          'WARN  [auth] recover rejected reason=bad_credentials login=an*** '
          'userId=$userId cause=code_mismatch',
        ),
      );
      expect(
        logs.text,
        contains(
          'WARN  [auth] recover rejected reason=bad_credentials login=an*** '
          'userId=$userId cause=code_malformed',
        ),
      );
      expect(
        logs.text,
        contains(
          'WARN  [auth] recover rejected reason=bad_credentials login=no*** '
          'cause=user_not_found',
        ),
      );
      expect(
        RegExp(
          r'DEBUG \[auth\] argon2id verify purpose=recovery_code m=19456,t=2,p=1 match=false',
        ).allMatches(logs.text),
        hasLength(3),
      );
      expect(logs.text, isNot(contains('argon2id hash purpose=password')));
    });

    test(
      'удалённый аккаунт не восстанавливается: 401 bad_credentials',
      () async {
        await api.db.execute(
          r'UPDATE users SET deleted_at = now() WHERE id = $1::uuid',
          parameters: [userId],
        );
        final response = await recover();
        expect(response.status, 401);
        expect(response.errorCode, 'bad_credentials');
        expect(logs.text, contains('cause=user_not_found'));
      },
    );

    test('слабый новый пароль → 400 password_too_short, код не потрачен', () async {
      final hashesBefore = await storedHashes();

      final weak = await recover(newPassword: '12345');

      expect(weak.status, 400);
      expect(weak.errorCode, 'password_too_short');
      expect(await storedHashes(), hashesBefore);
      expect(
        logs.text,
        contains(
          'INFO  [auth] recover rejected reason=password_too_short login=an***',
        ),
      );
      expect((await recover()).status, 200);
    });

    test('нет полей в теле → 400 bad_request со списком полей', () async {
      final response = await api.post('/auth/recover', body: {'login': 'anna'});
      expect(response.status, 400);
      expect(response.errorCode, 'bad_request');
      expect(
        logs.text,
        contains(
          'recover rejected reason=bad_request '
          'fields=recoveryCode,newPassword,deviceName',
        ),
      );
    });

    test(
      'два восстановления одним кодом одновременно: успешно только одно',
      () async {
        final results = await Future.wait([
          recover(newPassword: 'parallel-pass-a', deviceName: 'Phone A'),
          recover(newPassword: 'parallel-pass-b', deviceName: 'Phone B'),
        ]);

        expect(results.map((r) => r.status).toList()..sort(), [200, 401]);
        final loser = results.firstWhere((r) => r.status == 401);
        expect(loser.errorCode, 'bad_credentials');
        expect(
          await api.count(
            'SELECT count(*)::int FROM sessions WHERE revoked_at IS NULL',
          ),
          1,
        );
        final winnerPassword = results[0].status == 200
            ? 'parallel-pass-a'
            : 'parallel-pass-b';
        final loserPassword = results[0].status == 200
            ? 'parallel-pass-b'
            : 'parallel-pass-a';
        expect((await api.login(password: winnerPassword)).status, 200);
        expect((await api.login(password: loserPassword)).status, 401);
      },
    );
  });
}
