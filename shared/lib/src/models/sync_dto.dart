import 'budget.dart';
import 'category.dart';
import 'expense.dart';
import 'json.dart';
import 'member_profile.dart';
import 'recurring_rule.dart';
import 'sync_record.dart';

/// Сколько изменений максимум в одной пачке `/sync/push` (00-spec §10).
const int maxPushBatchSize = 200;

/// Размер страницы `/sync/pull` по умолчанию и максимум (00-spec §9).
const int pullPageSize = 500;

/// Операция изменения.
enum SyncOp { upsert, delete }

/// Одно изменение в `/sync/push`: `{entity, op, id, data, updatedAt}`.
/// У `delete` нет `data`.
final class SyncChange {
  SyncChange._({
    required this.entity,
    required this.op,
    required this.id,
    required DateTime updatedAt,
    this.data,
  }) : updatedAt = normalizeInstant(updatedAt);

  /// Создание или правка записи [record].
  factory SyncChange.upsert(SyncRecord record) => SyncChange._(
    entity: record.syncEntity,
    op: SyncOp.upsert,
    id: record.id,
    updatedAt: record.updatedAt,
    data: record.toJson(),
  );

  /// Удаление записи [id] (надгробие с моментом [updatedAt]).
  factory SyncChange.delete({
    required SyncEntity entity,
    required String id,
    required DateTime updatedAt,
  }) => SyncChange._(
    entity: entity,
    op: SyncOp.delete,
    id: id,
    updatedAt: updatedAt,
  );

  factory SyncChange.fromJson(Object? json) {
    final r = JsonReader.of(json, 'SyncChange');
    final op = r.enumByName('op', SyncOp.values);
    final data = r.optObject('data');
    if (op == SyncOp.upsert && data == null) {
      throw const FormatException('SyncChange.data: required for upsert');
    }
    if (op == SyncOp.delete && data != null) {
      throw const FormatException('SyncChange.data: must be absent for delete');
    }
    return SyncChange._(
      entity: r.enumByName('entity', SyncEntity.values),
      op: op,
      id: r.string('id'),
      updatedAt: r.instant('updatedAt'),
      data: data,
    );
  }

  final SyncEntity entity;
  final SyncOp op;
  final String id;
  final DateTime updatedAt;

  /// JSON записи для `upsert`.
  final Map<String, Object?>? data;

  /// Запись из [data] (только для `upsert`). Тип по [entity]; `id` внутри
  /// должен совпадать с [id], иначе [FormatException].
  SyncRecord decodeRecord() {
    final json = data;
    if (json == null) {
      throw StateError('SyncChange $id: ${op.name} has no data');
    }
    final SyncRecord record = switch (entity) {
      SyncEntity.budget => Budget.fromJson(json),
      SyncEntity.category => Category.fromJson(json),
      SyncEntity.expense => Expense.fromJson(json),
      SyncEntity.recurring => RecurringRule.fromJson(json),
    };
    if (record.id != id) {
      throw FormatException(
        'SyncChange: data.id ${record.id} does not match id $id',
      );
    }
    return record;
  }

  Map<String, Object?> toJson() => {
    'entity': entity.name,
    'op': op.name,
    'id': id,
    'data': ?data,
    'updatedAt': encodeInstant(updatedAt),
  };

  @override
  String toString() => 'SyncChange(${entity.name} ${op.name} $id)';
}

/// Тело `POST /sync/push`. Повтор с тем же [batchId] даёт тот же ответ.
final class SyncPushRequest {
  SyncPushRequest({required this.batchId, required List<SyncChange> changes})
    : changes = List.unmodifiable(changes);

  factory SyncPushRequest.fromJson(Object? json) {
    final r = JsonReader.of(json, 'SyncPushRequest');
    return SyncPushRequest(
      batchId: r.string('batchId'),
      changes: r.objects('changes', SyncChange.fromJson),
    );
  }

  final String batchId;
  final List<SyncChange> changes;

  Map<String, Object?> toJson() => {
    'batchId': batchId,
    'changes': [for (final c in changes) c.toJson()],
  };

  @override
  String toString() => 'SyncPushRequest($batchId, ${changes.length} changes)';
}

/// Отклонённое изменение: id записи и код причины (коды API/валидации).
final class SyncRejection {
  const SyncRejection({required this.id, required this.code});

  factory SyncRejection.fromJson(Object? json) {
    final r = JsonReader.of(json, 'SyncRejection');
    return SyncRejection(id: r.string('id'), code: r.string('code'));
  }

  final String id;
  final String code;

  Map<String, Object?> toJson() => {'id': id, 'code': code};

  @override
  bool operator ==(Object other) =>
      other is SyncRejection && other.id == id && other.code == code;

  @override
  int get hashCode => Object.hash(id, code);

  @override
  String toString() => 'SyncRejection($id $code)';
}

/// Ответ `POST /sync/push`: id применённых изменений, отклонённые и курсор.
final class SyncPushResponse {
  SyncPushResponse({
    required List<String> applied,
    required List<SyncRejection> rejected,
    required this.cursor,
  }) : applied = List.unmodifiable(applied),
       rejected = List.unmodifiable(rejected);

  factory SyncPushResponse.fromJson(Object? json) {
    final r = JsonReader.of(json, 'SyncPushResponse');
    return SyncPushResponse(
      applied: r.strings('applied'),
      rejected: r.objects('rejected', SyncRejection.fromJson),
      cursor: r.integer('cursor'),
    );
  }

  final List<String> applied;
  final List<SyncRejection> rejected;
  final int cursor;

  Map<String, Object?> toJson() => {
    'applied': applied,
    'rejected': [for (final x in rejected) x.toJson()],
    'cursor': cursor,
  };

  @override
  String toString() =>
      'SyncPushResponse(applied=${applied.length} '
      'rejected=${rejected.length} cursor=$cursor)';
}

/// Параметры `GET /sync/pull?cursor=N&limit=500`.
final class SyncPullQuery {
  SyncPullQuery({this.cursor = 0, this.limit = pullPageSize}) {
    if (cursor < 0) {
      throw ArgumentError.value(cursor, 'cursor', 'must not be negative');
    }
    RangeError.checkValueInInterval(limit, 1, pullPageSize, 'limit');
  }

  /// Разбор query-параметров; без параметров — cursor 0, limit 500.
  /// Не числа и значения вне диапазона — [FormatException].
  factory SyncPullQuery.fromQueryParameters(Map<String, String> query) {
    int read(String key, int fallback) {
      final text = query[key];
      if (text == null) return fallback;
      final value = int.tryParse(text);
      if (value == null) {
        throw FormatException('SyncPullQuery.$key: expected int', text);
      }
      return value;
    }

    final cursor = read('cursor', 0);
    final limit = read('limit', pullPageSize);
    try {
      return SyncPullQuery(cursor: cursor, limit: limit);
    } on ArgumentError catch (e) {
      throw FormatException('SyncPullQuery: ${e.message}');
    }
  }

  final int cursor;
  final int limit;

  Map<String, String> toQueryParameters() => {
    'cursor': '$cursor',
    'limit': '$limit',
  };

  @override
  bool operator ==(Object other) =>
      other is SyncPullQuery && other.cursor == cursor && other.limit == limit;

  @override
  int get hashCode => Object.hash(cursor, limit);

  @override
  String toString() => 'SyncPullQuery(cursor=$cursor limit=$limit)';
}

/// Ответ `GET /sync/pull`: всё изменённое после курсора в бюджетах
/// пользователя, включая надгробия.
final class SyncPullResponse {
  SyncPullResponse({
    List<Budget> budgets = const [],
    List<BudgetMember> members = const [],
    List<MemberProfile> profiles = const [],
    List<Category> categories = const [],
    List<Expense> expenses = const [],
    List<RecurringRule> recurring = const [],
    List<String> removedBudgetIds = const [],
    required this.cursor,
    required this.hasMore,
  }) : budgets = List.unmodifiable(budgets),
       members = List.unmodifiable(members),
       profiles = List.unmodifiable(profiles),
       categories = List.unmodifiable(categories),
       expenses = List.unmodifiable(expenses),
       recurring = List.unmodifiable(recurring),
       removedBudgetIds = List.unmodifiable(removedBudgetIds);

  factory SyncPullResponse.fromJson(Object? json) {
    final r = JsonReader.of(json, 'SyncPullResponse');
    return SyncPullResponse(
      budgets: r.objects('budgets', Budget.fromJson),
      members: r.objects('members', BudgetMember.fromJson),
      profiles: r.objects('profiles', MemberProfile.fromJson),
      categories: r.objects('categories', Category.fromJson),
      expenses: r.objects('expenses', Expense.fromJson),
      recurring: r.objects('recurring', RecurringRule.fromJson),
      removedBudgetIds: r.strings('removedBudgetIds'),
      cursor: r.integer('cursor'),
      hasMore: r.boolean('hasMore'),
    );
  }

  final List<Budget> budgets;
  final List<BudgetMember> members;
  final List<MemberProfile> profiles;
  final List<Category> categories;
  final List<Expense> expenses;
  final List<RecurringRule> recurring;

  /// Бюджеты, где пользователь больше не участник (исключён или удалены).
  final List<String> removedBudgetIds;
  final int cursor;
  final bool hasMore;

  /// Сколько сущностей в странице — для логов.
  int get totalCount =>
      budgets.length +
      members.length +
      profiles.length +
      categories.length +
      expenses.length +
      recurring.length +
      removedBudgetIds.length;

  Map<String, Object?> toJson() => {
    'budgets': [for (final x in budgets) x.toJson()],
    'members': [for (final x in members) x.toJson()],
    'profiles': [for (final x in profiles) x.toJson()],
    'categories': [for (final x in categories) x.toJson()],
    'expenses': [for (final x in expenses) x.toJson()],
    'recurring': [for (final x in recurring) x.toJson()],
    'removedBudgetIds': removedBudgetIds,
    'cursor': cursor,
    'hasMore': hasMore,
  };

  @override
  String toString() =>
      'SyncPullResponse(budgets=${budgets.length} members=${members.length} '
      'profiles=${profiles.length} categories=${categories.length} '
      'expenses=${expenses.length} recurring=${recurring.length} '
      'removed=${removedBudgetIds.length} cursor=$cursor hasMore=$hasMore)';
}
