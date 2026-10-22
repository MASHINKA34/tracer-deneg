import 'dart:math';

import 'package:server/auth/tokens.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/auth_support.dart';
import 'support/test_support.dart';

const _login = 'tainyilogin.vosst';
const _displayName = 'Тайное Имя Восстановления';
const _password = 'Пароль-Тайный-Старый-35';
const _newPassword = 'Пароль-Тайный-Новый-36';
const _wrongPassword = 'Пароль-Тайный-Неверный-37';
const _malformedCode = 'TAINY-KOD-NEVERNYI-UUU';

void main() {
  late LogCapture logs;
  late AuthHarness api;
  late String recoveryCode;
  late String accessToken;
  late String refreshToken;

  setUp(() async {
    logs = LogCapture();
    api = await AuthHarness.start();
    final registered = await api.register(
      login: _login,
      displayName: _displayName,
      password: _password,
    );
    expect(registered.status, 201);
    recoveryCode = registered.json['recoveryCode']! as String;
    accessToken = registered.json['accessToken']! as String;
    refreshToken = registered.json['refreshToken']! as String;
  });

  Future<ApiResponse> recover({
    String login = _login,
    required String code,
    String newPassword = _newPassword,
  }) => api.post(
    '/auth/recover',
    body: {
      'login': login,
      'recoveryCode': code,
      'newPassword': newPassword,
      'deviceName': 'Pixel 9',
    },
  );

  Future<List<String>> storedHashes() async {
    final rows = await api.db.execute(
      'SELECT password_hash, recovery_hash FROM users',
    );
    return [
      for (final row in rows)
        for (final hash in row) (hash! as String).split(r'$').last,
    ];
  }

  List<String> codeForms(String code) => [
    code,
    code.toLowerCase(),
    normalizeRecoveryCode(code)!,
    normalizeRecoveryCode(code)!.toLowerCase(),
  ];

  void expectNoSecrets(Iterable<String> secrets) {
    for (final secret in secrets) {
      expect(
        logs.text,
        isNot(contains(secret)),
        reason: 'secret in log: $secret',
      );
    }
    expect(logs.text, isNot(contains(r'$argon2id$')));
    expect(logs.text.toLowerCase(), isNot(contains(_login)));
    expect(logs.text, isNot(contains(_displayName)));
    expect(logs.text, isNot(contains(_password)));
    expect(logs.text, isNot(contains(_newPassword)));
    expect(logs.text, isNot(contains(_wrongPassword)));
    expect(logs.text, isNot(contains(_malformedCode)));
    expect(logs.text.toLowerCase(), isNot(contains('tainy-kod')));
  }

  test('восстановление и перевыпуск на debug: ни кодов, ни паролей, ни токенов, ни хешей, логин маской', () async {
    final random = Random(35);
    var wrongCode = generateRecoveryCode(random);
    while (wrongCode == recoveryCode) {
      wrongCode = generateRecoveryCode(random);
    }
    expect((await recover(code: wrongCode)).status, 401);
    expect((await recover(code: _malformedCode)).status, 401);
    expect(
      (await recover(login: 'nobody.$_login', code: recoveryCode)).status,
      401,
    );
    final recovered = await recover(
      code: normalizeRecoveryCode(recoveryCode)!.toLowerCase(),
    );
    expect(recovered.status, 200);
    final secondCode = recovered.json['recoveryCode']! as String;
    final recoveredAccess = recovered.json['accessToken']! as String;
    final recoveredRefresh = recovered.json['refreshToken']! as String;

    final rejected = await api.post(
      '/auth/recovery-code',
      body: {'password': _wrongPassword},
      bearer: recoveredAccess,
    );
    expect(rejected.status, 401);
    final reissued = await api.post(
      '/auth/recovery-code',
      body: {'password': _newPassword},
      bearer: recoveredAccess,
    );
    expect(reissued.status, 200);
    final thirdCode = reissued.json['recoveryCode']! as String;
    final again = await recover(
      code: thirdCode.toLowerCase(),
      newPassword: _password,
    );
    expect(again.status, 200);

    expect(logs.text, contains('login=ta***'));
    expect(logs.text, contains('recover ok userId='));
    expect(logs.text, contains('recovery code reissued userId='));
    expect(logs.text, contains('cause=code_mismatch'));
    expect(logs.text, contains('cause=code_malformed'));
    expect(logs.text, contains('cause=user_not_found'));
    expect(logs.text, contains('cause=password_mismatch'));
    expectNoSecrets([
      ...codeForms(recoveryCode),
      ...codeForms(wrongCode),
      ...codeForms(secondCode),
      ...codeForms(thirdCode),
      ...codeForms(again.json['recoveryCode']! as String),
      accessToken,
      refreshToken,
      hashRefreshToken(refreshToken),
      recoveredAccess,
      recoveredRefresh,
      hashRefreshToken(recoveredRefresh),
      again.json['accessToken']! as String,
      again.json['refreshToken']! as String,
      ...await storedHashes(),
    ]);
  });

  test('ошибка Postgres при смене пароля и кода: в логе SQLSTATE и ограничение, без хешей и логина, ничего не изменилось', () async {
    final hashesBefore = await storedHashes();
    await api.db.execute(
      'ALTER TABLE users ADD CONSTRAINT test_reject_recover '
      'CHECK (length(recovery_hash) < 10) NOT VALID',
    );
    logs.clear();

    final response = await recover(code: recoveryCode);

    expect(response.status, 500);
    expect(logs.text, contains('sqlState=23514'));
    expect(logs.text, contains('constraint test_reject_recover'));
    expect(logs.text, contains('transaction recover rolled back'));
    expect(
      logs.text,
      contains('ERROR [http] unhandled error in POST /api/v1/auth/recover'),
    );
    expectNoSecrets([...codeForms(recoveryCode), ...hashesBefore]);
    expect(await storedHashes(), hashesBefore);
    expect(
      await api.count(
        'SELECT count(*)::int FROM sessions WHERE revoked_at IS NULL',
      ),
      1,
    );
  });

  test('ошибка Postgres при перевыпуске кода: в логе SQLSTATE и ограничение, без хешей и логина, код прежний', () async {
    final hashesBefore = await storedHashes();
    await api.db.execute(
      'ALTER TABLE users ADD CONSTRAINT test_reject_reissue '
      'CHECK (length(recovery_hash) < 10) NOT VALID',
    );
    logs.clear();

    final response = await api.post(
      '/auth/recovery-code',
      body: {'password': _password},
      bearer: accessToken,
    );

    expect(response.status, 500);
    expect(logs.text, contains('sqlState=23514'));
    expect(logs.text, contains('constraint test_reject_reissue'));
    expect(
      logs.text,
      contains(
        'ERROR [http] unhandled error in POST /api/v1/auth/recovery-code',
      ),
    );
    expectNoSecrets([...codeForms(recoveryCode), ...hashesBefore]);
    expect(await storedHashes(), hashesBefore);
  });
}
