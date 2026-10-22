import 'dart:convert';
import 'dart:math';

import 'package:cryptography/dart.dart' show DartSha256;
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

const Duration accessTokenTtl = Duration(minutes: 15);
const Duration refreshTokenTtl = Duration(days: 90);
const int refreshTokenBytes = 32;

class AccessClaims {
  const AccessClaims({
    required this.userId,
    required this.sessionId,
    required this.expiresAt,
  });

  final String userId;
  final String sessionId;
  final DateTime expiresAt;
}

enum AccessTokenRejection {
  malformed('malformed'),
  badSignature('bad_signature'),
  wrongAlgorithm('wrong_algorithm'),
  expired('expired'),
  missingClaims('missing_claims');

  const AccessTokenRejection(this.reason);

  final String reason;
}

class AccessTokenCheck {
  const AccessTokenCheck._(this.claims, this.rejection);

  final AccessClaims? claims;
  final AccessTokenRejection? rejection;
}

class AccessTokens {
  AccessTokens(
    String secret, {
    this.ttl = accessTokenTtl,
    DateTime Function()? now,
  }) : _key = SecretKey(secret),
       _now = now ?? DateTime.now;

  final SecretKey _key;
  final Duration ttl;
  final DateTime Function() _now;

  String issue({required String userId, required String sessionId}) {
    final issuedAt = _now().toUtc();
    final expiresAt = issuedAt.add(ttl);
    return JWT({
      'sub': userId,
      'sid': sessionId,
      'iat': _seconds(issuedAt),
      'exp': _seconds(expiresAt),
    }).sign(_key, algorithm: JWTAlgorithm.HS256, noIssueAt: true);
  }

  AccessTokenCheck verify(String token) {
    final JWT jwt;
    try {
      jwt = JWT.verify(token, _key);
    } on JWTExpiredException {
      return const AccessTokenCheck._(null, AccessTokenRejection.expired);
    } on JWTException catch (e) {
      final rejection = e.message == 'invalid signature'
          ? AccessTokenRejection.badSignature
          : AccessTokenRejection.malformed;
      return AccessTokenCheck._(null, rejection);
    } on Object {
      return const AccessTokenCheck._(null, AccessTokenRejection.malformed);
    }
    if (jwt.header?['alg'] != JWTAlgorithm.HS256.name) {
      return const AccessTokenCheck._(
        null,
        AccessTokenRejection.wrongAlgorithm,
      );
    }
    final payload = jwt.payload;
    if (payload is! Map) {
      return const AccessTokenCheck._(null, AccessTokenRejection.missingClaims);
    }
    final sub = payload['sub'];
    final sid = payload['sid'];
    final exp = payload['exp'];
    if (sub is! String || sid is! String || exp is! int) {
      return const AccessTokenCheck._(null, AccessTokenRejection.missingClaims);
    }
    return AccessTokenCheck._(
      AccessClaims(
        userId: sub,
        sessionId: sid,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true),
      ),
      null,
    );
  }
}

int _seconds(DateTime time) => time.millisecondsSinceEpoch ~/ 1000;

String newRefreshToken([Random? random]) {
  final source = random ?? Random.secure();
  final bytes = List<int>.generate(
    refreshTokenBytes,
    (_) => source.nextInt(256),
  );
  return base64Url.encode(bytes).replaceAll('=', '');
}

String hashRefreshToken(String token) {
  final digest = const DartSha256().hashSync(utf8.encode(token)).bytes;
  final buffer = StringBuffer();
  for (final byte in digest) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}
