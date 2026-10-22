import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/features/categories/category_editor_controller.dart';
import 'package:shared/shared.dart';

import '../../data/provider_harness.dart';
import 'categories_fixture.dart';

Future<(ProviderHarness, CategoriesFixture)> _start() async {
  final h = ProviderHarness();
  final fixture = await CategoriesFixture.presets(h.db);
  return (h, fixture);
}

CategoryEditorController _controller(ProviderHarness h, String? id) {
  h.container.listen(categoryEditorControllerProvider(id), (_, _) {});
  return h.read(categoryEditorControllerProvider(id).notifier);
}

CategoryDraft _draft(ProviderHarness h, String? id) =>
    h.read(categoryEditorControllerProvider(id));

void main() {
  final cafe = Category(
    id: 'cafe',
    budgetId: 'b1',
    name: 'Кафе',
    emoji: '☕',
    color: CategoryColor.orange,
    sortOrder: 1,
    isSystem: false,
    updatedAt: DateTime.utc(2026, 10, 19),
    updatedBy: 'u1',
  );

  test('изменённые поля — только отличающиеся от категории; пробелы по краям '
      'названия не считаются правкой', () {
    expect(const CategoryDraft().changedFields(cafe), isEmpty);
    expect(
      const CategoryDraft(
        name: '  Кафе ',
        emoji: '☕',
        color: CategoryColor.orange,
      ).changedFields(cafe),
      isEmpty,
    );
    expect(
      const CategoryDraft(
        color: CategoryColor.blue,
        emoji: '🍔',
        name: 'Кофейни',
      ).changedFields(cafe),
      [CategoryField.name, CategoryField.emoji, CategoryField.color],
    );
    expect(
      categoryFieldNames(const [CategoryField.name, CategoryField.color]),
      'name,color',
    );
    expect(categoryFieldNames(const []), 'none');
  });

  test('новая категория по умолчанию: пустое название, ☕ и зелёный; ошибка '
      '«пусто» видна только после правки поля или «Сохранить», «длинно» — '
      'сразу', () {
    const draft = CategoryDraft();
    expect(draft.nameOf(null), '');
    expect(draft.emojiOf(null), '☕');
    expect(draft.colorOf(null), CategoryColor.green);
    expect(draft.nameError(null), ValidationError.categoryNameEmpty);
    expect(draft.visibleNameError(null), isNull);
    expect(
      draft.copyWith(submitted: true).visibleNameError(null),
      ValidationError.categoryNameEmpty,
    );
    expect(
      draft.copyWith(name: '   ').visibleNameError(null),
      ValidationError.categoryNameEmpty,
    );
    expect(
      draft.copyWith(name: 'К' * 25).visibleNameError(null),
      ValidationError.categoryNameTooLong,
    );
    expect(draft.copyWith(name: 'К' * 24).visibleNameError(null), isNull);
    expect(const CategoryDraft().visibleNameError(cafe), isNull);
    expect(const CategoryDraft(name: '').visibleNameError(cafe), isNotNull);
    expect(frequentCategoryEmojis, hasLength(19));
    for (final emoji in frequentCategoryEmojis) {
      expect(validateEmoji(emoji), isNull, reason: emoji);
    }
  });

  test('«🐱 Кот» создаётся перед «Другое» с выбранным цветом; info '
      '[categories] с id, бюджетом и мс без названия', () async {
    final (h, f) = await _start();
    final controller = _controller(h, null);
    controller
      ..setName('  Кот ')
      ..setColor(CategoryColor.teal);
    expect(controller.setEmoji('🐱', from: 'keyboard'), isTrue);

    expect(
      await controller.save(null, budgetId: f.budgetId),
      CategorySave.saved,
    );

    final list = await f.list();
    expect(list.map((c) => c.name), [
      ...[for (final p in presetCategories.where((p) => !p.isSystem)) p.name],
      'Кот',
      'Другое',
    ]);
    final cat = list[10];
    expect(cat.emoji, '🐱');
    expect(cat.color, CategoryColor.teal);
    expect(cat.isSystem, isFalse);
    final info = h.lines('categories', Level.INFO);
    expect(info, hasLength(1));
    expect(
      info.single,
      matches(
        'INFO  \\[categories\\] category created id=${cat.id} '
        'budgetId=${f.budgetId} order=10 color=teal in \\d+ms\$',
      ),
    );
    for (final line in h.lines('categories')) {
      expect(line, isNot(contains('Кот')), reason: line);
      expect(line, isNot(contains('🐱')), reason: line);
    }
    expect(_draft(h, null).name, isNull);
  });

  test('пустое и длинное название не сохраняются: invalid, ошибка видна, в '
      'базе ничего нового, info с кодом и длиной', () async {
    final (h, f) = await _start();
    final controller = _controller(h, null);

    expect(
      await controller.save(null, budgetId: f.budgetId),
      CategorySave.invalid,
    );
    expect(
      _draft(h, null).visibleNameError(null),
      ValidationError.categoryNameEmpty,
    );
    controller.setName('Очень длинное название кота');
    expect(
      await controller.save(null, budgetId: f.budgetId),
      CategorySave.invalid,
    );
    expect(await f.list(), hasLength(11));
    expect(h.lines('categories', Level.INFO), [
      matches(
        r'category save new blocked: category_name_empty length=0 max=24, '
        r'error shown under the name field$',
      ),
      matches(
        r'category save new blocked: category_name_too_long length=27 '
        r'max=24, error shown under the name field$',
      ),
    ]);
  });

  test('правка «Кафе»: пишутся только изменённые поля, info с именами полей '
      'без значений; без изменений — noChanges без записи', () async {
    final (h, f) = await _start();
    final original = await f.byName('Кафе');
    final controller = _controller(h, original.id);
    final outbox = (await h.db.select(h.db.outbox).get()).length;

    expect(await controller.save(original), CategorySave.noChanges);
    expect((await h.db.select(h.db.outbox).get()).length, outbox);

    controller
      ..setColor(CategoryColor.blue)
      ..setEmoji('🍕', from: 'grid#2');
    expect(await controller.save(original), CategorySave.saved);

    final saved = await f.byName('Кафе');
    expect(saved.color, CategoryColor.blue);
    expect(saved.emoji, '🍕');
    expect(saved.sortOrder, original.sortOrder);
    expect((await h.db.select(h.db.outbox).get()).length, outbox + 1);
    expect(h.lines('categories', Level.INFO), [
      matches(
        'category updated id=${original.id} budgetId=${f.budgetId} '
        'fields=emoji,color in \\d+ms\$',
      ),
    ]);
  });

  test('эмодзи: буква, два эмодзи и пусто отклоняются с warn, прежний '
      'эмодзи остаётся', () async {
    final (h, _) = await _start();
    final controller = _controller(h, null);
    expect(controller.setEmoji('a', from: 'keyboard'), isFalse);
    expect(controller.setEmoji('🐱🐶', from: 'keyboard'), isFalse);
    expect(controller.setEmoji(' ', from: 'keyboard'), isFalse);
    expect(_draft(h, null).emojiOf(null), '☕');
    expect(h.lines('categories', Level.WARNING), [
      contains('emoji from=keyboard rejected: emoji_invalid length=1'),
      contains('emoji from=keyboard rejected: emoji_invalid length=2'),
      contains('emoji from=keyboard rejected: emoji_empty length=0'),
    ]);
  });

  test(
    '«Другое» не правится и не удаляется: system, в базе без изменений',
    () async {
      final (h, f) = await _start();
      final other = await f.other();
      final controller = _controller(h, other.id)..setName('Прочее');

      expect(await controller.save(other), CategorySave.system);
      expect(
        await controller.delete(other, shownExpenses: 0),
        CategoryDelete.system,
      );
      expect((await f.other()).name, 'Другое');
      expect(await f.list(), hasLength(11));
    },
  );

  test('удаление «Здоровье» с 3 тратами и регулярной: число из базы 3, траты '
      'и регулярная в «Другом», info с перенесённым числом и мс', () async {
    final (h, f) = await _start();
    final health = await f.byName('Здоровье');
    final other = await f.other();
    await f.addExpenses(health.id, 3);
    await f.addExpenses((await f.byName('Кафе')).id, 2);
    final deleted = await f.expenses.create(
      budgetId: f.budgetId,
      categoryId: health.id,
      amount: const Money.rubles(5),
      spentOn: LocalDate(2026, 10, 2),
    );
    await f.expenses.delete(deleted.id);
    await h
        .read(recurringRepositoryProvider)
        .create(
          budgetId: f.budgetId,
          categoryId: health.id,
          title: 'Витамины',
          amount: const Money.rubles(900),
          dayOfMonth: 5,
          startMonth: YearMonth(2026, 10),
        );
    final controller = _controller(h, health.id);

    expect(await controller.expenseCount(health), 3);
    expect(
      await controller.delete(health, shownExpenses: 3),
      CategoryDelete.deleted,
    );

    expect((await f.list()).map((c) => c.id), isNot(contains(health.id)));
    expect(await f.expensesOf(health.id), isEmpty);
    expect(await f.expensesOf(other.id), hasLength(3));
    final rules = await h.db.select(h.db.recurringRules).get();
    expect(rules.single.categoryId, other.id);
    final info = h.lines('categories', Level.INFO);
    expect(info, hasLength(1));
    expect(
      info.single,
      matches(
        'category deleted id=${health.id} budgetId=${f.budgetId} '
        'movedExpenses=3 movedRecurring=1 shown=3 other=${other.id} '
        'in \\d+ms\$',
      ),
    );
    expect(h.lines('categories', Level.WARNING), isEmpty);
  });

  test('показали 2 траты, а к удалению их стало 3 — удаляется, warn о '
      'расхождении', () async {
    final (h, f) = await _start();
    final gifts = await f.byName('Подарки');
    await f.addExpenses(gifts.id, 3);
    final controller = _controller(h, gifts.id);

    expect(
      await controller.delete(gifts, shownExpenses: 2),
      CategoryDelete.deleted,
    );
    expect(h.lines('categories', Level.WARNING), [
      contains(
        'dialog showed 2 expenses but 3 were moved (changed while the '
        'dialog was open)',
      ),
    ]);
  });

  test('ошибка записи в базу: failed, error [categories] с id без значений '
      'параметров SQL, в базе без изменений', () async {
    final (h, f) = await _start();
    await h.db.customStatement(
      'CREATE TRIGGER categories_fail BEFORE INSERT ON categories '
      "BEGIN SELECT RAISE(ABORT, 'disk I/O error'); END",
    );
    final controller = _controller(h, null)..setName('Кот Барсик');

    expect(
      await controller.save(null, budgetId: f.budgetId),
      CategorySave.failed,
    );
    expect(_draft(h, null).busy, isFalse);
    expect(_draft(h, null).name, 'Кот Барсик');
    final errors = [
      for (final r in h.records)
        if (r.loggerName == 'categories' && r.level == Level.SEVERE) r,
    ];
    expect(errors, hasLength(1));
    expect(
      errors.single.message,
      matches(
        r'^category save failed new fields=name,emoji,color after \d+ms, '
        r'nothing saved: SqliteException',
      ),
    );
    expect(errors.single.message, contains('disk I/O error'));
    expect(errors.single.stackTrace, isNotNull);
    for (final r in h.records) {
      final text = '${r.message} ${r.error}';
      expect(text, isNot(contains('Барсик')), reason: text);
    }
    expect(await f.list(), hasLength(11));
  });

  test('ошибка при удалении: failed, error [categories] без параметров SQL, '
      'категория и траты на месте', () async {
    final (h, f) = await _start();
    final cafe = await f.byName('Кафе');
    await f.addExpenses(cafe.id, 2);
    await h.db.customStatement(
      'CREATE TRIGGER expenses_fail BEFORE UPDATE ON expenses '
      "BEGIN SELECT RAISE(ABORT, 'disk I/O error'); END",
    );
    final controller = _controller(h, cafe.id);

    expect(
      await controller.delete(cafe, shownExpenses: 2),
      CategoryDelete.failed,
    );
    expect(_draft(h, cafe.id).busy, isFalse);
    expect(await f.expensesOf(cafe.id), hasLength(2));
    expect((await f.list()).map((c) => c.id), contains(cafe.id));
    final errors = h.lines('categories', Level.SEVERE);
    expect(errors, hasLength(1));
    expect(
      errors.single,
      matches(
        'category delete failed id=${cafe.id} budgetId=${f.budgetId} '
        'after \\d+ms, nothing deleted: SqliteException',
      ),
    );
    for (final r in h.records) {
      expect('${r.message} ${r.error}', isNot(contains('Кафе')));
    }
  });
}
