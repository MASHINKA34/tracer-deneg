import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:server/budgets/budget_service.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/auth_support.dart';
import 'support/budget_support.dart';
import 'support/shared_budget_support.dart';
import 'support/test_support.dart';

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Future<String> _hmac(String secret, String text) async => _hex(
  (await Hmac.sha256().calculateMac(
    utf8.encode(text),
    secretKey: SecretKey(utf8.encode(secret)),
  )).bytes,
);

Future<String> _sha256(String text) async =>
    _hex((await Sha256().hash(utf8.encode(text))).bytes);

void main() {
  test('hashInviteCode — HMAC-SHA256 (RFC 4231, тест 2)', () {
    expect(
      hashInviteCode('what do ya want for nothing?', secret: 'Jefe'),
      '5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843',
    );
  });

  test('хеш зависит от секрета', () {
    final a = hashInviteCode('MLN-7QXW', secret: 'a' * 32);
    final b = hashInviteCode('MLN-7QXW', secret: 'b' * 32);
    expect(a, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(b, isNot(a));
    expect(hashInviteCode('MLN-7QXW', secret: 'a' * 32), a);
  });

  group('в базе', () {
    late LogCapture logs;
    late AuthHarness api;
    late TestUser olga;
    late TestUser boris;
    late Budget family;

    setUp(() async {
      logs = LogCapture();
      api = await AuthHarness.start();
      olga = await registerTestUser(api, 'olga', displayName: 'Ольга');
      boris = await registerTestUser(api, 'boris', displayName: 'Борис');
      family = await createSharedBudget(api, olga);
      logs.clear();
    });

    test('invites.code_hash — HMAC-SHA256 кода с INVITE_CODE_SECRET, а не '
        'SHA-256 кода; секрета и хеша нет в логах', () async {
      final code = await inviteCodeFor(api, olga, family.id);
      final rows = await api.db.execute(
        r'SELECT code_hash FROM invites WHERE budget_id = $1::uuid',
        parameters: [family.id],
      );
      final stored = rows.single[0]! as String;

      expect(stored, await _hmac(testInviteCodeSecret, code));
      expect(stored, isNot(await _sha256(code)));
      expect((await joinRaw(api, boris, code)).status, 200);

      expect(logs.text, isNot(contains(testInviteCodeSecret)));
      expect(logs.text, isNot(contains(stored)));
      expect(logs.text, isNot(contains(code)));
    });

    test('смена секрета отменяет выданные коды', () async {
      final code = await inviteCodeFor(api, olga, family.id);
      final rotated = BudgetService(
        db: api.db,
        inviteCodeSecret: 'rotated-invite-secret-0123456789-abcdef',
      );

      await expectLater(
        rotated.join(userId: boris.id, code: code),
        throwsA(
          isA<BudgetFailure>().having(
            (e) => e.reason,
            'reason',
            BudgetFailureReason.inviteNotFound,
          ),
        ),
      );
      expect(await memberRow(api, family.id, boris.id), isNull);
    });
  });
}
