import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/auth_support.dart';
import 'support/limits_support.dart';
import 'support/test_support.dart';

void main() {
  late LogCapture logs;
  late LimitsHarness api;
  late String olgaToken;
  late String annaToken;
  late String annaId;
  late String borisToken;
  late String borisId;
  late String budgetId;
  late String code;
  late List<String> wrongCodes;

  Future<ApiResponse> authed(
    String method,
    String path,
    String token, {
    Object? body,
    Object? rawBody,
  }) => api.send(
    method,
    path,
    body: body,
    rawBody: rawBody,
    headers: {'authorization': 'Bearer $token'},
  );

  Future<ApiResponse> join(String token, Object? value) =>
      authed('POST', '/invites/join', token, body: {'code': value});

  Future<({String id, String token})> register(String login) async {
    final response = await api.register(login);
    expect(response.status, 201, reason: '$response');
    return (
      id: (response.json['user']! as Map<String, Object?>)['id']! as String,
      token: response.json['accessToken']! as String,
    );
  }

  setUp(() async {
    logs = LogCapture();
    api = await LimitsHarness.start();
    olgaToken = (await register('olga')).token;
    final anna = await register('anna');
    annaToken = anna.token;
    annaId = anna.id;
    final boris = await register('boris');
    borisToken = boris.token;
    borisId = boris.id;

    budgetId = newId();
    final created = await authed(
      'POST',
      '/budgets',
      olgaToken,
      body: {'id': budgetId, 'name': 'Семья', 'emoji': '🏠'},
    );
    expect(created.status, 201, reason: '$created');
    final invite = await authed(
      'POST',
      '/budgets/$budgetId/invites',
      olgaToken,
    );
    expect(invite.status, 201, reason: '$invite');
    code = invite.json['code']! as String;
    wrongCodes = [
      for (final body in [
        '0000',
        '0001',
        '0002',
        '0003',
        '0004',
        '0005',
        '0006',
        '0007',
        '0008',
        '0009',
        '000A',
        '000B',
      ])
        if ('MLN-$body' != code) 'MLN-$body',
    ].take(10).toList();
    logs.clear();
  });

  Future<void> failJoins(int times, String token, {int from = 0}) async {
    for (var i = 0; i < times; i++) {
      final response = await join(token, wrongCodes[from + i]);
      expect(response.status, 404, reason: 'attempt ${i + 1}: $response');
      expect(response.errorCode, 'invite_not_found');
    }
  }

  void expectBlocked(ApiResponse response, String retryAfter) {
    expect(response.status, 429, reason: '$response');
    expect(response.errorCode, 'too_many_attempts');
    expect(response.headers['retry-after'], retryAfter);
  }

  Future<int> memberships(String userId) => api.count(
    r'SELECT count(*)::int FROM budget_members WHERE budget_id = $1::uuid '
    r'AND user_id = $2::uuid AND left_at IS NULL',
    [budgetId, userId],
  );

  test('10 неверных кодов → 11-я попытка 429 с Retry-After даже с верным '
      'кодом; через 15 минут снова можно', () async {
    await failJoins(10, annaToken);

    final blocked = await join(annaToken, code);
    expectBlocked(blocked, '900');
    expect(
      (blocked.json['error']! as Map<String, Object?>)['message'],
      'Слишком много неудачных попыток. Попробуй через 15 мин',
    );
    expect(await memberships(annaId), 0);
    expect(
      logs.text,
      contains(
        'WARN  [limits] invite code attempts exhausted userId=$annaId '
        'failures=10/10 window=15m → next attempts blocked for 900s',
      ),
    );
    expect(
      logs.text,
      contains(
        'WARN  [limits] invite code attempts limit hit userId=$annaId '
        'failures=10/10 window=15m retryAfter=900s → 429, code not checked',
      ),
    );
    expect(logs.text, isNot(contains('budget join ok')));

    api.clock.advance(const Duration(minutes: 14, seconds: 59));
    expectBlocked(await join(annaToken, code), '1');
    expectBlocked(await join(annaToken, wrongCodes.first), '1');

    api.clock.advance(const Duration(seconds: 1));
    final joined = await join(annaToken, code);
    expect(joined.status, 200, reason: '$joined');
    expect(await memberships(annaId), 1);

    for (final value in [code, ...wrongCodes]) {
      expect(logs.text, isNot(contains(value)));
    }
    expect(logs.text, contains('MLN-****'));
  });

  test('блокировка на пользователя: другой пользователь с того же IP не '
      'затронут', () async {
    await failJoins(10, annaToken);
    expectBlocked(await join(annaToken, code), '900');

    final wrong = await join(borisToken, wrongCodes.first);
    expect(wrong.status, 404, reason: '$wrong');
    expect(wrong.errorCode, 'invite_not_found');
    final joined = await join(borisToken, code);
    expect(joined.status, 200, reason: '$joined');
    expect(await memberships(borisId), 1);
    expect(logs.text, isNot(contains('userId=$borisId failures=10')));
  });

  test('успешный вход неудачи не сбрасывает', () async {
    await failJoins(5, annaToken);
    final joined = await join(annaToken, code);
    expect(joined.status, 200, reason: '$joined');
    expect(await memberships(annaId), 1);

    final again = await join(annaToken, code);
    expect(again.status, 200, reason: 'already member: $again');

    await failJoins(5, annaToken, from: 5);
    expectBlocked(await join(annaToken, code), '900');
  });

  test('неверный формат кода тоже неудача; 400 и 401 не считаются', () async {
    for (var i = 0; i < 6; i++) {
      final noCode = await authed(
        'POST',
        '/invites/join',
        annaToken,
        body: {'code': 42},
      );
      expect(noCode.status, 400, reason: '$noCode');
      final notJson = await authed(
        'POST',
        '/invites/join',
        annaToken,
        rawBody: 'code',
      );
      expect(notJson.status, 400, reason: '$notJson');
      final noToken = await api.post(
        '/invites/join',
        body: {'code': code},
        ip: '198.51.100.7',
      );
      expect(noToken.status, 401, reason: '$noToken');
    }

    final short = await join(annaToken, 'MLN-12');
    expect(short.status, 404, reason: '$short');
    expect(short.errorCode, 'invite_not_found');
    await failJoins(9, annaToken);
    expectBlocked(await join(annaToken, code), '900');
  });
}
