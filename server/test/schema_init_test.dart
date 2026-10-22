import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:server/db/database.dart';
import 'package:server/db/migrator.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/test_support.dart';

const _tables = {
  'schema_migrations',
  'users',
  'sessions',
  'budgets',
  'budget_members',
  'invites',
  'categories',
  'expenses',
  'recurring_rules',
  'push_batches',
  'client_errors',
};

const _syncTables = {
  'users',
  'budgets',
  'budget_members',
  'categories',
  'expenses',
  'recurring_rules',
};

Future<Database> _migrated() async {
  final db = await openScratchDatabase();
  await Migrator(db, directory: Directory('migrations')).run();
  return db;
}

Matcher _pgError(String sqlState, {String? constraint}) =>
    isA<ServerException>()
        .having((e) => e.code, 'code', sqlState)
        .having(
          (e) => e.constraintName,
          'constraintName',
          constraint ?? anything,
        );

class _Fixture {
  _Fixture(this.db);

  final Database db;

  Future<String> user(String login, {String name = 'Аня'}) async {
    final id = newId();
    await db.execute(
      r'INSERT INTO users (id, login, display_name, password_hash, recovery_hash) '
      r'VALUES ($1::uuid, $2, $3, $4, $5)',
      parameters: [id, login, name, 'hash', 'recovery'],
    );
    return id;
  }

  Future<String> budget(String ownerId, {String kind = 'shared'}) async {
    final id = newId();
    await db.execute(
      r'INSERT INTO budgets (id, kind, name, emoji, owner_id, created_at, '
      r'updated_at, updated_by) '
      r'VALUES ($1::uuid, $2, $3, $4, $5::uuid, now(), now(), $5::uuid)',
      parameters: [id, kind, 'Семья', '🏠', ownerId],
    );
    return id;
  }

  Future<void> member(String budgetId, String userId) => db.execute(
    r'INSERT INTO budget_members (budget_id, user_id, role, avatar_color) '
    r"VALUES ($1::uuid, $2::uuid, 'member', 'green')",
    parameters: [budgetId, userId],
  );

  Future<String> category(
    String budgetId,
    String userId, {
    String? color,
  }) async {
    final id = newId();
    await db.execute(
      r'INSERT INTO categories (id, budget_id, name, emoji, color, sort_order, '
      r'updated_at, updated_by) '
      r'VALUES ($1::uuid, $2::uuid, $3, $4, $5, 0, now(), $6::uuid)',
      parameters: [id, budgetId, 'Продукты', '🛒', color ?? 'green', userId],
    );
    return id;
  }

  Future<String> rule(String budgetId, String categoryId, String userId) async {
    final id = newId();
    await db.execute(
      r'INSERT INTO recurring_rules (id, budget_id, category_id, title, '
      r'amount_kopecks, day_of_month, start_month, created_at, updated_at, '
      r'updated_by) '
      r"VALUES ($1::uuid, $2::uuid, $3::uuid, 'Аренда', 3000000, 5, '2026-10', "
      r'now(), now(), $4::uuid)',
      parameters: [id, budgetId, categoryId, userId],
    );
    return id;
  }

  Future<String> expense(
    String budgetId,
    String categoryId,
    String authorId, {
    int amountKopecks = 64000,
  }) async {
    final id = newId();
    await db.execute(
      r'INSERT INTO expenses (id, budget_id, category_id, amount_kopecks, '
      r'spent_on, author_id, created_at, updated_at, updated_by) '
      r"VALUES ($1::uuid, $2::uuid, $3::uuid, $4, '2026-10-19', $5::uuid, "
      r'now(), now(), $5::uuid)',
      parameters: [id, budgetId, categoryId, amountKopecks, authorId],
    );
    return id;
  }

  Future<int> seqOf(String table, String where, List<Object?> params) async {
    final rows = await db.execute(
      'SELECT seq FROM $table WHERE $where',
      parameters: params,
    );
    return rows.single.single! as int;
  }

  Future<int> count(String table, String where, List<Object?> params) async {
    final rows = await db.execute(
      'SELECT count(*) FROM $table WHERE $where',
      parameters: params,
    );
    return rows.single.single! as int;
  }
}

void main() {
  late LogCapture logs;
  setUp(() => logs = LogCapture());

  group('0001_init: структура', () {
    test(
      'все таблицы 00-spec §8, push_batches и последовательность change_seq',
      () async {
        final db = await _migrated();
        final tables = await db.execute(
          "SELECT table_name FROM information_schema.tables "
          "WHERE table_schema = 'public' AND table_type = 'BASE TABLE'",
        );
        expect({for (final row in tables) row.single}, _tables);

        final sequence = await db.execute(
          "SELECT data_type FROM information_schema.sequences "
          "WHERE sequence_name = 'change_seq'",
        );
        expect(sequence.single.single, 'bigint');
        expect(logs.text, contains('migration 0001_init.sql applied'));
      },
    );

    test(
      'индексы: pull по (budget_id, seq), логин без учёта регистра, служебные',
      () async {
        final db = await _migrated();
        final rows = await db.execute(
          "SELECT indexname, indexdef FROM pg_indexes WHERE schemaname = 'public'",
        );
        final indexes = {
          for (final row in rows) row[0]! as String: row[1]! as String,
        };

        for (final table in [
          'budget_members',
          'categories',
          'expenses',
          'recurring_rules',
        ]) {
          expect(
            indexes['${table}_budget_seq'],
            'CREATE INDEX ${table}_budget_seq ON public.$table '
            'USING btree (budget_id, seq)',
            reason: table,
          );
        }
        expect(
          indexes['users_login_lower_key'],
          'CREATE UNIQUE INDEX users_login_lower_key ON public.users '
          'USING btree (lower(login))',
        );
        expect(
          indexes['budgets_personal_owner_key'],
          startsWith('CREATE UNIQUE INDEX budgets_personal_owner_key'),
        );
        expect(
          indexes['sessions_refresh_hash_key'],
          startsWith('CREATE UNIQUE INDEX sessions_refresh_hash_key'),
        );
        expect(
          indexes['push_batches_pkey'],
          endsWith('USING btree (user_id, batch_id)'),
        );
        for (final name in [
          'sessions_user',
          'budgets_owner',
          'budget_members_user',
          'invites_pkey',
          'invites_budget',
          'push_batches_created_at',
          'client_errors_received_at',
        ]) {
          expect(indexes, contains(name));
        }
      },
    );

    test('типы: деньги bigint копеек, дата траты date, моменты timestamptz, seq bigint', () async {
      final db = await _migrated();
      final rows = await db.execute(
        "SELECT table_name, column_name, data_type, is_nullable "
        "FROM information_schema.columns WHERE table_schema = 'public'",
      );
      final columns = {
        for (final row in rows)
          '${row[0]}.${row[1]}': (type: row[2]! as String, nullable: row[3]),
      };

      expect(columns['expenses.amount_kopecks']?.type, 'bigint');
      expect(columns['recurring_rules.amount_kopecks']?.type, 'bigint');
      expect(columns['expenses.spent_on']?.type, 'date');
      final moments = columns.entries.where((c) => c.key.endsWith('_at'));
      expect(moments, hasLength(greaterThan(20)));
      for (final column in moments) {
        expect(
          column.value.type,
          'timestamp with time zone',
          reason: column.key,
        );
      }
      for (final table in _syncTables) {
        expect(columns['$table.seq'], (type: 'bigint', nullable: 'NO'));
      }
      expect(columns['users.seq'], isNotNull);
      expect(columns['sessions.seq'], isNull);
    });
  });

  group('0001_init: seq из change_seq', () {
    test(
      'каждая вставка и правка синхронизируемой строки получает новый seq',
      () async {
        final db = await _migrated();
        final f = _Fixture(db);
        final owner = await f.user('anna');
        final budget = await f.budget(owner);
        await f.member(budget, owner);
        final category = await f.category(budget, owner);
        final rule = await f.rule(budget, category, owner);
        final expense = await f.expense(budget, category, owner);

        final inserted = [
          await f.seqOf('users', r'id = $1::uuid', [owner]),
          await f.seqOf('budgets', r'id = $1::uuid', [budget]),
          await f.seqOf('budget_members', r'budget_id = $1::uuid', [budget]),
          await f.seqOf('categories', r'id = $1::uuid', [category]),
          await f.seqOf('recurring_rules', r'id = $1::uuid', [rule]),
          await f.seqOf('expenses', r'id = $1::uuid', [expense]),
        ];
        expect(inserted, orderedEquals([...inserted]..sort()));
        expect(inserted.toSet(), hasLength(inserted.length));

        var last = inserted.last;
        for (final (table, where, id) in [
          ('budgets', r"name = 'Дом' WHERE id = $1::uuid", budget),
          (
            'budget_members',
            r"avatar_color = 'red' WHERE budget_id = $1::uuid",
            budget,
          ),
          ('categories', r"name = 'Еда' WHERE id = $1::uuid", category),
          ('recurring_rules', r"title = 'Квартира' WHERE id = $1::uuid", rule),
          ('expenses', r'deleted_at = now() WHERE id = $1::uuid', expense),
        ]) {
          await db.execute('UPDATE $table SET $where', parameters: [id]);
          final key = table == 'budget_members' ? 'budget_id' : 'id';
          final seq = await f.seqOf(table, '$key = \$1::uuid', [id]);
          expect(seq, greaterThan(last), reason: table);
          last = seq;
        }
      },
    );

    test('seq от клиента не принимается: его всегда ставит сервер', () async {
      final db = await _migrated();
      final f = _Fixture(db);
      final owner = await f.user('anna');
      final budget = await f.budget(owner);
      await db.execute(
        r'UPDATE budgets SET seq = 1 WHERE id = $1::uuid',
        parameters: [budget],
      );
      expect(
        await f.seqOf('budgets', r'id = $1::uuid', [budget]),
        greaterThan(2),
      );
    });

    test('профиль: seq меняют имя, день рождения и удаление, но не пароль и настройки', () async {
      final db = await _migrated();
      final f = _Fixture(db);
      final user = await f.user('anna');
      Future<int> seq() => f.seqOf('users', r'id = $1::uuid', [user]);
      Future<void> update(String set) => db.execute(
        'UPDATE users SET $set WHERE id = \$1::uuid',
        parameters: [user],
      );

      var last = await seq();
      for (final set in [
        "password_hash = 'new'",
        "recovery_hash = 'new'",
        'holidays_enabled = false',
        "holidays_disabled = '{newyear}'",
        "display_name = 'Аня'",
      ]) {
        await update(set);
        expect(await seq(), last, reason: set);
      }
      for (final set in [
        "display_name = 'Анна'",
        'birthday_month = 2, birthday_day = 29',
        'deleted_at = now()',
      ]) {
        await update(set);
        final next = await seq();
        expect(next, greaterThan(last), reason: set);
        last = next;
      }
    });
  });

  group('0001_init: ограничения', () {
    test('логин уникален без учёта регистра и хранится строчными', () async {
      final db = await _migrated();
      final f = _Fixture(db);
      await f.user('anna.k_1');

      await expectLater(
        f.user('anna.k_1'),
        throwsA(_pgError('23505', constraint: 'users_login_lower_key')),
      );
      await expectLater(f.user('Anna.K_1'), throwsA(_pgError('23514')));
      await expectLater(f.user('an'), throwsA(_pgError('23514')));
      await expectLater(f.user('anna-k'), throwsA(_pgError('23514')));

      final found = await db.execute(
        r'SELECT login FROM users WHERE lower(login) = lower($1)',
        parameters: ['ANNA.K_1'],
      );
      expect(found.single.single, 'anna.k_1');
    });

    test(
      'один личный бюджет на пользователя, общих — сколько угодно',
      () async {
        final db = await _migrated();
        final f = _Fixture(db);
        final user = await f.user('anna');
        await f.budget(user, kind: 'personal');
        await expectLater(
          f.budget(user, kind: 'personal'),
          throwsA(_pgError('23505', constraint: 'budgets_personal_owner_key')),
        );
        await f.budget(user);
        await f.budget(user);
        await expectLater(
          f.budget(user, kind: 'family'),
          throwsA(_pgError('23514')),
        );
      },
    );

    test(
      'цвета категорий и аватаров — ровно ключи CategoryColor из shared',
      () async {
        final db = await _migrated();
        final f = _Fixture(db);
        final user = await f.user('anna');
        final budget = await f.budget(user);
        for (final color in CategoryColor.values) {
          await f.category(budget, user, color: color.name);
        }
        await expectLater(
          f.category(budget, user, color: 'black'),
          throwsA(_pgError('23514')),
        );
        await db.execute(
          r'INSERT INTO categories (id, budget_id, name, emoji, color, sort_order, '
          r"is_system, updated_at, updated_by) VALUES ($1::uuid, $2::uuid, 'Другое', "
          r"'📦', NULL, 99, true, now(), $3::uuid)",
          parameters: [newId(), budget, user],
        );
      },
    );

    test('сумма траты 0,01–10 000 000 ₽ в копейках', () async {
      final db = await _migrated();
      final f = _Fixture(db);
      final user = await f.user('anna');
      final budget = await f.budget(user);
      final category = await f.category(budget, user);
      await f.expense(budget, category, user, amountKopecks: 1);
      await f.expense(budget, category, user, amountKopecks: maxExpenseKopecks);
      for (final bad in [0, -100, maxExpenseKopecks + 1]) {
        await expectLater(
          f.expense(budget, category, user, amountKopecks: bad),
          throwsA(_pgError('23514')),
          reason: '$bad',
        );
      }
    });
  });

  group('0001_init: удаление', () {
    test(
      'удаление бюджета уносит его участников, категории, регулярные и траты',
      () async {
        final db = await _migrated();
        final f = _Fixture(db);
        final user = await f.user('anna');
        final personal = await f.budget(user, kind: 'personal');
        final shared = await f.budget(user);
        for (final budget in [personal, shared]) {
          await f.member(budget, user);
          final category = await f.category(budget, user);
          await f.rule(budget, category, user);
          await f.expense(budget, category, user);
        }

        await db.execute(
          r'DELETE FROM budgets WHERE id = $1::uuid',
          parameters: [personal],
        );

        for (final table in [
          'budget_members',
          'categories',
          'recurring_rules',
          'expenses',
        ]) {
          expect(
            await f.count(table, r'budget_id = $1::uuid', [personal]),
            0,
            reason: table,
          );
          expect(
            await f.count(table, r'budget_id = $1::uuid', [shared]),
            1,
            reason: table,
          );
        }
      },
    );

    test(
      'строку автора трат в общем бюджете не удалить: траты не пропадут',
      () async {
        final db = await _migrated();
        final f = _Fixture(db);
        final owner = await f.user('anna');
        final author = await f.user('boris');
        final shared = await f.budget(owner);
        await f.member(shared, author);
        final category = await f.category(shared, owner);
        await f.expense(shared, category, author);

        await expectLater(
          db.execute(
            r'DELETE FROM users WHERE id = $1::uuid',
            parameters: [author],
          ),
          throwsA(_pgError('23503')),
        );
        expect(await f.count('expenses', r'author_id = $1::uuid', [author]), 1);
      },
    );

    test('сессии и пачки push удаляются вместе с пользователем, отчёты об ошибках остаются', () async {
      final db = await _migrated();
      final f = _Fixture(db);
      final user = await f.user('anna');
      await db.execute(
        r'INSERT INTO sessions (id, user_id, device_name, refresh_hash, expires_at) '
        r"VALUES ($1::uuid, $2::uuid, 'Pixel', 'h1', now() + interval '90 days')",
        parameters: [newId(), user],
      );
      await db.execute(
        r'INSERT INTO push_batches (user_id, batch_id, response) '
        r"VALUES ($1::uuid, 'b1', '{}')",
        parameters: [user],
      );
      await db.execute(
        r'INSERT INTO client_errors (user_id, app_version, kind, message) '
        r"VALUES ($1::uuid, '1.0.0+1', 'crash', 'StateError')",
        parameters: [user],
      );

      await db.execute(
        r'DELETE FROM users WHERE id = $1::uuid',
        parameters: [user],
      );

      expect(await f.count('sessions', 'true', []), 0);
      expect(await f.count('push_batches', 'true', []), 0);
      expect(await f.count('client_errors', 'user_id IS NULL', []), 1);
    });
  });
}
