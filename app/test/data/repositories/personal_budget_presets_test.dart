import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/repositories/budgets_repository.dart';
import 'package:milionchik/data/repositories/records.dart';
import 'package:shared/shared.dart';

import 'repository_harness.dart';

const List<String> _specOrder = [
  '0 🛒 Продукты green',
  '1 ☕ Кафе orange',
  '2 🚇 Транспорт yellow',
  '3 🏠 Дом blue',
  '4 💊 Здоровье red',
  '5 🏋️ Спорт indigo',
  '6 🎮 Развлечения pink',
  '7 👕 Одежда purple',
  '8 📱 Связь teal',
  '9 🎁 Подарки rose',
  '10 📦 Другое null',
];

String _describe(Category c) =>
    '${c.sortOrder} ${c.emoji} ${c.name} ${c.color?.name}';

Future<List<Category>> _storedCategories(RepositoryHarness h) async {
  final rows = await (h.db.select(
    h.db.categories,
  )..orderBy([(c) => OrderingTerm.asc(c.sortOrder)])).get();
  return [for (final r in rows) categoryFromRow(r)];
}

void main() {
  late RepositoryHarness h;

  setUp(() => h = RepositoryHarness());

  tearDown(() => h.dispose());

  test('пустая база: личный бюджет с данными текущего пользователя', () async {
    final budget = await h.budgets.createLocalPersonal();

    expect(budget.kind, BudgetKind.personal);
    expect(budget.name, DriftBudgetsRepository.personalName);
    expect(budget.emoji, DriftBudgetsRepository.personalEmoji);
    expect(validateBudgetName(budget.name), isNull);
    expect(validateEmoji(budget.emoji), isNull);
    expect(budget.ownerId, meId);
    expect(budget.updatedBy, meId);
    expect(budget.createdAt, h.clock);
    expect(budget.updatedAt, h.clock);
    expect(budget.deletedAt, isNull);
    expect(budget.seq, isNull);
    expect(await h.budgets.watchAll().first, [budget]);
  });

  test('11 категорий в порядке 00-spec §7.4, «Другое» последняя, системная, '
      'без цвета', () async {
    final budget = await h.budgets.createLocalPersonal();

    final visible = await h.categories.watchByBudget(budget.id).first;
    expect(visible.map(_describe), _specOrder);
    expect(visible.where((c) => c.isSystem).map((c) => c.name), ['Другое']);
    expect(visible.last.isSystem, isTrue);
    expect(visible.last.color, isNull);
    expect(visible.last.emoji, '📦');
    for (final c in visible) {
      expect(c.budgetId, budget.id, reason: c.name);
      expect(c.updatedBy, meId, reason: c.name);
      expect(c.updatedAt, h.clock, reason: c.name);
      expect(c.deletedAt, isNull, reason: c.name);
    }
    expect(visible.map((c) => c.id).toSet(), hasLength(11));

    final stored = await _storedCategories(h);
    expect(stored, visible);
  });

  test(
    'outbox: бюджет и 11 категорий по порядку, payload из моделей',
    () async {
      final budget = await h.budgets.createLocalPersonal();
      final categories = await h.categories.watchByBudget(budget.id).first;

      final rows = await h.outboxRows();
      expect(rows, hasLength(12));
      expect(rows.every((r) => r.op == SyncOp.upsert), isTrue);
      expect(rows.every((r) => r.notBefore == null), isTrue);
      expect(rows.first.entity, SyncEntity.budget);
      expect(rows.first.entityId, budget.id);
      expect(payloadOf(rows.first), budget.toJson());
      final categoryRows = rows.skip(1).toList();
      expect(categoryRows.map((r) => r.entity).toSet(), {SyncEntity.category});
      expect(categoryRows.map((r) => r.entityId), categories.map((c) => c.id));
      for (var i = 0; i < categories.length; i++) {
        expect(payloadOf(categoryRows[i]), categories[i].toJson());
      }
      expect(await h.outbox.count(), 12);
    },
  );

  test(
    'повторный вызов ничего не создаёт и возвращает тот же бюджет',
    () async {
      final first = await h.budgets.createLocalPersonal();
      final before = await h.rowCounts();
      final outboxBefore = await h.outboxRows();
      h.advance(const Duration(hours: 1));

      final second = await h.budgets.createLocalPersonal();

      expect(second, first);
      expect(await h.rowCounts(), before);
      expect(before, {
        'budgets': 1,
        'categories': 11,
        'expenses': 0,
        'recurring_rules': 0,
        'outbox': 12,
      });
      expect(
        (await h.outboxRows()).map((r) => r.id),
        outboxBefore.map((r) => r.id),
      );
    },
  );

  test(
    'личный бюджет с сервера уже есть: возвращается он, outbox пуст',
    () async {
      final server = await h.seedBudget(id: 'b-server-personal');
      final before = await h.rowCounts();

      final budget = await h.budgets.createLocalPersonal();

      expect(budget, server.budget);
      expect(await h.rowCounts(), before);
      expect(await h.outboxRows(), isEmpty);
    },
  );

  test('общий и удалённый личный не считаются: создаётся новый', () async {
    await h.seedBudget(id: 'b-shared', kind: BudgetKind.shared);
    await h.budgets.applyFromServer([
      Budget(
        id: 'b-old-personal',
        kind: BudgetKind.personal,
        name: 'Старый',
        emoji: '🗑',
        ownerId: meId,
        createdAt: DateTime.utc(2026, 9, 1),
        updatedAt: DateTime.utc(2026, 9, 2),
        updatedBy: serverUserId,
        deletedAt: DateTime.utc(2026, 9, 2),
      ),
    ]);

    final budget = await h.budgets.createLocalPersonal();

    expect(budget.id, isNot(anyOf('b-shared', 'b-old-personal')));
    expect(budget.kind, BudgetKind.personal);
    expect(
      (await h.categories.watchByBudget(budget.id).first).map(_describe),
      _specOrder,
    );
    expect(await h.outbox.count(), 12);
  });

  test('сбой на «Другое» откатывает всё: ни бюджета, ни категорий, ни outbox, '
      'в ошибке нет названий', () async {
    await h.db.customStatement(
      'CREATE TRIGGER categories_system_broken BEFORE INSERT ON categories '
      "WHEN NEW.is_system = 1 BEGIN SELECT RAISE(ABORT, 'system broken'); END",
    );

    await expectLater(h.budgets.createLocalPersonal(), throwsA(anything));

    expect(await h.rowCounts(), {
      'budgets': 0,
      'categories': 0,
      'expenses': 0,
      'recurring_rules': 0,
      'outbox': 0,
    });
    final errors = h.repoLogs(Level.SEVERE);
    expect(errors, hasLength(1));
    final line = formatLogRecord(errors.single);
    expect(
      line,
      matches(
        RegExp(
          r'ERROR \[repo\] budget create-personal failed id=[0-9a-f-]{36} '
          r'after \d+ms, transaction rolled back: ',
        ),
      ),
    );
    expect(line, contains('system broken'));
    expect(line, contains('\n  stack:\n'));
    for (final secret in [
      'Другое',
      '📦',
      DriftBudgetsRepository.personalName,
      DriftBudgetsRepository.personalEmoji,
    ]) {
      expect(line, isNot(contains(secret)), reason: secret);
    }
    expect(h.repoLogs(Level.INFO), isEmpty);
  });

  test('логи: создание - info с id, числом категорий и мс; повтор - debug '
      '«уже есть»; без названий', () async {
    final budget = await h.budgets.createLocalPersonal();
    await h.budgets.createLocalPersonal();

    final info = h.repoLogs(Level.INFO).map((r) => r.message).toList();
    expect(info, [
      'outbox size=12 was=- after=budget.create-personal',
      matches(
        RegExp(
          '^personal budget created id=${budget.id} categories=11 '
          r'outbox=12 in \d+ms$',
        ),
      ),
    ]);

    final debug = h.repoLogs(Level.FINE).map((r) => r.message).toList();
    expect(
      debug,
      contains(
        matches(
          RegExp(
            '^budget create-personal id=${budget.id} kind=personal '
            r'categories=11 outbox=12 in \d+ms$',
          ),
        ),
      ),
    );
    expect(
      debug,
      contains(
        matches(
          RegExp(
            '^personal budget already exists id=${budget.id} owner=$meId, '
            r'nothing created in \d+ms$',
          ),
        ),
      ),
    );
    expect(
      debug,
      contains(
        matches(
          RegExp(
            r'^budget create-personal id=[0-9a-f-]{36} '
            'skipped existing=${budget.id} '
            r'in \d+ms$',
          ),
        ),
      ),
    );

    final all = h.repoLogs().map((r) => r.message).join('\n');
    for (final secret in [
      'Продукты',
      'Другое',
      DriftBudgetsRepository.personalName,
      DriftBudgetsRepository.personalEmoji,
    ]) {
      expect(all, isNot(contains(secret)), reason: secret);
    }
  });
}
