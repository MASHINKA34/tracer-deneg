import 'package:server/auth/tokens.dart';
import 'package:test/test.dart';

import 'support/auth_support.dart';
import 'support/test_support.dart';

void main() {
  late LogCapture logs;
  late AuthHarness api;
  late String userId;
  late String sessionId;
  late String firstRefresh;

  setUp(() async {
    logs = LogCapture();
    api = await AuthHarness.start();
    final registered = await api.register();
    userId =
        (registered.json['user']! as Map<String, Object?>)['id']! as String;
    firstRefresh = registered.json['refreshToken']! as String;
    sessionId = api.auth.accessTokens
        .verify(registered.json['accessToken']! as String)
        .claims!
        .sessionId;
    logs.clear();
  });

  Future<ApiResponse> refresh(String token) =>
      api.post('/auth/refresh', body: {'refreshToken': token});

  Future<List<Object?>> session() async {
    final rows = await api.db.execute(
      r'SELECT refresh_hash, revoked_at IS NOT NULL FROM sessions WHERE id = $1::uuid',
      parameters: [sessionId],
    );
    return rows.single.toList();
  }

  group('POST /auth/refresh', () {
    test('ротация: новая пара, хеш в сессии заменён, срок продлён на 90 дней', () async {
      await api.db.execute(
        r"UPDATE sessions SET expires_at = now() + interval '1 day', "
        r"last_used_at = now() - interval '1 day' WHERE id = $1::uuid",
        parameters: [sessionId],
      );

      final response = await refresh(firstRefresh);

      expect(response.status, 200);
      expect(response.headers['cache-control'], 'no-store');
      final body = response.json;
      expect(body.keys, unorderedEquals(['accessToken', 'refreshToken']));
      final next = body['refreshToken']! as String;
      expect(next, isNot(firstRefresh));
      expect(next, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
      final claims = api.auth.accessTokens
          .verify(body['accessToken']! as String)
          .claims!;
      expect(claims.userId, userId);
      expect(claims.sessionId, sessionId);

      final rows = await api.db.execute(
        r'SELECT refresh_hash, revoked_at, '
        r"expires_at > now() + interval '89 days', "
        r"last_used_at > now() - interval '1 minute' "
        r'FROM sessions WHERE id = $1::uuid',
        parameters: [sessionId],
      );
      expect(rows.single.toList(), [hashRefreshToken(next), null, true, true]);
      final used = await api.db.execute(
        'SELECT refresh_hash, session_id FROM used_refresh_tokens',
      );
      expect(used.map((r) => r.toList()), [
        [hashRefreshToken(firstRefresh), sessionId],
      ]);
      expect(
        logs.text,
        contains(
          RegExp(
            'INFO  \\[auth\\] refresh ok userId=$userId sessionId=$sessionId in \\d+ms',
          ),
        ),
      );
    });

    test('цепочка: каждый новый refresh работает один раз', () async {
      var token = firstRefresh;
      for (var i = 0; i < 3; i++) {
        final response = await refresh(token);
        expect(response.status, 200, reason: 'step $i');
        token = response.json['refreshToken']! as String;
      }
      expect(
        await api.count('SELECT count(*)::int FROM used_refresh_tokens'),
        3,
      );
      expect((await session())[0], hashRefreshToken(token));
    });

    test('повтор старого refresh → 401, сессия отозвана, новый refresh тоже не работает', () async {
      final rotated = await refresh(firstRefresh);
      final current = rotated.json['refreshToken']! as String;

      final replay = await refresh(firstRefresh);
      expect(replay.status, 401);
      expect(replay.json, {
        'error': {
          'code': 'session_expired',
          'message': 'Сессия закончилась, войди снова',
        },
      });
      expect((await session())[1], isTrue);
      expect(
        logs.text,
        contains(
          RegExp(
            'WARN  \\[auth\\] refresh rejected reason=token_reused userId=$userId '
            'sessionId=$sessionId → session revoked in \\d+ms',
          ),
        ),
      );

      final afterReuse = await refresh(current);
      expect(afterReuse.status, 401);
      expect(afterReuse.errorCode, 'session_expired');
      expect(
        logs.text,
        contains(
          'refresh rejected reason=session_revoked userId=$userId sessionId=$sessionId',
        ),
      );
    });

    test('повтор refresh, который старше на несколько ротаций, тоже отзывает сессию', () async {
      var token = firstRefresh;
      for (var i = 0; i < 3; i++) {
        token = (await refresh(token)).json['refreshToken']! as String;
      }
      final replay = await refresh(firstRefresh);
      expect(replay.status, 401);
      expect((await session())[1], isTrue);
      expect((await refresh(token)).status, 401);
    });

    test('другие сессии пользователя при повторе не трогаются', () async {
      final other = await api.login(deviceName: 'Tablet');
      final otherRefresh = other.json['refreshToken']! as String;
      await refresh(firstRefresh);
      await refresh(firstRefresh);
      final response = await refresh(otherRefresh);
      expect(response.status, 200);
    });

    test('истёкшая сессия → 401 session_expired', () async {
      await api.db.execute(
        r"UPDATE sessions SET expires_at = now() - interval '1 second' WHERE id = $1::uuid",
        parameters: [sessionId],
      );
      final response = await refresh(firstRefresh);
      expect(response.status, 401);
      expect(response.errorCode, 'session_expired');
      expect(
        logs.text,
        contains(
          'INFO  [auth] refresh rejected reason=session_expired userId=$userId sessionId=$sessionId',
        ),
      );
      expect(
        await api.count('SELECT count(*)::int FROM used_refresh_tokens'),
        0,
      );
    });

    test(
      'незнакомый токен → 401 session_expired, ничего не отозвано',
      () async {
        final response = await refresh(newRefreshToken());
        expect(response.status, 401);
        expect(response.errorCode, 'session_expired');
        expect((await session())[1], isFalse);
        expect(
          logs.text,
          contains(
            RegExp(
              r'INFO  \[auth\] refresh rejected reason=unknown_token in \d+ms',
            ),
          ),
        );
      },
    );

    test('удалённый аккаунт → 401', () async {
      await api.db.execute(
        r'UPDATE users SET deleted_at = now() WHERE id = $1::uuid',
        parameters: [userId],
      );
      final response = await refresh(firstRefresh);
      expect(response.status, 401);
      expect(logs.text, contains('refresh rejected reason=user_deleted'));
    });

    test('нет refreshToken в теле → 400 bad_request', () async {
      final empty = await api.post('/auth/refresh', body: {'refreshToken': ''});
      expect(empty.status, 400);
      expect(empty.errorCode, 'bad_request');
      final missing = await api.post(
        '/auth/refresh',
        body: <String, Object?>{},
      );
      expect(missing.status, 400);
      expect(missing.errorCode, 'bad_request');
    });
  });
}
