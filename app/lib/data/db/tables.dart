import 'package:drift/drift.dart';
import 'package:shared/shared.dart';

import 'converters.dart';

mixin SyncColumns on Table {
  TextColumn get updatedAt => text().map(const InstantConverter())();
  TextColumn get updatedBy => text()();
  TextColumn get deletedAt => text().map(const InstantConverter()).nullable()();
  IntColumn get serverSeq => integer().nullable()();
}

@DataClassName('BudgetEntry')
class Budgets extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get kind => textEnum<BudgetKind>()();
  TextColumn get name => text()();
  TextColumn get emoji => text()();
  TextColumn get ownerId => text()();
  TextColumn get createdAt => text().map(const InstantConverter())();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('BudgetMemberEntry')
class BudgetMembers extends Table {
  TextColumn get budgetId => text()();
  TextColumn get userId => text()();
  TextColumn get role => textEnum<MemberRole>()();
  TextColumn get avatarColor => textEnum<CategoryColor>()();
  TextColumn get joinedAt => text().map(const InstantConverter())();
  TextColumn get leftAt => text().map(const InstantConverter()).nullable()();
  TextColumn get updatedAt => text().map(const InstantConverter()).nullable()();
  TextColumn get updatedBy => text().nullable()();
  TextColumn get deletedAt => text().map(const InstantConverter()).nullable()();
  IntColumn get serverSeq => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {budgetId, userId};
}

@DataClassName('CategoryEntry')
@TableIndex(name: 'categories_budget_sort', columns: {#budgetId, #sortOrder})
class Categories extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get budgetId => text()();
  TextColumn get name => text()();
  TextColumn get nameSearch => text()();
  TextColumn get emoji => text()();
  TextColumn get color => textEnum<CategoryColor>().nullable()();
  IntColumn get sortOrder => integer()();
  BoolColumn get isSystem => boolean()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('ExpenseEntry')
@TableIndex(name: 'expenses_budget_spent_on', columns: {#budgetId, #spentOn})
@TableIndex(name: 'expenses_budget_deleted', columns: {#budgetId, #deletedAt})
@TableIndex(
  name: 'expenses_recurring_month',
  columns: {#recurringId, #recurringMonth},
)
class Expenses extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get budgetId => text()();
  TextColumn get categoryId => text()();
  IntColumn get amountKopecks => integer()();
  TextColumn get spentOn => text().map(const LocalDateConverter())();
  TextColumn get comment => text()();
  TextColumn get commentSearch => text()();
  TextColumn get authorId => text()();
  TextColumn get recurringId => text().nullable()();
  TextColumn get recurringMonth =>
      text().map(const YearMonthConverter()).nullable()();
  TextColumn get createdAt => text().map(const InstantConverter())();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('RecurringRuleEntry')
class RecurringRules extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get budgetId => text()();
  TextColumn get categoryId => text()();
  TextColumn get title => text()();
  IntColumn get amountKopecks => integer()();
  IntColumn get dayOfMonth => integer()();
  TextColumn get startMonth => text().map(const YearMonthConverter())();
  TextColumn get createdAt => text().map(const InstantConverter())();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('MemberProfileEntry')
class MemberProfiles extends Table {
  TextColumn get userId => text()();
  TextColumn get displayName => text()();
  TextColumn get avatarColor => textEnum<CategoryColor>()();
  IntColumn get birthdayMonth => integer().nullable()();
  IntColumn get birthdayDay => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {userId};
}

@DataClassName('OutboxEntry')
@TableIndex(name: 'outbox_not_before', columns: {#notBefore, #id})
class Outbox extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entity => textEnum<SyncEntity>()();
  TextColumn get entityId => text()();
  TextColumn get op => textEnum<SyncOp>()();
  TextColumn get payload => text().nullable()();
  TextColumn get createdAt => text().map(const InstantConverter())();
  TextColumn get notBefore => text().map(const InstantConverter()).nullable()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
}

@DataClassName('SyncStateEntry')
class SyncStates extends Table {
  @override
  String get tableName => 'sync_state';

  IntColumn get id => integer()();
  IntColumn get cursor => integer().withDefault(const Constant(0))();
  TextColumn get lastSyncAt =>
      text().map(const InstantConverter()).nullable()();
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => ['CHECK (id = 0)'];
}

@DataClassName('LocalPrefEntry')
class LocalPrefs extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}
