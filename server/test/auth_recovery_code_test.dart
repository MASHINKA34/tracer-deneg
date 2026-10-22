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
  late String sessionId;
  late String accessToken;
  late String refreshToken;
  late String recoveryCode;

  setUp(() async {
    logs = LogCapture();
    api = await AuthHarness.start();
    final registered = await api.register();
    userId =
        (registered.json['user']! as Map<String, Object?>)['id']! as String;
    accessToken = registered.json['accessToken']! as String;
    refreshToken = registered.json['refreshToken']! as String;
    recoveryCode = registered.json['recoveryCode']! as String;
    sessionId = api.auth.accessTokens.verify(accessToken).claims!.sessionId;
    logs.clear();
  });

  Future<ApiResponse> reissue({String? password, String? bearer}) => api.post(
    '/auth/recovery-code',
    body: {'password': password ?? 'secret-pass-1'},
    bearer: bearer ?? accessToken,
  );

  Future<ApiResponse> recover(String code) => api.post(
    '/auth/recover',
    body: {
      'login': 'anna',
      'recoveryCode': code,
      'newPassword': 'new-secret-pass-2',
      'deviceName': 'Redmi Note 13',
    },
  );

  Future<List<Object?>> storedHashes() async {
    final rows = await api.db.execute(
      r'SELECT password_hash, recovery_hash FROM users WHERE id = $1::uuid',
      parameters: [userId],
    );
    return rows.single.toList();
  }

  group('POST /auth/recovery-code', () {
    test('верный пароль → 200 с новым кодом: старый код больше не работает, новый работает, сессии не тронуты', () async {
      final before = await storedHashes();

      final response = await reissue();

      expect(response.status, 200);
      expect(response.headers['cache-control'], 'no-store');
      expect(response.json.keys, ['recoveryCode']);
      final newCode = response.json['recoveryCode']! as String;
      expect(newCode, matches(_codeShape));
      expect(newCode, isNot(recoveryCode));

      final after = await storedHashes();
      expect(after[0], before[0]);
      expect(after[1], isNot(before[1]));
      expect(
        await api.count(
          'SELECT count(*)::int FROM sessions WHERE revoked_at IS NOT NULL',
        ),
        0,
      );
      expect(
        logs.text,
        contains(
          RegExp(
            'INFO  \\[auth\\] recovery code reissued userId=$userId '
            'sessionId=$sessionId in \\d+ms',
          ),
        ),
      );
      expect(
        (await api.post(
          '/auth/refresh',
          body: {'refreshToken': refreshToken},
        )).status,
        200,
      );

      final withOldCode = await recover(recoveryCode);
      expect(withOldCode.status, 401);
      expect(withOldCode.errorCode, 'bad_credentials');
      final withNewCode = await recover(newCode.toLowerCase());
      expect(withNewCode.status, 200);
    });

    test('неверный пароль → 401 bad_credentials, код не изменился и старый работает', () async {
      final before = await storedHashes();

      final response = await reissue(password: 'wrong-pass-1');

      expect(response.status, 401);
      expect(response.json, {
        'error': {'code': 'bad_credentials', 'message': 'Неверный пароль'},
      });
      expect(await storedHashes(), before);
      expect(
        logs.text,
        contains(
          'WARN  [auth] recovery code reissue rejected reason=bad_credentials '
          'userId=$userId sessionId=$sessionId cause=password_mismatch',
        ),
      );
      expect(logs.text, isNot(contains('recovery code reissued')));
      expect((await recover(recoveryCode)).status, 200);
    });

    test('без токена → 401 unauthorized, код не изменился', () async {
      final before = await storedHashes();
      final response = await api.post(
        '/auth/recovery-code',
        body: {'password': 'secret-pass-1'},
      );
      expect(response.status, 401);
      expect(response.errorCode, 'unauthorized');
      expect(await storedHashes(), before);
    });

    test('после восстановления с другого телефона старый токен не перевыпускает код', () async {
      expect((await recover(recoveryCode)).status, 200);
      logs.clear();

      final response = await reissue(password: 'new-secret-pass-2');

      expect(response.status, 401);
      expect(response.errorCode, 'unauthorized');
      expect(
        logs.text,
        contains(
          'unauthorized POST /api/v1/auth/recovery-code reason=session_revoked',
        ),
      );
    });

    test('нет пароля в теле → 400 bad_request', () async {
      final response = await api.post(
        '/auth/recovery-code',
        body: <String, Object?>{},
        bearer: accessToken,
      );
      expect(response.status, 400);
      expect(response.errorCode, 'bad_request');
      expect(
        logs.text,
        contains(
          'recovery code reissue rejected reason=bad_request fields=password',
        ),
      );
    });
  });
}
