import '../categories/category_color.dart';
import 'json.dart';
import 'sync_record.dart';

/// Вид бюджета: личный (один на пользователя) или общий.
enum BudgetKind { personal, shared }

/// Роль участника бюджета.
enum MemberRole { owner, member }

/// Бюджет (00-spec §8).
final class Budget implements SyncRecord {
  Budget({
    required this.id,
    required this.kind,
    required this.name,
    required this.emoji,
    required this.ownerId,
    required DateTime createdAt,
    required DateTime updatedAt,
    required this.updatedBy,
    DateTime? deletedAt,
    this.seq,
  }) : createdAt = normalizeInstant(createdAt),
       updatedAt = normalizeInstant(updatedAt),
       deletedAt = deletedAt == null ? null : normalizeInstant(deletedAt);

  factory Budget.fromJson(Object? json) {
    final r = JsonReader.of(json, 'Budget');
    return Budget(
      id: r.string('id'),
      kind: r.enumByName('kind', BudgetKind.values),
      name: r.string('name'),
      emoji: r.string('emoji'),
      ownerId: r.string('ownerId'),
      createdAt: r.instant('createdAt'),
      updatedAt: r.instant('updatedAt'),
      updatedBy: r.string('updatedBy'),
      deletedAt: r.optInstant('deletedAt'),
      seq: r.optInteger('seq'),
    );
  }

  @override
  final String id;
  final BudgetKind kind;

  /// Название, 1–30 символов.
  final String name;
  final String emoji;
  final String ownerId;
  final DateTime createdAt;
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
  SyncEntity get syncEntity => SyncEntity.budget;

  Budget copyWith({
    BudgetKind? kind,
    String? name,
    String? emoji,
    String? ownerId,
    DateTime? updatedAt,
    String? updatedBy,
    Object? deletedAt = keep,
    Object? seq = keep,
  }) => Budget(
    id: id,
    kind: kind ?? this.kind,
    name: name ?? this.name,
    emoji: emoji ?? this.emoji,
    ownerId: ownerId ?? this.ownerId,
    createdAt: createdAt,
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
    'kind': kind.name,
    'name': name,
    'emoji': emoji,
    'ownerId': ownerId,
    'createdAt': encodeInstant(createdAt),
    'updatedAt': encodeInstant(updatedAt),
    'updatedBy': updatedBy,
    'deletedAt': deletedAt == null ? null : encodeInstant(deletedAt!),
    'seq': seq,
  };

  @override
  bool operator ==(Object other) =>
      other is Budget &&
      other.id == id &&
      other.kind == kind &&
      other.name == name &&
      other.emoji == emoji &&
      other.ownerId == ownerId &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      other.updatedBy == updatedBy &&
      other.deletedAt == deletedAt &&
      other.seq == seq;

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    name,
    emoji,
    ownerId,
    createdAt,
    updatedAt,
    updatedBy,
    deletedAt,
    seq,
  );

  @override
  String toString() =>
      'Budget($id ${kind.name} owner=$ownerId deleted=$isDeleted seq=$seq)';
}

/// Участник бюджета (00-spec §8).
final class BudgetMember {
  BudgetMember({
    required this.budgetId,
    required this.userId,
    required this.role,
    required this.avatarColor,
    required DateTime joinedAt,
    DateTime? leftAt,
  }) : joinedAt = normalizeInstant(joinedAt),
       leftAt = leftAt == null ? null : normalizeInstant(leftAt);

  factory BudgetMember.fromJson(Object? json) {
    final r = JsonReader.of(json, 'BudgetMember');
    return BudgetMember(
      budgetId: r.string('budgetId'),
      userId: r.string('userId'),
      role: r.enumByName('role', MemberRole.values),
      avatarColor: r.enumByName('avatarColor', CategoryColor.values),
      joinedAt: r.instant('joinedAt'),
      leftAt: r.optInstant('leftAt'),
    );
  }

  final String budgetId;
  final String userId;
  final MemberRole role;

  /// Цвет аватара — по порядку вступления.
  final CategoryColor avatarColor;
  final DateTime joinedAt;

  /// Когда вышел или исключён; `null` — участник сейчас.
  final DateTime? leftAt;

  bool get isActive => leftAt == null;

  Map<String, Object?> toJson() => {
    'budgetId': budgetId,
    'userId': userId,
    'role': role.name,
    'avatarColor': avatarColor.name,
    'joinedAt': encodeInstant(joinedAt),
    'leftAt': leftAt == null ? null : encodeInstant(leftAt!),
  };

  @override
  bool operator ==(Object other) =>
      other is BudgetMember &&
      other.budgetId == budgetId &&
      other.userId == userId &&
      other.role == role &&
      other.avatarColor == avatarColor &&
      other.joinedAt == joinedAt &&
      other.leftAt == leftAt;

  @override
  int get hashCode =>
      Object.hash(budgetId, userId, role, avatarColor, joinedAt, leftAt);

  @override
  String toString() =>
      'BudgetMember($budgetId/$userId ${role.name} active=$isActive)';
}
