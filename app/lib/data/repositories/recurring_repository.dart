import 'package:drift/drift.dart';
import 'package:shared/shared.dart';

import '../current_user.dart';
import '../db/app_database.dart';
import 'outbox_queue.dart';
import 'records.dart';
import 'repository_errors.dart';
import 'repository_writer.dart';

abstract interface class RecurringRepository {
  Stream<List<RecurringRule>> watchByBudget(String budgetId);

  Stream<RecurringRule?> watchById(String id);

  Stream<RecurringRule?> watchByIdWithDeleted(String id);

  Future<List<RecurringRule>> liveRulesOfLiveBudgets();

  Future<RecurringRule> create({
    required String budgetId,
    required String categoryId,
    required String title,
    required Money amount,
    required int dayOfMonth,
    required YearMonth startMonth,
  });

  Future<RecurringRule> update(
    String id, {
    String? categoryId,
    String? title,
    Money? amount,
    int? dayOfMonth,
    YearMonth? startMonth,
  });

  Future<RecurringRule> delete(String id);

  Future<void> applyFromServer(Iterable<RecurringRule> rules);
}

final class DriftRecurringRepository implements RecurringRepository {
  DriftRecurringRepository(
    this._db, {
    required CurrentUser currentUser,
    required OutboxQueue outbox,
    Now now = DateTime.now,
  }) : _writer = RepositoryWriter(
         _db,
         outbox: outbox,
         currentUser: currentUser,
         now: now,
       );

  static const String _entity = 'recurring';

  final AppDatabase _db;
  final RepositoryWriter _writer;

  OutboxQueue get _outbox => _writer.outbox;

  @override
  Stream<List<RecurringRule>> watchByBudget(String budgetId) => _writer.watch(
    _entity,
    'budget=$budgetId',
    (_db.select(_db.recurringRules)
          ..where((r) => r.budgetId.equals(budgetId) & r.deletedAt.isNull())
          ..orderBy([
            (r) => OrderingTerm.asc(r.dayOfMonth),
            (r) => OrderingTerm.asc(r.createdAt),
            (r) => OrderingTerm.asc(r.id),
          ]))
        .watch()
        .map((rows) => [for (final r in rows) recurringFromRow(r)]),
  );

  @override
  Stream<RecurringRule?> watchById(String id) => _writer.watch(
    _entity,
    'id=$id',
    (_db.select(_db.recurringRules)
          ..where((r) => r.id.equals(id) & r.deletedAt.isNull()))
        .watchSingleOrNull()
        .map((r) => r == null ? null : recurringFromRow(r)),
  );

  @override
  Stream<RecurringRule?> watchByIdWithDeleted(String id) => _writer.watch(
    _entity,
    'id=$id with deleted',
    (_db.select(_db.recurringRules)..where((r) => r.id.equals(id)))
        .watchSingleOrNull()
        .map((r) => r == null ? null : recurringFromRow(r)),
  );

  @override
  Future<List<RecurringRule>> liveRulesOfLiveBudgets() async {
    final rules = _db.recurringRules;
    final budgets = _db.budgets;
    final query =
        _db.select(rules).join([
            innerJoin(budgets, budgets.id.equalsExp(rules.budgetId)),
          ])
          ..where(rules.deletedAt.isNull() & budgets.deletedAt.isNull())
          ..orderBy([
            OrderingTerm.asc(rules.budgetId),
            OrderingTerm.asc(rules.dayOfMonth),
            OrderingTerm.asc(rules.createdAt),
            OrderingTerm.asc(rules.id),
          ]);
    final rows = await query.get();
    return [for (final row in rows) recurringFromRow(row.readTable(rules))];
  }

  Future<RecurringRule> _live(String id) async {
    final row = await (_db.select(
      _db.recurringRules,
    )..where((r) => r.id.equals(id) & r.deletedAt.isNull())).getSingleOrNull();
    if (row == null) {
      throw RepositoryException(
        RepositoryFailure.notFound,
        entity: _entity,
        id: id,
      );
    }
    return recurringFromRow(row);
  }

  void _validate(RecurringRule r) {
    checkValid(validateRecurringTitle(r.title), entity: _entity, id: r.id);
    checkValid(validateAmount(r.amount), entity: _entity, id: r.id);
    checkValid(validateDayOfMonth(r.dayOfMonth), entity: _entity, id: r.id);
  }

  String _describe(RecurringRule r, String outbox) =>
      'budget=${r.budgetId} category=${r.categoryId} day=${r.dayOfMonth} '
      'from=${r.startMonth} amount=${r.amount.kopecks} outbox=$outbox';

  @override
  Future<RecurringRule> create({
    required String budgetId,
    required String categoryId,
    required String title,
    required Money amount,
    required int dayOfMonth,
    required YearMonth startMonth,
  }) {
    final id = newId();
    late int outboxId;
    return _writer.edit(
      _entity,
      'create',
      id: id,
      describe: (r) => _describe(r, 'upsert#$outboxId'),
      body: (c) async {
        final rule = RecurringRule(
          id: id,
          budgetId: budgetId,
          categoryId: categoryId,
          title: normalizeText(title),
          amount: amount,
          dayOfMonth: dayOfMonth,
          startMonth: startMonth,
          createdAt: c.now,
          updatedAt: c.now,
          updatedBy: c.userId,
        );
        _validate(rule);
        await _db.into(_db.recurringRules).insert(recurringToRow(rule));
        outboxId = await _outbox.enqueueUpsert(rule);
        return rule;
      },
    );
  }

  @override
  Future<RecurringRule> update(
    String id, {
    String? categoryId,
    String? title,
    Money? amount,
    int? dayOfMonth,
    YearMonth? startMonth,
  }) {
    late int outboxId;
    return _writer.edit(
      _entity,
      'update',
      id: id,
      describe: (r) => _describe(r, 'upsert#$outboxId'),
      body: (c) async {
        final current = await _live(id);
        final rule = current.copyWith(
          categoryId: categoryId,
          title: title == null ? null : normalizeText(title),
          amount: amount,
          dayOfMonth: dayOfMonth,
          startMonth: startMonth,
          updatedAt: c.now,
          updatedBy: c.userId,
        );
        _validate(rule);
        await _db
            .into(_db.recurringRules)
            .insertOnConflictUpdate(recurringToRow(rule));
        outboxId = await _outbox.enqueueUpsert(rule);
        return rule;
      },
    );
  }

  @override
  Future<RecurringRule> delete(String id) {
    late int outboxId;
    return _writer.edit(
      _entity,
      'delete',
      id: id,
      describe: (r) => 'budget=${r.budgetId} outbox=delete#$outboxId',
      body: (c) async {
        final current = await _live(id);
        final tombstone = current.copyWith(
          deletedAt: c.now,
          updatedAt: c.now,
          updatedBy: c.userId,
        );
        await _db
            .into(_db.recurringRules)
            .insertOnConflictUpdate(recurringToRow(tombstone));
        outboxId = await _outbox.enqueueDelete(
          SyncEntity.recurring,
          id,
          at: c.now,
        );
        return tombstone;
      },
    );
  }

  @override
  Future<void> applyFromServer(Iterable<RecurringRule> rules) {
    final list = rules.toList();
    return _writer.sync(
      _entity,
      'apply',
      target: 'count=${list.length}',
      body: () async {
        await _db.batch((b) {
          b.insertAllOnConflictUpdate(_db.recurringRules, [
            for (final r in list) recurringToRow(r),
          ]);
        });
      },
    );
  }
}
