import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:server/auth/auth_middleware.dart';
import 'package:server/auth/tokens.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'support/auth_support.dart';
import 'support/test_support.dart';

void main() {
  late LogCapture logs;
  late AuthHarness api;
  late Handler probe;
  late String userId;
  late String sessionId;
  late String accessToken;
  AuthContext? seen;

  setUp(() async {
    logs = LogCapture();
    api = await AuthHarness.start();
    seen = null;
    probe = const Pipeline().addMiddleware(authMiddleware(api.auth)).addHandler(
      (request) {
        seen = authContextOf(request);
        return Response.ok('ok');
      },
    );
    final registered = await api.register();
    userId =
        (registered.json['user']! as Map<String, Object?>)['id']! as String;
    accessToken = registered.json['accessToken']! as String;
    sessionId = api.auth.accessTokens.verify(accessToken).claims!.sessionId;
    logs.clear();
  });

  Future<Response> call({String? authorization}) async => probe(
    Request(
      'GET',
      Uri.parse('http://localhost/api/v1/probe?token=QUERYSECRET'),
      headers: {'authorization': ?authorization},
    ),
  );

  Future<void> expectUnauthorized(Response response, String reason) async {
    expect(response.statusCode, 401);
    expect(response.headers['www-authenticate'], 'Bearer');
    expect(jsonDecode(await response.readAsString()), {
      'error': {'code': 'unauthorized', 'message': 'Нужно войти в аккаунт'},
    });
    expect(seen, isNull);
    expect(
      logs.text,
      contains(
        RegExp(
          'INFO  \\[auth\\] unauthorized GET /api/v1/probe reason=$reason',
        ),
      ),
    );
    expect(logs.text, isNot(contains('QUERYSECRET')));
  }

  test('Bearer с действующим access → userId и sessionId в контексте запроса', () async {
    final response = await call(authorization: 'Bearer $accessToken');
    expect(response.statusCode, 200);
    expect(seen!.userId, userId);
    expect(seen!.sessionId, sessionId);
    expect(
      logs.text,
      contains(
        RegExp(
          'DEBUG \\[auth\\] authorized GET /api/v1/probe userId=$userId sessionId=$sessionId in \\d+ms',
        ),
      ),
    );
  });

  test('схема bearer без учёта регистра', () async {
    final response = await call(authorization: 'bearer $accessToken');
    expect(response.statusCode, 200);
  });

  test('нет заголовка → 401 unauthorized', () async {
    await expectUnauthorized(await call(), 'missing_token');
  });

  test('не Bearer → 401 unauthorized', () async {
    await expectUnauthorized(
      await call(authorization: 'Basic YW5uYTpwYXNz'),
      'malformed_header',
    );
    logs.clear();
    await expectUnauthorized(
      await call(authorization: 'Bearer'),
      'malformed_header',
    );
  });

  test('просроченный access → 401 unauthorized', () async {
    final stale = AccessTokens(
      testJwtSecret,
      now: () =>
          DateTime.now().subtract(accessTokenTtl + const Duration(seconds: 5)),
    ).issue(userId: userId, sessionId: sessionId);
    await expectUnauthorized(
      await call(authorization: 'Bearer $stale'),
      'expired',
    );
  });

  test('access живёт 15 минут: за минуту до конца ещё действует', () async {
    final almost = AccessTokens(
      testJwtSecret,
      now: () =>
          DateTime.now().subtract(accessTokenTtl - const Duration(minutes: 1)),
    ).issue(userId: userId, sessionId: sessionId);
    expect((await call(authorization: 'Bearer $almost')).statusCode, 200);
  });

  test('подпись другим секретом → 401 unauthorized', () async {
    final forged = AccessTokens('another-secret-0123456789-abcdefghijk')
        .issue(userId: userId, sessionId: sessionId);
    await expectUnauthorized(
      await call(authorization: 'Bearer $forged'),
      'bad_signature',
    );
  });

  test('подменённая полезная нагрузка → 401 unauthorized', () async {
    final parts = accessToken.split('.');
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    ) as Map<String, Object?>;
    payload['sub'] = '00000000-0000-4000-8000-000000000000';
    final tampered =
        '${parts[0]}.${base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '')}.${parts[2]}';
    await expectUnauthorized(
      await call(authorization: 'Bearer $tampered'),
      'bad_signature',
    );
  });

  test('мусор вместо токена → 401 unauthorized', () async {
    await expectUnauthorized(
      await call(authorization: 'Bearer not-a-jwt'),
      'malformed',
    );
  });

  test(
    'другой алгоритм с тем же секретом (HS512) → 401 unauthorized',
    () async {
      final hs512 = JWT({
        'sub': userId,
        'sid': sessionId,
        'exp':
            DateTime.now()
                .add(const Duration(minutes: 5))
                .millisecondsSinceEpoch ~/
            1000,
      }).sign(SecretKey(testJwtSecret), algorithm: JWTAlgorithm.HS512);
      await expectUnauthorized(
        await call(authorization: 'Bearer $hs512'),
        'wrong_algorithm',
      );
    },
  );

  test('без sid или exp → 401 unauthorized', () async {
    final noSid = JWT({
      'sub': userId,
      'exp':
          DateTime.now()
              .add(const Duration(minutes: 5))
              .millisecondsSinceEpoch ~/
          1000,
    }).sign(SecretKey(testJwtSecret));
    await expectUnauthorized(
      await call(authorization: 'Bearer $noSid'),
      'missing_claims',
    );
    logs.clear();
    final noExp = JWT({'sub': userId, 'sid': sessionId})
        .sign(SecretKey(testJwtSecret));
    await expectUnauthorized(
      await call(authorization: 'Bearer $noExp'),
      'missing_claims',
    );
  });

  test('сессия отозвана → access этой сессии больше не пускает', () async {
    await api.db.execute(
      r'UPDATE sessions SET revoked_at = now() WHERE id = $1::uuid',
      parameters: [sessionId],
    );
    await expectUnauthorized(
      await call(authorization: 'Bearer $accessToken'),
      'session_revoked',
    );
    expect(logs.text, contains('userId=$userId sessionId=$sessionId'));
  });

  test('сессия истекла или аккаунт удалён → 401', () async {
    await api.db.execute(
      r"UPDATE sessions SET expires_at = now() - interval '1 second' WHERE id = $1::uuid",
      parameters: [sessionId],
    );
    await expectUnauthorized(
      await call(authorization: 'Bearer $accessToken'),
      'session_expired',
    );

    await api.db.execute(
      r"UPDATE sessions SET expires_at = now() + interval '1 day' WHERE id = $1::uuid",
      parameters: [sessionId],
    );
    await api.db.execute(
      r'UPDATE users SET deleted_at = now() WHERE id = $1::uuid',
      parameters: [userId],
    );
    logs.clear();
    await expectUnauthorized(
      await call(authorization: 'Bearer $accessToken'),
      'user_deleted',
    );
  });

  test('сессии нет в базе → 401', () async {
    final orphan = api.auth.accessTokens.issue(
      userId: userId,
      sessionId: '00000000-0000-4000-8000-000000000000',
    );
    await expectUnauthorized(
      await call(authorization: 'Bearer $orphan'),
      'session_not_found',
    );
  });

  test('маршрут без middleware: authContextOf падает понятной ошибкой', () {
    expect(
      () => authContextOf(Request('GET', Uri.parse('http://localhost/x'))),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('not behind authMiddleware'),
        ),
      ),
    );
  });
}
