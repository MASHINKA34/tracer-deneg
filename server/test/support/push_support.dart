import 'package:server/sync/sync_notifier.dart';
import 'package:shared/shared.dart';

import 'auth_support.dart';
import 'shared_budget_support.dart';

Future<ApiResponse> pushRaw(AuthHarness api, TestUser user, Object? body) =>
    api.send('POST', '/sync/push', body: body, bearer: user.accessToken);

Future<SyncPushResponse> pushAs(
  AuthHarness api,
  TestUser user,
  List<SyncChange> changes, {
  String? batchId,
}) async {
  final response = await pushRaw(
    api,
    user,
    SyncPushRequest(batchId: batchId ?? newId(), changes: changes).toJson(),
  );
  if (response.status != 200) {
    throw StateError('push for ${user.login} failed: $response');
  }
  return SyncPushResponse.fromJson(response.json);
}

DateTime minutesAgo(int minutes) =>
    normalizeInstant(DateTime.now().subtract(Duration(minutes: minutes)));

Expense expenseRecord({
  String? id,
  required String budgetId,
  required String categoryId,
  required String authorId,
  int kopecks = 64000,
  LocalDate? spentOn,
  String comment = '',
  String? recurringId,
  YearMonth? recurringMonth,
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  final at = updatedAt ?? minutesAgo(10);
  return Expense(
    id: id ?? newId(),
    budgetId: budgetId,
    categoryId: categoryId,
    amount: Money(kopecks),
    spentOn: spentOn ?? LocalDate(2026, 10, 20),
    comment: comment,
    authorId: authorId,
    recurringId: recurringId,
    recurringMonth: recurringMonth,
    createdAt: createdAt ?? at,
    updatedAt: at,
    updatedBy: authorId,
  );
}

Category categoryRecord({
  String? id,
  required String budgetId,
  required String updatedBy,
  String name = 'Кофе',
  String emoji = '☕',
  CategoryColor? color = CategoryColor.orange,
  int sortOrder = 20,
  bool isSystem = false,
  DateTime? updatedAt,
}) => Category(
  id: id ?? newId(),
  budgetId: budgetId,
  name: name,
  emoji: emoji,
  color: color,
  sortOrder: sortOrder,
  isSystem: isSystem,
  updatedAt: updatedAt ?? minutesAgo(10),
  updatedBy: updatedBy,
);

RecurringRule recurringRecord({
  String? id,
  required String budgetId,
  required String categoryId,
  required String updatedBy,
  String title = 'Интернет',
  int kopecks = 70000,
  int dayOfMonth = 5,
  YearMonth? startMonth,
  DateTime? updatedAt,
}) {
  final at = updatedAt ?? minutesAgo(10);
  return RecurringRule(
    id: id ?? newId(),
    budgetId: budgetId,
    categoryId: categoryId,
    title: title,
    amount: Money(kopecks),
    dayOfMonth: dayOfMonth,
    startMonth: startMonth ?? YearMonth(2026, 9),
    createdAt: at,
    updatedAt: at,
    updatedBy: updatedBy,
  );
}

Map<String, Object?> changeJson(SyncChange change) => change.toJson();

Map<String, Object?> pushBody(
  List<Object?> changes, {
  String? batchId,
}) => {'batchId': batchId ?? newId(), 'changes': changes};

Future<String> firstCategoryOf(AuthHarness api, String budgetId) async {
  final rows = await api.db.execute(
    r'SELECT id FROM categories WHERE budget_id = $1::uuid '
    'AND NOT is_system ORDER BY sort_order LIMIT 1',
    parameters: [budgetId],
  );
  return rows.single.first! as String;
}

Future<String> systemCategoryOf(AuthHarness api, String budgetId) async {
  final rows = await api.db.execute(
    r'SELECT id FROM categories WHERE budget_id = $1::uuid AND is_system',
    parameters: [budgetId],
  );
  return rows.single.first! as String;
}

class StoredRow {
  StoredRow(this.values);

  final Map<String, Object?> values;

  int get seq => values['seq']! as int;
  DateTime get updatedAt => values['updated_at']! as DateTime;
  DateTime? get deletedAt => values['deleted_at'] as DateTime?;
  String get budgetId => values['budget_id']! as String;
  String get updatedBy => values['updated_by']! as String;

  Object? operator [](String column) => values[column];
}

Future<StoredRow?> storedRow(AuthHarness api, String table, String id) async {
  final rows = await api.db.execute(
    'SELECT * FROM $table WHERE id = \$1::uuid',
    parameters: [id],
  );
  if (rows.isEmpty) return null;
  return StoredRow(rows.single.toColumnMap());
}

Future<int> rowCount(AuthHarness api, String table, String id) => api.count(
  'SELECT count(*)::int FROM $table WHERE id = \$1::uuid',
  [id],
);

class RecordingNotifier implements SyncNotifier {
  final List<BudgetsChanged> events = [];

  @override
  void budgetsChanged(BudgetsChanged event) => events.add(event);
}
