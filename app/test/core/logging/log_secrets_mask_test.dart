import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/core/logging/log_secrets.dart';

const String _jwt =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.'
    'eyJzdWIiOiJ1c2VyLTc3Iiwic2lkIjoic2Vzcy0xIn0.'
    'Qm9vb2tfc2lnbmF0dXJlX3RoYXRfaXNfbG9uZ19lbm91Z2g';

const String _refresh = 'Xk9mQ2pL7vR1tY4wZ8bN3cH6dF0gJ5sA2eU9iO1qW7r';

void main() {
  test('утёкшие токены, коды и пароли маскируются точечно, остальной текст '
      'строки на месте', () {
    final source = [
      'INFO  [api] GET /sync/pull header Authorization: Bearer $_jwt rid=ab12',
      'DEBUG [api] → POST /auth/refresh body={"refreshToken":"$_refresh"}',
      'INFO  [auth] token=$_jwt from deep link',
      'INFO  [auth] restored refresh $_refresh for userId=user-77',
      'INFO  [auth] code K7M2-P9QR-T4VW shown',
      'INFO  [budgets] invite MLN-7K2Q created',
      'DEBUG [api] body={"password":"Pw-alpha-bravo","login":"an***"}',
    ].join('\n');

    final check = maskLeakedSecrets(source);

    for (final secret in [
      _jwt,
      _refresh,
      'K7M2-P9QR-T4VW',
      'MLN-7K2Q',
      'Pw-alpha-bravo',
    ]) {
      expect(check.text, isNot(contains(secret)), reason: secret);
    }
    expect(check.text.split('\n'), [
      'INFO  [api] GET /sync/pull header Authorization: Bearer ***(${_jwt.length}) rid=ab12',
      'DEBUG [api] → POST /auth/refresh body={"refreshToken":"***(43)"}',
      'INFO  [auth] token=***(${_jwt.length}) from deep link',
      'INFO  [auth] restored refresh ***(43) for userId=user-77',
      'INFO  [auth] code ****-****-**** shown',
      'INFO  [budgets] invite MLN-**** created',
      'DEBUG [api] body={"password":"***(14)","login":"an***"}',
    ]);
    expect(check.found, {
      'bearer': 1,
      'jwt': 1,
      'field': 2,
      'token': 1,
      'recoveryCode': 1,
      'inviteCode': 1,
    });
    expect(check.clean, isFalse);
  });

  test('обычные строки лога (маски, rid, UUID, стек, даты, числа) не '
      'меняются', () {
    const source =
        '2026-10-24T10:00:01.123+03:00 INFO  [api] POST /auth/login 200 in '
        '120ms size=512 rid=7f3a9c0d1e2b4a5f\n'
        '2026-10-24T10:00:01.200+03:00 INFO  [auth] signed in login=an*** '
        'tokens=AuthTokens(access=***(171), refresh=***(43))\n'
        '2026-10-24T10:00:02.000+03:00 INFO  [profile] recovery code '
        '****-****-**** reissued userId=1b4e28ba-2fa1-11d2-883f-0016d3cca427\n'
        '2026-10-24T10:00:03.000+03:00 WARN  [budgets] invite MLN-**** '
        'expired budgetId=budget-shared-family\n'
        '  stack:\n'
        '    #0      _ProfileScreenState._sendLogs '
        '(package:milionchik/features/profile/profile_screen.dart:212:7)\n'
        '2026-10-24T10:00:04.000+03:00 INFO  [errors] error reports done '
        'sent=2 dropped=0 left=0 of 2 reason=start in 240ms\n'
        '2026-10-24T10:00:05.000+03:00 INFO  [db] request 1234-5678-9012 '
        'body={"password":"***(14)","accessToken":"<none>"}';

    final check = maskLeakedSecrets(source);

    expect(check.text, source);
    expect(check.clean, isTrue);
    expect(check.summary, 'none');
  });
}
