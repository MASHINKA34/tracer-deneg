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
}
