import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/dart.dart';
import 'package:cryptography/helpers.dart';
import 'package:logging/logging.dart';
import 'package:shared/logging.dart';

final _log = Logger('auth');

const int argon2MaxConcurrent = 4;
const Duration argon2SlowQueueWait = Duration(seconds: 1);

typedef Argon2Derive = Future<List<int>> Function(
  DartArgon2State state,
  String secret,
  List<int> salt,
);

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
  PasswordHasher({
    this.params = Argon2Params.owasp,
    this.maxConcurrent = argon2MaxConcurrent,
    this.slowQueueWait = argon2SlowQueueWait,
    this._derive = deriveArgon2id,
    Random? random,
  }) : _random = random ?? Random.secure() {
    if (maxConcurrent < 1) {
      throw ArgumentError.value(
        maxConcurrent,
        'maxConcurrent',
        'at least one argon2id hash must be allowed at a time',
      );
    }
  }

  final Argon2Params params;
  final int maxConcurrent;
  final Duration slowQueueWait;
  final Argon2Derive _derive;
  final Random _random;
  final Queue<Completer<void>> _waiting = Queue();
  final List<DartArgon2State> _idleBuffers = [];
  int _running = 0;
  int _buffers = 0;
  Future<String>? _dummy;

  int get running => _running;

  int get queued => _waiting.length;

  int get buffers => _buffers;

  Future<String> hash(String secret, {required String purpose}) async {
    final sw = Stopwatch()..start();
    final salt = List<int>.generate(
      params.saltLength,
      (_) => _random.nextInt(256),
    );
    final derived = await _deriveInSlot(params, secret, salt, purpose);
    final encoded =
        '\$argon2id\$v=19\$${params.phc}\$${_encode(salt)}\$${_encode(derived.digest)}';
    _log.fine(
      'argon2id hash purpose=$purpose ${params.phc} '
      'in ${sw.elapsedMilliseconds}ms queueWait=${derived.waitedMs}ms',
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
    final derived = await _deriveInSlot(
      parsed.params,
      secret,
      parsed.salt,
      purpose,
    );
    final match = constantTimeBytesEquality.equals(derived.digest, parsed.hash);
    _log.fine(
      'argon2id verify purpose=$purpose ${parsed.params.phc} match=$match '
      'in ${sw.elapsedMilliseconds}ms queueWait=${derived.waitedMs}ms',
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

  Future<({List<int> digest, int waitedMs})> _deriveInSlot(
    Argon2Params params,
    String secret,
    List<int> salt,
    String purpose,
  ) async {
    final sw = Stopwatch()..start();
    if (_running < maxConcurrent) {
      _running++;
    } else {
      final turn = Completer<void>();
      _waiting.add(turn);
      _log.fine(
        'argon2id queued purpose=$purpose '
        'running=$_running/$maxConcurrent queued=${_waiting.length}',
      );
      await turn.future;
      if (sw.elapsed > slowQueueWait) {
        _log.warning(
          'argon2id slot waited ${sw.elapsedMilliseconds}ms purpose=$purpose '
          'running=$_running/$maxConcurrent queued=${_waiting.length} '
          '→ too many password checks at once, requests wait for a slot',
        );
      }
    }
    final waitedMs = sw.elapsedMilliseconds;
    try {
      final digest = params == this.params
          ? await _deriveReusing(secret, salt, purpose)
          : await _deriveOnce(params, secret, salt, purpose);
      return (digest: digest, waitedMs: waitedMs);
    } finally {
      _releaseSlot();
    }
  }

  Future<List<int>> _deriveReusing(
    String secret,
    List<int> salt,
    String purpose,
  ) async {
    final DartArgon2State state;
    if (_idleBuffers.isNotEmpty) {
      state = _idleBuffers.removeLast();
    } else {
      state = newArgon2State(params);
      _buffers++;
      _log.fine(
        'argon2id buffer added purpose=$purpose ${params.phc} '
        'buffers=$_buffers/$maxConcurrent (${params.memoryKib} KiB each, '
        'kept for the next hashes)',
      );
    }
    final List<int> digest;
    try {
      digest = await _derive(state, secret, salt);
    } catch (e) {
      _buffers--;
      if (!state.isBufferUsed) state.tryReleaseMemory();
      _log.warning(
        'argon2id failed purpose=$purpose ${params.phc}: ${describeError(e)} '
        '→ its buffer freed, buffers=$_buffers/$maxConcurrent',
      );
      rethrow;
    }
    _idleBuffers.add(state);
    return digest;
  }

  Future<List<int>> _deriveOnce(
    Argon2Params stored,
    String secret,
    List<int> salt,
    String purpose,
  ) async {
    _log.fine(
      'argon2id one-off buffer purpose=$purpose for stored ${stored.phc} '
      '(current ${params.phc}) → freed right after',
    );
    final state = newArgon2State(stored);
    try {
      return await _derive(state, secret, salt);
    } finally {
      if (!state.isBufferUsed) state.tryReleaseMemory();
    }
  }

  void _releaseSlot() {
    if (_waiting.isEmpty) {
      _running--;
      return;
    }
    _waiting.removeFirst().complete();
  }
}

DartArgon2State newArgon2State(Argon2Params params) => DartArgon2id(
  parallelism: params.parallelism,
  memory: params.memoryKib,
  iterations: params.iterations,
  hashLength: params.hashLength,
).newState();

Future<List<int>> deriveArgon2id(
  DartArgon2State state,
  String secret,
  List<int> salt,
) => state.deriveKeyBytes(password: utf8.encode(secret), nonce: salt);

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
