import 'dart:async';
import 'dart:math';

import 'package:server/auth/password_hasher.dart';
import 'package:test/test.dart';

import 'support/test_support.dart';

const _password = 'Пароль-Тайный-Длинный-77';

void main() {
  late LogCapture logs;
  setUp(() => logs = LogCapture());

  test(
    'по умолчанию параметры OWASP Password Storage: m=19456 KiB, t=2, p=1',
    () {
      expect(Argon2Params.owasp.memoryKib, 19456);
      expect(Argon2Params.owasp.iterations, 2);
      expect(Argon2Params.owasp.parallelism, 1);
      expect(PasswordHasher().params, Argon2Params.owasp);
    },
  );

  test(
    'хеш в формате PHC argon2id, соль своя у каждого хеша, пароль проверяется',
    () async {
      final hasher = PasswordHasher();
      final first = await hasher.hash(_password, purpose: 'password');
      final second = await hasher.hash(_password, purpose: 'password');

      final phc = RegExp(
        r'^\$argon2id\$v=19\$m=19456,t=2,p=1\$([A-Za-z0-9+/]{22})\$([A-Za-z0-9+/]{43})$',
      );
      expect(first, matches(phc));
      expect(second, matches(phc));
      expect(first, isNot(second));
      expect(phc.firstMatch(first)![1], isNot(phc.firstMatch(second)![1]));

      expect(
        await hasher.verify(_password, first, purpose: 'password'),
        isTrue,
      );
      expect(
        await hasher.verify(_password, second, purpose: 'password'),
        isTrue,
      );
      expect(
        await hasher.verify('$_password ', first, purpose: 'password'),
        isFalse,
      );
      expect(await hasher.verify('', first, purpose: 'password'), isFalse);
    },
  );

  test('совместим с эталонной реализацией argon2 (PHC-строка из её тестов)', () async {
    const reference =
        r'$argon2id$v=19$m=65536,t=2,p=1$c29tZXNhbHQ$CTFhFdXPJO1aFaMaO6Mm5c8y7cJHAph8ArZWb2GRPPc';
    final hasher = PasswordHasher();
    expect(await hasher.verify('password', reference, purpose: 'test'), isTrue);
    expect(
      await hasher.verify('passwore', reference, purpose: 'test'),
      isFalse,
    );
  });

  test('испорченная строка хеша → не совпадает, предупреждение без самого хеша', () async {
    final hasher = PasswordHasher();
    const broken = r'$argon2id$v=19$m=19456,t=2,p=1$BROKEN-SALT-VALUE$';
    expect(
      await hasher.verify(_password, broken, purpose: 'password'),
      isFalse,
    );
    expect(
      await hasher.verify(
        _password,
        r'$2b$10$abcdefghijklmnopqrstuv',
        purpose: 'password',
      ),
      isFalse,
    );
    expect(
      await hasher.verify(
        _password,
        r'$argon2id$v=19$m=99999999,t=2,p=1$c29tZXNhbHQ$CTFhFdXPJO1aFaMaO6Mm5c8y7cJHAph8ArZWb2GRPPc',
        purpose: 'password',
      ),
      isFalse,
    );
    expect(
      logs.text,
      contains(
        'WARN  [auth] argon2id verify purpose=password: stored hash is not a valid argon2id string (length=${broken.length}) → treated as mismatch',
      ),
    );
    expect(logs.text, isNot(contains('BROKEN-SALT-VALUE')));
  });

  test('проверка для несуществующего логина делает ту же работу argon2id с теми же параметрами', () async {
    final hasher = PasswordHasher();
    await hasher.verifyDummy('wrong-1', purpose: 'password');
    await hasher.verifyDummy('wrong-2', purpose: 'password');

    expect(
      RegExp(r'argon2id hash purpose=dummy m=19456,t=2,p=1')
          .allMatches(logs.text),
      hasLength(1),
    );
    expect(
      RegExp(
        r'DEBUG \[auth\] argon2id verify purpose=password m=19456,t=2,p=1 match=false in \d+ms',
      ).allMatches(logs.text),
      hasLength(2),
    );
  });

  test('прогрев при старте: фиктивный хеш готов заранее, первый вход с чужим логином не дольше обычного', () async {
    final hasher = PasswordHasher();
    final took = await hasher.warmUp();
    expect(took, greaterThan(Duration.zero));
    expect(logs.text, contains('argon2id hash purpose=dummy m=19456,t=2,p=1'));
    logs.clear();

    await hasher.verifyDummy('wrong-1', purpose: 'password');

    expect(logs.text, isNot(contains('purpose=dummy')));
    expect(
      logs.text,
      contains('argon2id verify purpose=password m=19456,t=2,p=1 match=false'),
    );
  });

  test(
    'на debug — время каждого хеширования и проверки, без пароля и хеша',
    () async {
      final hasher = PasswordHasher();
      final stored = await hasher.hash(_password, purpose: 'password');
      await hasher.verify(_password, stored, purpose: 'password');

      expect(
        logs.text,
        contains(
          RegExp(
            r'DEBUG \[auth\] argon2id hash purpose=password m=19456,t=2,p=1 in \d+ms',
          ),
        ),
      );
      expect(
        logs.text,
        contains(
          RegExp(
            r'DEBUG \[auth\] argon2id verify purpose=password m=19456,t=2,p=1 match=true in \d+ms',
          ),
        ),
      );
      expect(logs.text, isNot(contains(_password)));
      expect(logs.text, isNot(contains(stored.split(r'$').last)));
      expect(logs.text, isNot(contains(r'$argon2id$')));
    },
  );

  group('не больше 4 хешей одновременно', () {
    Future<void> pump() async {
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('по умолчанию 4 места', () {
      expect(argon2MaxConcurrent, 4);
      expect(PasswordHasher().maxConcurrent, 4);
    });

    test('10 входов сразу: настоящий argon2id считается не больше 4 раз '
        'одновременно, все хеши верные', () async {
      var active = 0;
      var peak = 0;
      final hasher = PasswordHasher(
        derive: (params, secret, salt) async {
          active++;
          peak = max(peak, active);
          try {
            return await deriveArgon2id(params, secret, salt);
          } finally {
            active--;
          }
        },
      );

      final hashes = await Future.wait([
        for (var i = 0; i < 10; i++)
          hasher.hash('$_password-$i', purpose: 'password'),
      ]);

      expect(peak, 4);
      expect(hasher.running, 0);
      expect(hasher.queued, 0);
      peak = 0;
      final matches = await Future.wait([
        for (var i = 0; i < 10; i++)
          hasher.verify('$_password-$i', hashes[i], purpose: 'password'),
        hasher.verifyDummy('wrong-1', purpose: 'password'),
        hasher.verifyDummy('wrong-2', purpose: 'password'),
      ]);
      expect(matches.sublist(0, 10), everyElement(isTrue));
      expect(peak, 4);
    });

    test('очередь по порядку: освободилось место — начинается следующий; '
        'ошибка хеша тоже освобождает место', () async {
      final started = <String>[];
      final gates = <Completer<List<int>>>[];
      final hasher = PasswordHasher(
        derive: (params, secret, salt) {
          started.add(secret);
          final gate = Completer<List<int>>();
          gates.add(gate);
          return gate.future;
        },
      );

      final results = [
        for (var i = 0; i < 6; i++)
          hasher
              .hash('secret-$i', purpose: 'password')
              .then<Object>((value) => value, onError: (Object e) => e),
      ];
      await pump();
      expect(started, ['secret-0', 'secret-1', 'secret-2', 'secret-3']);
      expect(hasher.running, 4);
      expect(hasher.queued, 2);

      gates[0].completeError(StateError('argon2 broke'));
      await pump();
      expect(started, hasLength(5));
      expect(started.last, 'secret-4');
      expect(hasher.running, 4);
      expect(hasher.queued, 1);

      for (final gate in gates.sublist(1)) {
        gate.complete(List<int>.filled(32, 7));
      }
      await pump();
      expect(started.last, 'secret-5');
      gates.last.complete(List<int>.filled(32, 7));

      final done = await Future.wait(results);
      expect(done.first, isA<StateError>());
      expect(done.sublist(1), everyElement(startsWith(r'$argon2id$')));
      expect(hasher.running, 0);
      expect(hasher.queued, 0);
    });

    test('в логе: debug — постановка в очередь и ожидание места, '
        'warning — если место ждали дольше порога', () async {
      final hasher = PasswordHasher(
        maxConcurrent: 1,
        slowQueueWait: const Duration(milliseconds: 20),
        derive: (params, secret, salt) async {
          await Future<void>.delayed(const Duration(milliseconds: 60));
          return List<int>.filled(32, 1);
        },
      );

      final first = hasher.hash(_password, purpose: 'password');
      final second = hasher.hash(_password, purpose: 'recovery');
      await Future.wait([first, second]);

      expect(
        logs.text,
        contains(
          'DEBUG [auth] argon2id queued purpose=recovery running=1/1 '
          'queued=1',
        ),
      );
      expect(
        logs.text,
        contains(
          RegExp(
            r'WARN  \[auth\] argon2id slot waited (\d+)ms '
            r'purpose=recovery running=1/1 queued=0 → too many '
            r'password checks at once, requests wait for a slot',
          ),
        ),
      );
      expect(
        logs.text,
        contains(
          RegExp(
            r'DEBUG \[auth\] argon2id hash purpose=recovery '
            r'm=19456,t=2,p=1 in \d+ms queueWait=([2-9]\d|\d{3,})ms',
          ),
        ),
      );
      expect(
        logs.text,
        contains(
          RegExp(
            r'DEBUG \[auth\] argon2id hash purpose=password '
            r'm=19456,t=2,p=1 in \d+ms queueWait=\d+ms',
          ),
        ),
      );
      expect(RegExp('WARN').allMatches(logs.text), hasLength(1));
      expect(logs.text, isNot(contains(_password)));
    });

    test('меньше 1 места — ошибка конструктора', () {
      expect(
        () => PasswordHasher(maxConcurrent: 0),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
