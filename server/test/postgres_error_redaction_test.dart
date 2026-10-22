import 'dart:io';

import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:server/db/database.dart';
import 'package:server/db/migrator.dart';
import 'package:server/logging/log_setup.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/test_support.dart';

const _passwordHash = r'$argon2id$v=19$SECRET-PASSWORD-HASH';
const _recoveryHash = r'$argon2id$v=19$SECRET-RECOVERY-HASH';
const _displayName = 'Секретное Имя';

void main() {
  late LogCapture logs;
  late Database db;

  setUp(() async {
    logs = LogCapture();
    db = await openScratchDatabase();
    await Migrator(db, directory: Directory('migrations')).run();
    logs.clear();
  });

  Future<void> insertUser(String login) => db.execute(
    r'INSERT INTO users (id, login, display_name, password_hash, recovery_hash) '
    r'VALUES ($1::uuid, $2, $3, $4, $5)',
    parameters: [newId(), login, _displayName, _passwordHash, _recoveryHash],
    what: 'insert user',
  );

  Future<ServerException> failing(Future<void> Function() action) async {
    try {
      await action();
    } on ServerException catch (e, st) {
      Logger('test').severe('operation failed', e, st);
      return e;
    }
    fail('expected ServerException');
  }

  test('нарушение CHECK в users: ни хешей, ни имени, ни логина в логе — SQLSTATE и ограничение есть', () async {
    final error = await failing(() => insertUser('Bad-Login'));

    expect(error.detail, contains('SECRET-PASSWORD-HASH'));
    for (final secret in [
      'SECRET-PASSWORD-HASH',
      'SECRET-RECOVERY-HASH',
      _displayName,
      'Bad-Login',
    ]) {
      expect(logs.text, isNot(contains(secret)), reason: secret);
    }
    expect(logs.text, contains('WARN  [db] query insert user failed in'));
    expect(logs.text, contains('constraint users_login_check'));
    expect(logs.text, contains('sqlState=23514'));
    expect(logs.text, contains('detail="Failing row contains (…)."'));
    expect(logs.text, contains('ERROR [test] operation failed'));
    expect(logs.text, contains('  stack:'));
  });

  test('логин занят: значение ключа скрыто, имя индекса видно', () async {
    await insertUser('boris.secret');
    final error = await failing(() => insertUser('boris.secret'));

    expect(error.detail, contains('boris.secret'));
    expect(logs.text, isNot(contains('boris.secret')));
    expect(logs.text, contains('sqlState=23505'));
    expect(logs.text, contains('constraint users_login_lower_key'));
    expect(
      logs.text,
      contains('detail="Key (lower(login))=(…) already exists."'),
    );
  });

  test(
    'неверное значение параметра (класс 22): значение скрыто, тип виден',
    () async {
      final error = await failing(
        () => db.execute(
          r'SELECT $1::uuid',
          parameters: ['not-a-uuid-SECRET'],
          what: 'cast uuid',
        ),
      );

      expect(error.code, '22P02');
      expect(error.message, contains('not-a-uuid-SECRET'));
      expect(logs.text, isNot(contains('not-a-uuid-SECRET')));
      expect(logs.text, contains('invalid input syntax for type uuid: "…"'));
      expect(logs.text, contains('sqlState=22P02'));
    },
  );

  test(
    'ошибки без данных пишутся как раньше: текст и имена объектов',
    () async {
      await failing(() => db.execute('CREATE TABL x (id integer)'));
      expect(logs.text, contains('42601: syntax error at or near "TABL"'));

      await failing(() => db.execute('SELECT * FROM no_such_table'));
      expect(
        logs.text,
        contains('42P01: relation "no_such_table" does not exist'),
      );
    },
  );

  test('маска detail: значения в скобках скрыты, имена колонок оставлены', () {
    expect(
      redactPostgresDetail(
        'Key (budget_id, user_id)=(a1, b2) is not present in table "budgets".',
      ),
      'Key (budget_id, user_id)=(…) is not present in table "budgets".',
    );
    expect(
      redactPostgresDetail('Failing row contains (1, (nested), x).'),
      'Failing row contains (…).',
    );
    expect(redactPostgresDetail('Some other detail.'), 'Some other detail.');
  });
}
