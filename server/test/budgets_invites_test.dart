import 'dart:math';

import 'package:server/budgets/budget_service.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/auth_support.dart';
import 'support/budget_support.dart';
import 'support/shared_budget_support.dart';
import 'support/test_support.dart';

final RegExp _codeFormat = RegExp(r'^MLN-[0-9A-HJKMNP-TV-Z]{4}$');

void main() {
  late LogCapture logs;
  late ShiftedClock clock;
  late AuthHarness api;
  late TestUser olga;
  late TestUser boris;
  late TestUser vera;
  late String familyId;

  setUp(() async {
    logs = LogCapture();
    clock = ShiftedClock();
    api = await AuthHarness.start(now: clock.now);
    olga = await registerTestUser(api, 'olga', displayName: 'Ольга');
    boris = await registerTestUser(api, 'boris', displayName: 'Борис');
    vera = await registerTestUser(api, 'vera', displayName: 'Вера');
    familyId = (await createSharedBudget(api, olga)).id;
    logs.clear();
  });

  Future<List<List<Object?>>> invites(String budgetId) async {
    final rows = await api.db.execute(
      r'SELECT code_hash, created_by, created_at, expires_at, revoked_at '
      r'FROM invites WHERE budget_id = $1::uuid '
      'ORDER BY revoked_at IS NULL, created_at',
      parameters: [budgetId],
    );
    return [for (final row in rows) row.toList()];
  }

  test(
    'создатель получает код MLN-XXXX на 24 часа; в базе только хеш кода',
    () async {
      final before = DateTime.now().toUtc();
      final response = await createInviteRaw(api, olga, familyId);
      final after = DateTime.now().toUtc();

      expect(response.status, 201, reason: response.text);
      expect(response.headers['cache-control'], 'no-store');
      expect(response.json.keys.toSet(), {'code', 'expiresAt'});
      final code = response.json['code']! as String;
      expect(code, matches(_codeFormat));
      final expiresAt = decodeInstant(response.json['expiresAt']! as String);
      expect(
        expiresAt.isBefore(
          before.add(inviteTtl).subtract(const Duration(seconds: 1)),
        ),
        isFalse,
      );
      expect(
        expiresAt.isAfter(after.add(inviteTtl).add(const Duration(seconds: 1))),
        isFalse,
      );

      final stored = await invites(familyId);
      expect(stored, hasLength(1));
      expect(
        stored.single[0],
        hashInviteCode(code, secret: testInviteCodeSecret),
      );
      expect(stored.single[0], matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(stored.single[1], olga.id);
      expect(stored.single[3], expiresAt);
      expect(stored.single[4], isNull);
      final suffix = code.substring(4);
      expect(
        await api.count(
          r'SELECT count(*)::int FROM invites i '
          r'WHERE position($1 in i::text) > 0 OR position($2 in i::text) > 0',
          [code, suffix],
        ),
        0,
      );
    },
  );

  test('новый код отменяет прежний: старый → 404 invite_not_found, '
      'новый пускает', () async {
    final first = await inviteCodeFor(api, olga, familyId);
    final second = await inviteCodeFor(api, olga, familyId);
    expect(second, isNot(first));

    final stored = await invites(familyId);
    expect(stored, hasLength(2));
    expect(stored[0][4], isNotNull, reason: 'first invite revoked');
    expect(stored[1][4], isNull, reason: 'second invite active');

    final old = await joinRaw(api, boris, first);
    expect(old.status, 404, reason: old.text);
    expect(old.errorCode, ApiErrorCode.inviteNotFound.code);
    expect(await memberRow(api, familyId, boris.id), isNull);

    expect((await joinRaw(api, boris, second)).status, 200);
    expect(
      logs.text,
      matches(
        RegExp(
          'INFO  \\[budgets\\] budget invite ok budgetId=$familyId '
          'userId=${olga.id} code=MLN-\\*\\*\\*\\* expiresAt=\\S+ '
          'previousRevoked=1 attempts=1 in \\d+ms rid=',
        ),
      ),
    );
    expect(
      logs.text,
      contains(
        'WARN  [budgets] budget join rejected reason=invite_not_found '
        'userId=${boris.id} code=MLN-**** budgetId=$familyId '
        'problem="invite revoked at ',
      ),
    );
  });

  test('код живёт 24 часа: за минуту до конца пускает, через 24 ч → '
      '404 invite_not_found', () async {
    final code = await inviteCodeFor(api, olga, familyId);

    clock.offset = inviteTtl - const Duration(minutes: 1);
    expect((await joinRaw(api, boris, code)).status, 200);

    clock.offset = inviteTtl + const Duration(seconds: 1);
    final expired = await joinRaw(api, vera, code);
    expect(expired.status, 404, reason: expired.text);
    expect(expired.errorCode, ApiErrorCode.inviteNotFound.code);
    expect(
      (expired.json['error']! as Map<String, Object?>)['message'],
      'Код не найден или истёк',
    );
    expect(await memberRow(api, familyId, vera.id), isNull);
    expect(
      logs.text,
      contains(
        'WARN  [budgets] budget join rejected reason=invite_not_found '
        'userId=${vera.id} code=MLN-**** budgetId=$familyId '
        'problem="invite expired at ',
      ),
    );

    final fresh = await inviteCodeFor(api, olga, familyId);
    expect((await joinRaw(api, vera, fresh)).status, 200);
  });

  test('приглашать может только создатель: участник → 403 forbidden, '
      'чужой → 404, личный бюджет → 403, ничего не записано', () async {
    await joinBudget(api, boris, await inviteCodeFor(api, olga, familyId));
    final personalId = await SharedBudgetFixture(api).personalBudgetOf(olga.id);
    final before = await invites(familyId);
    logs.clear();

    final member = await createInviteRaw(api, boris, familyId);
    expect(member.status, 403, reason: member.text);
    expect(member.errorCode, ApiErrorCode.forbidden.code);

    final stranger = await createInviteRaw(api, vera, familyId);
    expect(stranger.status, 404, reason: stranger.text);
    expect(stranger.errorCode, ApiErrorCode.notFound.code);

    final personal = await createInviteRaw(api, olga, personalId);
    expect(personal.status, 403, reason: personal.text);
    expect(personal.errorCode, ApiErrorCode.forbidden.code);

    expect(await invites(familyId), before);
    expect(await invites(personalId), isEmpty);
    expect(
      logs.text,
      contains(
        'WARN  [budgets] budget invite rejected by rights reason=forbidden '
        'budgetId=$familyId userId=${boris.id} '
        'problem="only the owner can do this, role=member"',
      ),
    );
    expect(
      logs.text,
      contains(
        'WARN  [budgets] budget invite rejected by rights reason=not_found '
        'budgetId=$familyId userId=${vera.id} problem="not an active member"',
      ),
    );
  });

  test('код приглашения не попадает в лог ни при выдаче, ни при входе, '
      'ни при неверном вводе — только MLN-****', () async {
    var code = await inviteCodeFor(api, olga, familyId);
    for (var i = 0; i < 50 && !_distinctive(code); i++) {
      code = await inviteCodeFor(api, olga, familyId);
    }
    expect(_distinctive(code), isTrue, reason: code);
    final suffix = code.substring(4);
    final typed = 'mln ${suffix.toLowerCase()}';
    await joinBudget(api, boris, typed);
    await joinRaw(api, vera, 'MLN-$suffix$suffix');
    await joinRaw(api, vera, 'XYZ-QQQU');

    expect(logs.text, contains('code=MLN-****'));
    expect(logs.text, isNot(contains(suffix)));
    expect(logs.text, isNot(contains(typed)));
    expect(logs.text, isNot(contains('QQQU')));
    expect(
      logs.text,
      isNot(contains(hashInviteCode(code, secret: testInviteCodeSecret))),
    );
  });

  test('код совпал с действующим приглашением другого бюджета — выдаётся '
      'другой; совпал с истёкшим — строка переиспользуется', () async {
    final dachaId = (await createSharedBudget(api, olga, name: 'Дача')).id;
    var now = DateTime.now().toUtc();
    BudgetService service() => BudgetService(
      db: api.db,
      inviteCodeSecret: testInviteCodeSecret,
      now: () => now,
      random: Random(42),
    );

    final family = await service().createInvite(
      userId: olga.id,
      budgetId: familyId,
    );
    logs.clear();
    final dacha = await service().createInvite(
      userId: olga.id,
      budgetId: dachaId,
    );
    expect(dacha.code, isNot(family.code));
    expect(dacha.code, matches(_codeFormat));
    expect(
      logs.text,
      contains(
        'DEBUG [budgets] invite code collides with an active invite, '
        'generating another budgetId=$dachaId userId=${olga.id} '
        'attempt=1/$inviteCodeAttempts',
      ),
    );
    expect(logs.text, contains('attempts=2'));

    expect((await joinBudget(api, boris, family.code)).id, familyId);
    expect((await joinBudget(api, vera, dacha.code)).id, dachaId);

    now = now.add(inviteTtl + const Duration(minutes: 1));
    clock.offset = inviteTtl + const Duration(minutes: 1);
    final reused = await service().createInvite(
      userId: olga.id,
      budgetId: dachaId,
    );
    expect(reused.code, family.code);
    expect(
      await api.count(
        r'SELECT count(*)::int FROM invites WHERE code_hash = $1 '
        r'AND budget_id = $2::uuid AND revoked_at IS NULL',
        [hashInviteCode(family.code, secret: testInviteCodeSecret), dachaId],
      ),
      1,
    );
    final joined = await joinRaw(
      api,
      await registerTestUser(api, 'dima', displayName: 'Дима'),
      family.code,
    );
    expect(joined.status, 200, reason: joined.text);
    expect(Budget.fromJson(joined.json['budget']).id, dachaId);
  });
}

bool _distinctive(String code) =>
    code
        .substring(4)
        .split('')
        .where((char) => 'GHJKMNPQRSTVWXYZ'.contains(char))
        .length >=
    2;
