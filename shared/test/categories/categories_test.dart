import 'package:shared/shared.dart';
import 'package:test/test.dart';

Category cat(String id, int order, {bool system = false}) => Category(
  id: id,
  budgetId: 'b1',
  name: id,
  emoji: '🛒',
  color: system ? null : CategoryColor.green,
  sortOrder: order,
  isSystem: system,
  updatedAt: DateTime.utc(2026, 10, 1),
  updatedBy: 'u1',
);

void main() {
  group('presetCategories', () {
    test('10 готовых + «Другое» в порядке §7.4', () {
      expect(
        [
          for (final p in presetCategories)
            '${p.sortOrder} ${p.emoji} ${p.name} ${p.color?.name}',
        ],
        [
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
        ],
      );
      expect(presetCategories.where((p) => p.isSystem).single.name, 'Другое');
      expect(presetCategories.last.isSystem, isTrue);
      expect(
        presetCategories.first.toString(),
        'PresetCategory(0 🛒 Продукты)',
      );
    });

    test('эмодзи Спорта — с вариантом эмодзи U+FE0F', () {
      expect(presetCategories[5].emoji, '\u{1F3CB}\u{FE0F}');
    });

    test('все готовые проходят валидацию', () {
      for (final p in presetCategories) {
        expect(validateCategoryName(p.name), isNull, reason: p.name);
        expect(validateEmoji(p.emoji), isNull, reason: p.emoji);
      }
    });

    test('10 ключей цветов', () {
      expect(CategoryColor.values.map((c) => c.name), [
        'green',
        'orange',
        'yellow',
        'blue',
        'red',
        'purple',
        'pink',
        'teal',
        'indigo',
        'rose',
      ]);
      expect(CategoryColor.fromKey('teal'), CategoryColor.teal);
      expect(CategoryColor.fromKey('black'), isNull);
    });
  });

  group('buildPresetCategories', () {
    test('копия набора для нового бюджета с новыми id', () {
      var counter = 0;
      final now = DateTime.utc(2026, 10, 19, 12);
      final categories = buildPresetCategories(
        budgetId: 'budget-1',
        updatedBy: 'user-1',
        now: now,
        newId: () => 'id-${counter++}',
      );
      expect(categories, hasLength(11));
      expect(categories.map((c) => c.id).toSet(), hasLength(11));
      expect(categories.first.id, 'id-0');
      expect(categories.every((c) => c.budgetId == 'budget-1'), isTrue);
      expect(categories.every((c) => c.updatedBy == 'user-1'), isTrue);
      expect(categories.every((c) => c.updatedAt == now), isTrue);
      expect(categories.every((c) => !c.isDeleted), isTrue);
      final other = categories.last;
      expect(other.isSystem, isTrue);
      expect(other.color, isNull);
    });
  });

  group('порядок категорий', () {
    test('«Другое» всегда последняя, остальные по sortOrder, затем по id', () {
      final sorted = [
        cat('other', 10, system: true),
        cat('b', 11),
        cat('a', 0),
        cat('c', 11),
        cat('z', 5),
      ]..sort(compareCategories);
      expect(sorted.map((c) => c.id), ['a', 'z', 'b', 'c', 'other']);
    });

    test('новая категория — после всех несистемных', () {
      expect(
        nextCategorySortOrder([cat('a', 0), cat('o', 10, system: true)]),
        1,
      );
      expect(nextCategorySortOrder([cat('a', 0), cat('b', 12)]), 13);
      expect(nextCategorySortOrder([]), 0);
    });
  });
}
