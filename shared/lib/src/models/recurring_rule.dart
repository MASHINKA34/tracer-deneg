import '../money/money.dart';
import '../time/year_month.dart';
import 'json.dart';
import 'sync_record.dart';

/// Правило регулярной траты (00-spec §8, §7.5).
final class RecurringRule implements SyncRecord {
  RecurringRule({
    required this.id,
    required this.budgetId,
    required this.categoryId,
    required this.title,
    required this.amount,
    required this.dayOfMonth,
    required this.startMonth,
    required DateTime createdAt,
    required DateTime updatedAt,
    required this.updatedBy,
    DateTime? deletedAt,
    this.seq,
  }) : createdAt = normalizeInstant(createdAt),
       updatedAt = normalizeInstant(updatedAt),
       deletedAt = deletedAt == null ? null : normalizeInstant(deletedAt);

  factory RecurringRule.fromJson(Object? json) {
    final r = JsonReader.of(json, 'RecurringRule');
    return RecurringRule(
      id: r.string('id'),
      budgetId: r.string('budgetId'),
      categoryId: r.string('categoryId'),
      title: r.string('title'),
      amount: Money(r.integer('amountKopecks')),
      dayOfMonth: r.integer('dayOfMonth'),
      startMonth: r.month('startMonth'),
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

  /// Название, 1–40 символов; становится комментарием созданных трат.
  final String title;
  final Money amount;

  /// День списания D (1–31); в коротком месяце — последний день.
  final int dayOfMonth;

  /// Первый месяц, за который создаётся трата.
  final YearMonth startMonth;
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
  SyncEntity get syncEntity => SyncEntity.recurring;

  RecurringRule copyWith({
    String? budgetId,
    String? categoryId,
    String? title,
    Money? amount,
    int? dayOfMonth,
    YearMonth? startMonth,
    DateTime? updatedAt,
    String? updatedBy,
    Object? deletedAt = keep,
    Object? seq = keep,
  }) => RecurringRule(
    id: id,
    budgetId: budgetId ?? this.budgetId,
    categoryId: categoryId ?? this.categoryId,
    title: title ?? this.title,
    amount: amount ?? this.amount,
    dayOfMonth: dayOfMonth ?? this.dayOfMonth,
    startMonth: startMonth ?? this.startMonth,
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
    'title': title,
    'amountKopecks': amount.kopecks,
    'dayOfMonth': dayOfMonth,
    'startMonth': startMonth.toJson(),
    'createdAt': encodeInstant(createdAt),
    'updatedAt': encodeInstant(updatedAt),
    'updatedBy': updatedBy,
    'deletedAt': deletedAt == null ? null : encodeInstant(deletedAt!),
    'seq': seq,
  };

  @override
  bool operator ==(Object other) =>
      other is RecurringRule &&
      other.id == id &&
      other.budgetId == budgetId &&
      other.categoryId == categoryId &&
      other.title == title &&
      other.amount == amount &&
      other.dayOfMonth == dayOfMonth &&
      other.startMonth == startMonth &&
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
    title,
    amount,
    dayOfMonth,
    startMonth,
    createdAt,
    updatedAt,
    updatedBy,
    deletedAt,
    seq,
  );

  /// Без названия и суммы: их нельзя писать в лог на уровне info.
  @override
  String toString() =>
      'RecurringRule($id budget=$budgetId day=$dayOfMonth from=$startMonth '
      'deleted=$isDeleted)';
}
