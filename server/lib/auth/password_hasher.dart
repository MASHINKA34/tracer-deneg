import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:cryptography/helpers.dart';
import 'package:logging/logging.dart';

final _log = Logger('auth');

class Argon2Params {
  const Argon2Params({
    required this.memoryKib,
    required this.iterations,
    required this.parallelism,
    this.hashLength = 32,
    this.saltLength = 16,
  });

  static const owasp = Argon2Params(
    memoryKib: 19456,
    iterations: 2,
    parallelism: 1,
  );

  final int memoryKib;
  final int iterations;
  final int parallelism;
  final int hashLength;
  final int saltLength;

  String get phc => 'm=$memoryKib,t=$iterations,p=$parallelism';

  @override
  bool operator ==(Object other) =>
      other is Argon2Params &&
      other.memoryKib == memoryKib &&
      other.iterations == iterations &&
      other.parallelism == parallelism &&
      other.hashLength == hashLength;

  @override
  int get hashCode =>
      Object.hash(memoryKib, iterations, parallelism, hashLength);

  @override
  String toString() => 'Argon2Params($phc len=$hashLength)';
}

class PasswordHasher {
  PasswordHasher({this.params = Argon2Params.owasp, Random? random})
    : _random = random ?? Random.secure();

  final Argon2Params params;
  final Random _random;
  Future<String>? _dummy;

  Future<String> hash(String secret, {required String purpose}) async {
    final sw = Stopwatch()..start();
    final salt = List<int>.generate(
      params.saltLength,
      (_) => _random.nextInt(256),
    );
    final digest = await _derive(params, secret, salt);
    final encoded =
        '\$argon2id\$v=19\$${params.phc}\$${_encode(salt)}\$${_encode(digest)}';
    _log.fine(
      'argon2id hash purpose=$purpose ${params.phc} '
      'in ${sw.elapsedMilliseconds}ms',
    );
    return encoded;
  }

  Future<bool> verify(
    String secret,
    String encoded, {
    required String purpose,
  }) async {
    final sw = Stopwatch()..start();
    final parsed = _PhcHash.tryParse(encoded);
    if (parsed == null) {
      _log.warning(
        'argon2id verify purpose=$purpose: stored hash is not a valid '
        'argon2id string (length=${encoded.length}) → treated as mismatch',
      );
      return false;
    }
    final digest = await _derive(parsed.params, secret, parsed.salt);
    final match = constantTimeBytesEquality.equals(digest, parsed.hash);
    _log.fine(
      'argon2id verify purpose=$purpose ${parsed.params.phc} match=$match '
      'in ${sw.elapsedMilliseconds}ms',
    );
    return match;
  }

  Future<void> verifyDummy(String secret, {required String purpose}) async {
    await verify(secret, await _dummyHash(), purpose: purpose);
  }

  Future<Duration> warmUp() async {
    final sw = Stopwatch()..start();
    await _dummyHash();
    return sw.elapsed;
  }

  Future<String> _dummyHash() => _dummy ??= hash(
    _encode(List<int>.generate(24, (_) => _random.nextInt(256))),
    purpose: 'dummy',
  );
}

Future<List<int>> _derive(
  Argon2Params params,
  String secret,
  List<int> salt,
) async {
  final algorithm = DartArgon2id(
    parallelism: params.parallelism,
    memory: params.memoryKib,
    iterations: params.iterations,
    hashLength: params.hashLength,
  );
  final key = await algorithm.deriveKey(
    secretKey: SecretKey(utf8.encode(secret)),
    nonce: salt,
  );
  return key.extractBytes();
}

String _encode(List<int> bytes) => base64.encode(bytes).replaceAll('=', '');

List<int>? _decode(String text) {
  final padded = text.padRight((text.length + 3) ~/ 4 * 4, '=');
  try {
    return base64.decode(padded);
  } on FormatException {
    return null;
  }
}

final RegExp _phcPattern = RegExp(
  r'^\$argon2id\$v=19\$m=(\d{1,7}),t=(\d{1,3}),p=(\d{1,2})\$([A-Za-z0-9+/]+)\$([A-Za-z0-9+/]+)$',
);

class _PhcHash {
  _PhcHash(this.params, this.salt, this.hash);

  final Argon2Params params;
  final List<int> salt;
  final List<int> hash;

  static _PhcHash? tryParse(String encoded) {
    final match = _phcPattern.firstMatch(encoded);
    if (match == null) return null;
    final memory = int.parse(match[1]!);
    final iterations = int.parse(match[2]!);
    final parallelism = int.parse(match[3]!);
    final salt = _decode(match[4]!);
    final hash = _decode(match[5]!);
    if (salt == null || hash == null) return null;
    if (iterations < 1 || parallelism < 1) return null;
    if (memory < 8 * parallelism || memory > 1048576) return null;
    if (hash.length < 4 || salt.length < 8) return null;
    return _PhcHash(
      Argon2Params(
        memoryKib: memory,
        iterations: iterations,
        parallelism: parallelism,
        hashLength: hash.length,
        saltLength: salt.length,
      ),
      salt,
      hash,
    );
  }
}
