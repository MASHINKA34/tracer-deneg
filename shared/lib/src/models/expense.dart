import '../money/money.dart';
import '../time/local_date.dart';
import '../time/year_month.dart';
import 'json.dart';
import 'sync_record.dart';

/// Трата (00-spec §8).
final class Expense implements SyncRecord {
  Expense({
    required this.id,
    required this.budgetId,
    required this.categoryId,
    required this.amount,
    required this.spentOn,
    this.comment = '',
    required this.authorId,
    this.recurringId,
    this.recurringMonth,
    required DateTime createdAt,
    required DateTime updatedAt,
    required this.updatedBy,
    DateTime? deletedAt,
    this.seq,
  }) : createdAt = normalizeInstant(createdAt),
       updatedAt = normalizeInstant(updatedAt),
       deletedAt = deletedAt == null ? null : normalizeInstant(deletedAt);

  factory Expense.fromJson(Object? json) {
    final r = JsonReader.of(json, 'Expense');
    return Expense(
      id: r.string('id'),
      budgetId: r.string('budgetId'),
      categoryId: r.string('categoryId'),
      amount: Money(r.integer('amountKopecks')),
      spentOn: r.date('spentOn'),
      comment: r.optString('comment') ?? '',
      authorId: r.string('authorId'),
      recurringId: r.optString('recurringId'),
      recurringMonth: r.optMonth('recurringMonth'),
      createdAt: r.instant('createdAt'),
      updatedAt: r.instant('updatedAt'),
      updatedBy: r.string('updatedBy'),
      deletedAt: r.optInstant('deletedAt'),
      seq: r.optInteger('seq'),
    );
  }

  @override
  final String id;
  final String budgetId;
  final String categoryId;

  /// Сумма, 0,01–10 000 000,00 ₽.
  final Money amount;

  /// Дата траты — календарная дата телефона, где её внесли.
  final LocalDate spentOn;

  /// Комментарий, 0–100 символов (пустая строка — нет комментария).
  final String comment;
  final String authorId;

  /// Регулярная, создавшая трату, и её месяц (`YYYY-MM`).
  final String? recurringId;
  final YearMonth? recurringMonth;
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
  SyncEntity get syncEntity => SyncEntity.expense;

  Expense copyWith({
    String? budgetId,
    String? categoryId,
    Money? amount,
    LocalDate? spentOn,
    String? comment,
    DateTime? updatedAt,
    String? updatedBy,
    Object? deletedAt = keep,
    Object? seq = keep,
  }) => Expense(
    id: id,
    budgetId: budgetId ?? this.budgetId,
    categoryId: categoryId ?? this.categoryId,
    amount: amount ?? this.amount,
    spentOn: spentOn ?? this.spentOn,
    comment: comment ?? this.comment,
    authorId: authorId,
    recurringId: recurringId,
    recurringMonth: recurringMonth,
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
    'budgetId': budgetId,
    'categoryId': categoryId,
    'amountKopecks': amount.kopecks,
    'spentOn': spentOn.toJson(),
    'comment': comment,
    'authorId': authorId,
    'recurringId': recurringId,
    'recurringMonth': recurringMonth?.toJson(),
    'createdAt': encodeInstant(createdAt),
    'updatedAt': encodeInstant(updatedAt),
    'updatedBy': updatedBy,
    'deletedAt': deletedAt == null ? null : encodeInstant(deletedAt!),
    'seq': seq,
  };

  @override
  bool operator ==(Object other) =>
      other is Expense &&
      other.id == id &&
      other.budgetId == budgetId &&
      other.categoryId == categoryId &&
      other.amount == amount &&
      other.spentOn == spentOn &&
      other.comment == comment &&
      other.authorId == authorId &&
      other.recurringId == recurringId &&
      other.recurringMonth == recurringMonth &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      other.updatedBy == updatedBy &&
      other.deletedAt == deletedAt &&
      other.seq == seq;

  @override
  int get hashCode => Object.hash(
    id,
    budgetId,
    categoryId,
    amount,
    spentOn,
    comment,
    authorId,
    recurringId,
    recurringMonth,
    createdAt,
    updatedAt,
    updatedBy,
    deletedAt,
    seq,
  );

  /// Без суммы и комментария: их нельзя писать в лог на уровне info.
  @override
  String toString() =>
      'Expense($id budget=$budgetId on $spentOn '
      'recurring=${recurringId ?? '-'} deleted=$isDeleted)';
}
