import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/data/repositories/repository_errors.dart';
import 'package:shared/shared.dart';

import 'repository_harness.dart';

void main() {
  late RepositoryHarness h;
  late SeededBudget b;

  setUp(() async {
    h = RepositoryHarness();
    b = await h.seedBudget();
  });

  tearDown(() => h.dispose());

  test('чтение: по порядку, «Другое» последняя', () async {
    final list = await h.categories.watchByBudget(b.id).first;
    expect(list.map((c) => c.name), [
      'Продукты',
      'Кафе',
      'Транспорт',
      'Дом',
      'Здоровье',
      'Спорт',
      'Развлечения',
      'Одежда',
      'Связь',
      'Подарки',
      'Другое',
    ]);
  });

  test(
    'новая категория встаёт последней перед «Другое», одна запись upsert',
    () async {
      final created = await h.categories.create(
        budgetId: b.id,
        name: '  Книги ',
        emoji: '📚',
        color: CategoryColor.teal,
      );

      expect(created.name, 'Книги');
      expect(created.sortOrder, 10);
      expect(created.isSystem, isFalse);
      expect(created.updatedBy, meId);
      expect(created.updatedAt, h.clock);

      final names = (await h.categories.watchByBudget(b.id).first)
          .map((c) => c.name)
          .toList();
      expect(names.sublist(names.length - 2), ['Книги', 'Другое']);

      final rows = await h.outboxRows();
      expect(rows, hasLength(1));
      expect(rows.single.entity, SyncEntity.category);
      expect(rows.single.op, SyncOp.upsert);
      expect(rows.single.entityId, created.id);
      expect(payloadOf(rows.single), created.toJson());
    },
  );

  test('порядок не переиспользуется после удаления последней своей', () async {
    final first = await h.categories.create(
      budgetId: b.id,
      name: 'Книги',
      emoji: '📚',
      color: CategoryColor.teal,
    );
    await h.categories.delete(first.id);
    final second = await h.categories.create(
      budgetId: b.id,
      name: 'Кино',
      emoji: '🎬',
      color: CategoryColor.pink,
    );
    expect(first.sortOrder, 10);
    expect(second.sortOrder, 11);
  });

  test('правка: одна запись upsert, колонка поиска обновлена', () async {
    final cafe = b.byName('Кафе');
    h.advance(const Duration(minutes: 1));

    final updated = await h.categories.update(
      cafe.id,
      name: 'Ёда вне дома',
      color: CategoryColor.red,
    );

    expect(updated.name, 'Ёда вне дома');
    expect(updated.color, CategoryColor.red);
    expect(updated.emoji, cafe.emoji);
    expect(updated.sortOrder, cafe.sortOrder);
    expect(updated.updatedAt, h.clock);

    final rows = await h.outboxRows();
    expect(rows, hasLength(1));
    expect(payloadOf(rows.single), updated.toJson());
    final row = await (h.db.select(
      h.db.categories,
    )..where((c) => c.id.equals(cafe.id))).getSingle();
    expect(row.nameSearch, 'еда вне дома');
  });

  test('ошибка валидации названия и эмодзи — ничего не пишется', () async {
    final before = await h.rowCounts();
    Matcher invalid(ValidationError e) => throwsA(
      isA<RepositoryException>().having((x) => x.validation, 'validation', e),
    );

    await expectLater(
      h.categories.create(
        budgetId: b.id,
        name: '   ',
        emoji: '📚',
        color: CategoryColor.teal,
      ),
      invalid(ValidationError.categoryNameEmpty),
    );
    await expectLater(
      h.categories.create(
        budgetId: b.id,
        name: 'а' * 25,
        emoji: '📚',
        color: CategoryColor.teal,
      ),
      invalid(ValidationError.categoryNameTooLong),
    );
    await expectLater(
      h.categories.create(
        budgetId: b.id,
        name: 'Книги',
        emoji: 'Ab',
        color: CategoryColor.teal,
      ),
      invalid(ValidationError.emojiInvalid),
    );
    await expectLater(
      h.categories.update(b.byName('Кафе').id, name: ''),
      invalid(ValidationError.categoryNameEmpty),
    );

    expect(await h.rowCounts(), before);
  });

  test('надгробие с сервера не видно в чтении', () async {
    final cafe = b.byName('Кафе');
    await h.categories.applyFromServer([
      cafe.copyWith(deletedAt: h.clock, updatedAt: h.clock, seq: 9),
    ]);
    expect(await h.categories.watchById(cafe.id).first, isNull);
    expect(
      (await h.categories.watchByBudget(b.id).first).map((c) => c.id),
      isNot(contains(cafe.id)),
    );
    expect(await h.outboxRows(), isEmpty);
  });
}
