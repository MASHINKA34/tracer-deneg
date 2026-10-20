import '../categories/category_color.dart';
import 'json.dart';
import 'sync_record.dart';

/// Категория трат бюджета (00-spec §8, §7.4).
final class Category implements SyncRecord {
  Category({
    required this.id,
    required this.budgetId,
    required this.name,
    required this.emoji,
    required this.color,
    required this.sortOrder,
    required this.isSystem,
    required DateTime updatedAt,
    required this.updatedBy,
    DateTime? deletedAt,
    this.seq,
  }) : updatedAt = normalizeInstant(updatedAt),
       deletedAt = deletedAt == null ? null : normalizeInstant(deletedAt);

  factory Category.fromJson(Object? json) {
    final r = JsonReader.of(json, 'Category');
    return Category(
      id: r.string('id'),
      budgetId: r.string('budgetId'),
      name: r.string('name'),
      emoji: r.string('emoji'),
      color: r.optEnumByName('color', CategoryColor.values),
      sortOrder: r.integer('sortOrder'),
      isSystem: r.boolean('isSystem'),
      updatedAt: r.instant('updatedAt'),
      updatedBy: r.string('updatedBy'),
      deletedAt: r.optInstant('deletedAt'),
      seq: r.optInteger('seq'),
    );
  }

  @override
  final String id;
  final String budgetId;

  /// Название, 1–24 символа.
  final String name;
  final String emoji;

  /// Цвет; `null` только у системной «Другое» (фон `bg/surface-3`).
  final CategoryColor? color;

  /// Порядок в списках (системная всё равно последняя).
  final int sortOrder;

  /// Системная «Другое»: нельзя удалить и переименовать.
  final bool isSystem;
  @override
  final DateTime updatedAt;
  @override
  final String updatedBy;
  @override
  final DateTime? deletedAt;
  @override
  final int? seq;

  @override
  bool get isDeleted => deletedAt != null;

  @override
  SyncEntity get syncEntity => SyncEntity.category;

  Category copyWith({
    String? name,
    String? emoji,
    Object? color = keep,
    int? sortOrder,
    DateTime? updatedAt,
    String? updatedBy,
    Object? deletedAt = keep,
    Object? seq = keep,
  }) => Category(
    id: id,
    budgetId: budgetId,
    name: name ?? this.name,
    emoji: emoji ?? this.emoji,
    color: identical(color, keep) ? this.color : color as CategoryColor?,
    sortOrder: sortOrder ?? this.sortOrder,
    isSystem: isSystem,
    updatedAt: updatedAt ?? this.updatedAt,
    updatedBy: updatedBy ?? this.updatedBy,
    deletedAt: identical(deletedAt, keep)
        ? this.deletedAt
        : deletedAt as DateTime?,
    seq: identical(seq, keep) ? this.seq : seq as int?,
  );

  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'budgetId': budgetId,
    'name': name,
    'emoji': emoji,
    'color': color?.name,
    'sortOrder': sortOrder,
    'isSystem': isSystem,
    'updatedAt': encodeInstant(updatedAt),
    'updatedBy': updatedBy,
    'deletedAt': deletedAt == null ? null : encodeInstant(deletedAt!),
    'seq': seq,
  };

  @override
  bool operator ==(Object other) =>
      other is Category &&
      other.id == id &&
      other.budgetId == budgetId &&
      other.name == name &&
      other.emoji == emoji &&
      other.color == color &&
      other.sortOrder == sortOrder &&
      other.isSystem == isSystem &&
      other.updatedAt == updatedAt &&
      other.updatedBy == updatedBy &&
      other.deletedAt == deletedAt &&
      other.seq == seq;

  @override
  int get hashCode => Object.hash(
    id,
    budgetId,
    name,
    emoji,
    color,
    sortOrder,
    isSystem,
    updatedAt,
    updatedBy,
    deletedAt,
    seq,
  );

  @override
  String toString() =>
      'Category($id budget=$budgetId order=$sortOrder system=$isSystem '
      'deleted=$isDeleted)';
}
