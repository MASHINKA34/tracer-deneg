import 'dart:convert';
import 'dart:math';

import 'package:server/auth/tokens.dart';
import 'package:test/test.dart';

const _secret = 'unit-test-secret-0123456789-abcdefghij';
const _userId = '11111111-1111-4111-8111-111111111111';
const _sessionId = '22222222-2222-4222-8222-222222222222';

Map<String, Object?> _part(String token, int index) => jsonDecode(
  utf8.decode(base64Url.decode(base64Url.normalize(token.split('.')[index]))),
) as Map<String, Object?>;

void main() {
  group('access JWT', () {
    test('HS256, sub = userId, sid = sessionId, срок 15 минут', () {
      final issuedAt = DateTime.utc(2026, 10, 23, 12, 0, 0);
      final token = AccessTokens(
        _secret,
        now: () => issuedAt,
      ).issue(userId: _userId, sessionId: _sessionId);

      expect(_part(token, 0), {'alg': 'HS256', 'typ': 'JWT'});
      expect(_part(token, 1), {
        'sub': _userId,
        'sid': _sessionId,
        'iat': issuedAt.millisecondsSinceEpoch ~/ 1000,
        'exp':
            issuedAt.add(const Duration(minutes: 15)).millisecondsSinceEpoch ~/
            1000,
      });
      expect(accessTokenTtl, const Duration(minutes: 15));
    });

    test('свой токен проходит проверку и отдаёт userId и sessionId', () {
      final tokens = AccessTokens(_secret);
      final check = tokens.verify(
        tokens.issue(userId: _userId, sessionId: _sessionId),
      );
      expect(check.rejection, isNull);
      expect(check.claims!.userId, _userId);
      expect(check.claims!.sessionId, _sessionId);
      expect(
        check.claims!.expiresAt.difference(DateTime.now()).inSeconds,
        inInclusiveRange(14 * 60, 15 * 60),
      );
    });

    test(
      'просроченный → expired, чужой секрет → bad_signature, мусор → malformed',
      () {
        final tokens = AccessTokens(_secret);
        final stale = AccessTokens(
          _secret,
          now: () => DateTime.now().subtract(const Duration(minutes: 16)),
        ).issue(userId: _userId, sessionId: _sessionId);
        final foreign = AccessTokens('other-secret-0123456789-abcdefghijk')
            .issue(userId: _userId, sessionId: _sessionId);

        expect(tokens.verify(stale).rejection, AccessTokenRejection.expired);
        expect(
          tokens.verify(foreign).rejection,
          AccessTokenRejection.badSignature,
        );
        expect(tokens.verify('abc').rejection, AccessTokenRejection.malformed);
        expect(
          tokens.verify('a.b.c').rejection,
          AccessTokenRejection.malformed,
        );
        expect(tokens.verify('').rejection, AccessTokenRejection.malformed);
      },
    );

    test('alg=none не принимается', () {
      final header = base64Url
          .encode(utf8.encode('{"alg":"none","typ":"JWT"}'))
          .replaceAll('=', '');
      final payload = base64Url
          .encode(
            utf8.encode(
              jsonEncode({
                'sub': _userId,
                'sid': _sessionId,
                'exp': 4102444800,
              }),
            ),
          )
          .replaceAll('=', '');
      final check = AccessTokens(_secret).verify('$header.$payload.');
      expect(check.claims, isNull);
    });
  });

  group('refresh', () {
    test('256 случайных бит: 43 символа base64url без =, каждый раз новый', () {
      final tokens = {for (var i = 0; i < 200; i++) newRefreshToken()};
      expect(tokens, hasLength(200));
      for (final token in tokens) {
        expect(token, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
        expect(base64Url.decode(base64Url.normalize(token)), hasLength(32));
      }
      expect(refreshTokenBytes * 8, 256);
      expect(refreshTokenTtl, const Duration(days: 90));
    });

    test(
      'случайность из переданного генератора (на сервере Random.secure)',
      () {
        expect(newRefreshToken(Random(1)), newRefreshToken(Random(1)));
        expect(newRefreshToken(Random(1)), isNot(newRefreshToken(Random(2))));
      },
    );

    test('на сервере хранится SHA-256 в hex', () {
      expect(
        hashRefreshToken('abc'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
      final token = newRefreshToken();
      expect(hashRefreshToken(token), matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(hashRefreshToken(token), isNot(contains(token)));
    });
  });
}
