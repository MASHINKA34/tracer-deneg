import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:server/account/account_service.dart';
import 'package:server/db/database.dart';
import 'package:server/db/migrator.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/test_support.dart';

const _release = '0004_release_deleted_logins.sql';

Directory _migrationsBefore(String name) {
  final dir = Directory.systemTemp.createTempSync('milionchik_migrations_');
  addTearDown(() => dir.deleteSync(recursive: true));
  for (final file in Directory('migrations').listSync().whereType<File>()) {
    final fileName = file.uri.pathSegments.last;
    if (fileName.endsWith('.sql') && fileName.compareTo(name) < 0) {
      file.copySync('${dir.path}/$fileName');
    }
  }
  return dir;
}

void _addMigration(Directory dir, String name) =>
    File('migrations/$name').copySync('${dir.path}/$name');

Matcher _checkViolation() => isA<ServerException>()
    .having((e) => e.code, 'code', '23514')
    .having((e) => e.constraintName, 'constraintName', 'users_login_check');

Future<String> _user(Database db, String login, {String? id}) async {
  final userId = id ?? newId();
  await db.execute(
    r'INSERT INTO users (id, login, display_name, password_hash, '
    r'recovery_hash) VALUES ($1::uuid, $2, $3, $4, $5)',
    parameters: [userId, login, 'Аня', 'hash', 'recovery'],
  );
  return userId;
}

Future<void> _deleteKeepingLogin(Database db, String userId) => db.execute(
  r'UPDATE users SET deleted_at = now(), display_name = $2, '
  r"password_hash = '', recovery_hash = '' WHERE id = $1::uuid",
  parameters: [userId, deletedMemberName],
);

Future<Map<String, List<Object?>>> _users(Database db) async {
  final rows = await db.execute(
    'SELECT id, login, seq, deleted_at IS NOT NULL FROM users ORDER BY id',
  );
  return {for (final row in rows) row[0]! as String: row.sublist(1)};
}

void main() {
  late LogCapture logs;

  setUp(() => logs = LogCapture());

  group(_release, () {
    late Database db;
    late Directory dir;
    late String anna;
    late String olga;
    late String boris;

    setUp(() async {
      db = await openScratchDatabase();
      dir = _migrationsBefore(_release);
      final before = await Migrator(db, directory: dir).run();
      expect(before.schemaVersion, 3);
      anna = await _user(db, 'anna');
      olga = await _user(db, 'olga');
      boris = await _user(db, 'boris.k');
      await _deleteKeepingLogin(db, olga);
      await _deleteKeepingLogin(db, boris);
      _addMigration(dir, _release);
      logs.clear();
    });

    test('удалённые аккаунты со старыми логинами получают служебный логин, '
        'живые и seq не меняются, в логе число освобождённых', () async {
      final before = await _users(db);

      final result = await Migrator(db, directory: dir).run();

      expect(result.applied, [_release]);
      expect(result.schemaVersion, 4);
      final after = await _users(db);
      expect(after[anna], before[anna]);
      expect(after[olga], [deletedAccountLogin(olga), before[olga]![1], true]);
      expect(after[boris], [
        deletedAccountLogin(boris),
        before[boris]![1],
        true,
      ]);
      expect(
        logs.text,
        contains(
          RegExp(
            r'INFO  \[db\] migration 0004_release_deleted_logins\.sql '
            r'applied in \d+ms \(1/1\) changedRows=2',
          ),
        ),
      );
      expect(logs.text, isNot(contains('olga')));
      expect(logs.text, isNot(contains('boris')));

      final newOlga = await _user(db, 'olga');
      final newBoris = await _user(db, 'boris.k');
      expect((await _users(db))[newOlga]![0], 'olga');
      expect((await _users(db))[newBoris]![0], 'boris.k');
    });

    test('повторно ничего не меняет: мигратор её пропускает, тот же SQL ещё '
        'раз — 0 строк', () async {
      await Migrator(db, directory: dir).run();
      final released = await _users(db);
      logs.clear();

      final again = await Migrator(db, directory: dir).run();
      expect(again.applied, isEmpty);
      expect(logs.text, isNot(contains('applying')));

      final sql = File('migrations/$_release').readAsStringSync();
      final changed = await db.withConnection(
        'rerun $_release',
        (connection) => connection.transaction(
          'rerun $_release',
          (tx) async => (await tx.execute(
            sql,
            what: 'rerun $_release',
            queryMode: QueryMode.simple,
          )).affectedRows,
        ),
      );
      expect(changed, 0);
      expect(await _users(db), released);
    });
  });

  group('ограничение users_login_check после $_release', () {
    late Database db;

    setUp(() async {
      db = await openScratchDatabase();
      await Migrator(db, directory: Directory('migrations')).run();
    });

    test('служебный логин нельзя живому аккаунту и чужой у удалённого', () async {
      final id = newId();
      await expectLater(
        _user(db, deletedAccountLogin(id), id: id),
        throwsA(_checkViolation()),
      );

      final anna = await _user(db, 'anna');
      await expectLater(
        db.execute(
          r'UPDATE users SET deleted_at = now(), login = $2 '
          r'WHERE id = $1::uuid',
          parameters: [anna, deletedAccountLogin(newId())],
        ),
        throwsA(_checkViolation()),
      );
      await db.execute(
        r'UPDATE users SET deleted_at = now(), login = $2 WHERE id = $1::uuid',
        parameters: [anna, deletedAccountLogin(anna)],
      );
      expect((await _users(db))[anna], [
        deletedAccountLogin(anna),
        isA<int>(),
        true,
      ]);
    });

    test('формат живого логина прежний: 3–32 символа [a-z0-9_.]', () async {
      await _user(db, 'anna.k_1');
      await _user(db, 'a' * loginMaxLength);
      for (final login in [
        'Anna',
        'an',
        'anna-k',
        'a' * (loginMaxLength + 1),
      ]) {
        await expectLater(
          _user(db, login),
          throwsA(_checkViolation()),
          reason: login,
        );
      }
    });
  });
}
