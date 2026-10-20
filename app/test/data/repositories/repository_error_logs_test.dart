import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:shared/shared.dart';

import 'repository_harness.dart';

const String _comment = 'Секретный кофе';

Future<void> _breakInsert(RepositoryHarness h, String table) =>
    h.db.customStatement(
      'CREATE TRIGGER ${table}_broken BEFORE INSERT ON $table '
      "BEGIN SELECT RAISE(ABORT, '$table is broken'); END",
    );

String _severeLine(RepositoryHarness h) {
  final errors = h.repoLogs(Level.SEVERE);
  expect(errors, hasLength(1));
  return formatLogRecord(errors.single);
}

void _expectNoSecrets(String line, List<String> secrets) {
  for (final secret in secrets) {
    expect(
      line.toLowerCase(),
      isNot(contains(secret.toLowerCase())),
      reason: secret,
    );
  }
}

void _expectSafe(
  String line, {
  required String prefix,
  required String table,
  required List<String> secrets,
}) {
  expect(line, contains(prefix));
  _expectNoSecrets(line, secrets);
  expect(line, contains('SqliteException(1811)'));
  expect(line, contains('$table is broken'));
  expect(line, contains('Causing statement: INSERT INTO "$table"'));
  expect(line, contains('parameters: <'));
  expect(line, isNot(contains('\n  error: ')));
  final stack = line.indexOf('\n  stack:\n');
  expect(stack, greaterThan(0));
  expect(line.substring(stack), contains('package:milionchik/data/'));
}

Future<Expense> _createCoffee(RepositoryHarness h, SeededBudget b) =>
    h.expenses.create(
      budgetId: b.id,
      categoryId: b.byName('Кафе').id,
      amount: const Money.rubles(640),
      spentOn: LocalDate(2026, 10, 20),
      comment: _comment,
    );

void main() {
  group('база в памяти', () {
    late RepositoryHarness h;
    late SeededBudget b;

    setUp(() async {
      h = RepositoryHarness();
      b = await h.seedBudget();
    });

    tearDown(() => h.dispose());

    test('трата: сбой outbox - в строке тип, код, message, sql и стек, '
        'без комментария, суммы и payload', () async {
      await _breakInsert(h, 'outbox');

      await expectLater(_createCoffee(h, b), throwsA(anything));

      _expectSafe(
        _severeLine(h),
        prefix: 'ERROR [repo] expense create failed id=',
        table: 'outbox',
        secrets: [_comment, '64000', 'amountKopecks'],
      );
    });

    test('трата: сбой вставки в expenses - без комментария и суммы', () async {
      await _breakInsert(h, 'expenses');

      await expectLater(_createCoffee(h, b), throwsA(anything));

      _expectSafe(
        _severeLine(h),
        prefix: 'ERROR [repo] expense create failed id=',
        table: 'expenses',
        secrets: [_comment, '64000'],
      );
    });

    test('категория: сбой outbox - без названия', () async {
      await _breakInsert(h, 'outbox');

      await expectLater(
        h.categories.create(
          budgetId: b.id,
          name: 'Тайная',
          emoji: '🔒',
          color: CategoryColor.rose,
        ),
        throwsA(anything),
      );

      _expectSafe(
        _severeLine(h),
        prefix: 'ERROR [repo] category create failed id=',
        table: 'outbox',
        secrets: ['Тайная', '🔒'],
      );
    });

    test('регулярная: сбой outbox - без названия и суммы', () async {
      await _breakInsert(h, 'outbox');

      await expectLater(
        h.recurring.create(
          budgetId: b.id,
          categoryId: b.other.id,
          title: 'Тайный абонемент',
          amount: const Money.rubles(1234),
          dayOfMonth: 7,
          startMonth: YearMonth(2026, 11),
        ),
        throwsA(anything),
      );

      _expectSafe(
        _severeLine(h),
        prefix: 'ERROR [repo] recurring create failed id=',
        table: 'outbox',
        secrets: ['Тайный абонемент', '123400'],
      );
    });

    test('профиль участника с сервера: сбой записи - без имени', () async {
      await _breakInsert(h, 'member_profiles');

      await expectLater(
        h.members.applyProfilesFromServer([
          const MemberProfile(
            userId: 'user-anna',
            displayName: 'Анна Тайнова',
            avatarColor: CategoryColor.rose,
          ),
        ]),
        throwsA(anything),
      );

      _expectSafe(
        _severeLine(h),
        prefix: 'ERROR [repo] profile apply failed count=1',
        table: 'member_profiles',
        secrets: ['Анна Тайнова'],
      );
    });

    test('настройка: сбой записи - без значения', () async {
      await _breakInsert(h, 'local_prefs');

      await expectLater(
        DriftPrefsRepository(h.db).setString('hint', 'Тайное значение'),
        throwsA(anything),
      );

      _expectSafe(
        _severeLine(h),
        prefix: 'ERROR [repo] pref set failed key=hint type=string',
        table: 'local_prefs',
        secrets: ['Тайное значение'],
      );
    });

    test('битая запись outbox: в логе id, сущность, операция, длина payload и '
        'тип со смещением, без текста payload', () async {
      const payload =
          '{"id":"e-broken","comment":"$_comment","amountKopecks":64000';
      final outboxId = await h.db
          .into(h.db.outbox)
          .insert(
            OutboxCompanion.insert(
              entity: SyncEntity.expense,
              entityId: 'e-broken',
              op: SyncOp.upsert,
              payload: const Value(payload),
              createdAt: h.clock,
            ),
          );

      await expectLater(h.outbox.pending(), throwsA(isA<FormatException>()));

      final errors = h.repoLogs(Level.SEVERE);
      expect(errors, hasLength(2));
      for (final record in errors) {
        final line = formatLogRecord(record);
        _expectNoSecrets(line, [_comment, '64000', 'amountKopecks', '{"id"']);
        expect(line, contains('\n  stack:\n'));
      }
      expect(
        errors.first.message,
        matches(
          RegExp(
            '^outbox entry unreadable outboxId=$outboxId entity=expense '
            'id=e-broken op=upsert payloadLength=${payload.length} '
            r'error=FormatException offset=\d+$',
          ),
        ),
      );
    });
  });

  test(
    'база в фоновом изоляте, как в приложении: сбой outbox - без комментария '
    'и суммы',
    () async {
      final dir = await Directory.systemTemp.createTemp('milionchik_repo_');
      final h = RepositoryHarness(
        db: AppDatabase(
          NativeDatabase.createInBackground(File('${dir.path}/test.sqlite')),
        ),
      );
      addTearDown(() async {
        await h.dispose();
        await dir.delete(recursive: true);
      });
      final b = await h.seedBudget();
      await _breakInsert(h, 'outbox');

      await expectLater(_createCoffee(h, b), throwsA(anything));

      _expectSafe(
        _severeLine(h),
        prefix: 'ERROR [repo] expense create failed id=',
        table: 'outbox',
        secrets: [_comment, '64000', 'amountKopecks'],
      );
    },
  );
}
