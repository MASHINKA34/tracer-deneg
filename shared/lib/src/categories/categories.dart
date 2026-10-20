import '../models/category.dart';
import 'category_color.dart';

/// Готовая категория, которая создаётся в каждом новом бюджете.
final class PresetCategory {
  const PresetCategory({
    required this.emoji,
    required this.name,
    required this.color,
    required this.sortOrder,
    this.isSystem = false,
  });

  final String emoji;
  final String name;

  /// `null` — у системной «Другое».
  final CategoryColor? color;
  final int sortOrder;
  final bool isSystem;

  @override
  String toString() => 'PresetCategory($sortOrder $emoji $name)';
}

/// 10 готовых категорий и «Другое» в этом порядке (00-spec §7.4).
const List<PresetCategory> presetCategories = [
  PresetCategory(
    emoji: '🛒',
    name: 'Продукты',
    color: CategoryColor.green,
    sortOrder: 0,
  ),
  PresetCategory(
    emoji: '☕',
    name: 'Кафе',
    color: CategoryColor.orange,
    sortOrder: 1,
  ),
  PresetCategory(
    emoji: '🚇',
    name: 'Транспорт',
    color: CategoryColor.yellow,
    sortOrder: 2,
  ),
  PresetCategory(
    emoji: '🏠',
    name: 'Дом',
    color: CategoryColor.blue,
    sortOrder: 3,
  ),
  PresetCategory(
    emoji: '💊',
    name: 'Здоровье',
    color: CategoryColor.red,
    sortOrder: 4,
  ),
  PresetCategory(
    emoji: '🏋️',
    name: 'Спорт',
    color: CategoryColor.indigo,
    sortOrder: 5,
  ),
  PresetCategory(
    emoji: '🎮',
    name: 'Развлечения',
    color: CategoryColor.pink,
    sortOrder: 6,
  ),
  PresetCategory(
    emoji: '👕',
    name: 'Одежда',
    color: CategoryColor.purple,
    sortOrder: 7,
  ),
  PresetCategory(
    emoji: '📱',
    name: 'Связь',
    color: CategoryColor.teal,
    sortOrder: 8,
  ),
  PresetCategory(
    emoji: '🎁',
    name: 'Подарки',
    color: CategoryColor.rose,
    sortOrder: 9,
  ),
  PresetCategory(
    emoji: '📦',
    name: 'Другое',
    color: null,
    sortOrder: 10,
    isSystem: true,
  ),
];

/// Категории нового бюджета [budgetId] из [presetCategories]. id даёт
/// [newId] (UUID v4 у того, кто создаёт бюджет).
List<Category> buildPresetCategories({
  required String budgetId,
  required String updatedBy,
  required DateTime now,
  required String Function() newId,
}) => [
  for (final preset in presetCategories)
    Category(
      id: newId(),
      budgetId: budgetId,
      name: preset.name,
      emoji: preset.emoji,
      color: preset.color,
      sortOrder: preset.sortOrder,
      isSystem: preset.isSystem,
      updatedAt: now,
      updatedBy: updatedBy,
    ),
];

/// Порядок категорий в списках: системная «Другое» всегда последняя,
/// остальные по `sortOrder`, при равенстве — по id (стабильно на всех
/// устройствах).
int compareCategories(Category a, Category b) {
  if (a.isSystem != b.isSystem) return a.isSystem ? 1 : -1;
  final byOrder = a.sortOrder.compareTo(b.sortOrder);
  return byOrder != 0 ? byOrder : a.id.compareTo(b.id);
}

/// `sortOrder` для новой категории: после всех несистемных (удалённые тоже
/// учитываются — порядок не переиспользуется), перед «Другое».
int nextCategorySortOrder(Iterable<Category> existing) {
  var max = -1;
  for (final category in existing) {
    if (!category.isSystem && category.sortOrder > max) {
      max = category.sortOrder;
    }
  }
  return max + 1;
}
