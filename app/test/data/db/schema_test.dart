import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/db/app_database.dart';

const _tables = [
  'budgets',
  'budget_members',
  'categories',
  'expenses',
  'recurring_rules',
  'member_profiles',
  'outbox',
  'sync_state',
  'local_prefs',
];

const _syncTables = [
  'budgets',
  'budget_members',
  'categories',
  'expenses',
  'recurring_rules',
];

const _syncColumns = ['updated_at', 'updated_by', 'deleted_at', 'server_seq'];

void main() {
  late AppDatabase db;
  late List<LogRecord> records;
  late StreamSubscription<LogRecord> sub;

  setUp(() {
    records = [];
    Logger.root.level = Level.ALL;
    sub = Logger.root.onRecord.listen(records.add);
    db = AppDatabase.memory();
  });

  tearDown(() async {
    await db.close();
    await sub.cancel();
  });

  Future<List<String>> names(String type) async {
    final rows = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = ? "
          "AND name NOT LIKE 'sqlite_%' ORDER BY name",
          variables: [Variable.withString(type)],
        )
        .get();
    return [for (final r in rows) r.read<String>('name')];
  }

  Future<Map<String, ({String type, bool notNull, int pk})>> columns(
    String table,
  ) async {
    final rows = await db.customSelect('PRAGMA table_info("$table")').get();
    return {
      for (final r in rows)
        r.read<String>('name'): (
          type: r.read<String>('type'),
          notNull: r.read<int>('notnull') == 1,
          pk: r.read<int>('pk'),
        ),
    };
  }

  Future<List<String>> indexColumns(String index) async {
    final rows = await db.customSelect('PRAGMA index_info("$index")').get();
    return [for (final r in rows) r.read<String>('name')];
  }

  test('схема версии 1 создаётся в памяти: девять таблиц', () async {
    expect(db.schemaVersion, 1);
    expect(await names('table'), unorderedEquals(_tables));
  });

  test('индексы трат, категорий и очереди', () async {
    expect(
      await names('index'),
      unorderedEquals([
        'categories_budget_sort',
        'expenses_budget_spent_on',
        'expenses_budget_deleted',
        'expenses_recurring_month',
        'outbox_not_before',
      ]),
    );
    expect(await indexColumns('expenses_budget_spent_on'), [
      'budget_id',
      'spent_on',
    ]);
    expect(await indexColumns('expenses_budget_deleted'), [
      'budget_id',
      'deleted_at',
    ]);
    expect(await indexColumns('expenses_recurring_month'), [
      'recurring_id',
      'recurring_month',
    ]);
    expect(await indexColumns('categories_budget_sort'), [
      'budget_id',
      'sort_order',
    ]);
    expect(await indexColumns('outbox_not_before'), ['not_before', 'id']);
  });

  test('общие поля синхронизации у синхронизируемых таблиц', () async {
    for (final table in _syncTables) {
      final cols = await columns(table);
      expect(cols.keys, containsAll(_syncColumns), reason: table);
      expect(cols['updated_at']!.type, 'TEXT', reason: table);
      expect(cols['deleted_at']!.notNull, isFalse, reason: table);
      expect(cols['server_seq']!.type, 'INTEGER', reason: table);
      expect(cols['server_seq']!.notNull, isFalse, reason: table);
    }
    for (final table in ['budgets', 'categories', 'expenses']) {
      final cols = await columns(table);
      expect(cols['updated_at']!.notNull, isTrue, reason: table);
      expect(cols['updated_by']!.notNull, isTrue, reason: table);
    }
    expect((await columns('recurring_rules'))['updated_at']!.notNull, isTrue);
  });

  test('поля трат: копейки, дата и месяц текстом, колонка поиска', () async {
    final cols = await columns('expenses');
    expect(cols.keys, [
      ..._syncColumns,
      'id',
      'budget_id',
      'category_id',
      'amount_kopecks',
      'spent_on',
      'comment',
      'comment_search',
      'author_id',
      'recurring_id',
      'recurring_month',
      'created_at',
    ]);
    expect(cols['id']!.pk, 1);
    expect(cols['id']!.type, 'TEXT');
    expect(cols['amount_kopecks']!.type, 'INTEGER');
    expect(cols['spent_on']!.type, 'TEXT');
    expect(cols['comment_search']!.notNull, isTrue);
    expect(cols['recurring_month']!.notNull, isFalse);
  });

  test('категории с колонкой поиска по названию', () async {
    final cols = await columns('categories');
    expect(
      cols.keys,
      containsAll([
        'id',
        'budget_id',
        'name',
        'name_search',
        'emoji',
        'color',
        'sort_order',
        'is_system',
      ]),
    );
    expect(cols['name_search']!.notNull, isTrue);
    expect(cols['color']!.notNull, isFalse);
  });

  test('бюджеты, участники, регулярные и профили', () async {
    expect(
      (await columns('budgets')).keys,
      containsAll(['id', 'kind', 'name', 'emoji', 'owner_id', 'created_at']),
    );
    final members = await columns('budget_members');
    expect(
      members.keys,
      containsAll([
        'budget_id',
        'user_id',
        'role',
        'avatar_color',
        'joined_at',
        'left_at',
      ]),
    );
    expect(members['budget_id']!.pk, 1);
    expect(members['user_id']!.pk, 2);
    expect(
      (await columns('recurring_rules')).keys,
      containsAll([
        'id',
        'budget_id',
        'category_id',
        'title',
        'amount_kopecks',
        'day_of_month',
        'start_month',
        'created_at',
      ]),
    );
    final profiles = await columns('member_profiles');
    expect(profiles.keys, [
      'user_id',
      'display_name',
      'avatar_color',
      'birthday_month',
      'birthday_day',
    ]);
    expect(profiles.keys, isNot(contains('server_seq')));
  });

  test('очередь, состояние синхронизации и настройки', () async {
    final outbox = await columns('outbox');
    expect(outbox.keys, [
      'id',
      'entity',
      'entity_id',
      'op',
      'payload',
      'created_at',
      'not_before',
      'attempts',
      'last_error',
    ]);
    expect(outbox['not_before']!.notNull, isFalse);
    expect((await columns('sync_state')).keys, [
      'id',
      'cursor',
      'last_sync_at',
      'last_error',
    ]);
    expect((await columns('local_prefs')).keys, ['key', 'value']);
  });

  test('sync_state — одна строка с курсором 0, вторую не вставить', () async {
    final rows = await db.select(db.syncStates).get();
    expect(rows, hasLength(1));
    expect(rows.single.cursor, 0);
    expect(rows.single.lastSyncAt, isNull);
    await expectLater(
      db.into(db.syncStates).insert(const SyncStatesCompanion(id: Value(1))),
      throwsA(isA<SqliteException>()),
    );
  });

  test('первое создание схемы — info со списком таблиц', () async {
    await db.customSelect('SELECT 1').get();
    final created = records
        .where((r) => r.loggerName == 'db' && r.level == Level.INFO)
        .map((r) => r.message)
        .where((m) => m.startsWith('schema created'))
        .toList();
    expect(created, hasLength(1));
    expect(created.single, contains('version=1'));
    expect(created.single, contains('tables=${_tables.join(',')}'));
    expect(created.single, matches(RegExp(r'in \d+ms$')));
  });
}
