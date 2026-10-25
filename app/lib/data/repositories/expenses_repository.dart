import 'dart:async';
import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../current_user.dart';
import '../db/app_database.dart';
import 'outbox_queue.dart';
import 'records.dart';
import 'repository_errors.dart';
import 'repository_writer.dart';

final _log = Logger('repo');

const Duration expenseUndoWindow = Duration(seconds: 5);

final class TodayExpenseSaved {
  const TodayExpenseSaved({
    required this.expenseId,
    required this.budgetId,
    required this.day,
    required this.action,
  });

  final String expenseId;
  final String budgetId;
  final LocalDate day;
  final String action;

  @override
  String toString() =>
      'expense $action id=$expenseId budgetId=$budgetId day=$day';
}

typedef TodayExpenseListener = void Function(TodayExpenseSaved event);

final class TodayExpenseEvents {
  final StreamController<TodayExpenseSaved> _controller =
      StreamController<TodayExpenseSaved>.broadcast();

  Stream<TodayExpenseSaved> get stream => _controller.stream;

  void add(TodayExpenseSaved event) {
    if (_controller.isClosed) {
      _log.fine('$event for today after events were closed: not delivered');
      return;
    }
    _controller.add(event);
  }

  Future<void> close() => _controller.close();
}

abstract interface class ExpensesRepository {
  Stream<List<Expense>> watchByBudget(String budgetId);

  Stream<Expense?> watchById(String id);

  Future<Expense> create({
    required String budgetId,
    required String categoryId,
    required Money amount,
    required LocalDate spentOn,
    String comment = '',
  });

  Future<Expense> update(
    String id, {
    String? budgetId,
    String? categoryId,
    Money? amount,
    LocalDate? spentOn,
    String? comment,
  });

  Future<Expense> delete(String id);

  Future<bool> undoDelete(String id);

  Future<({Set<String> live, Set<String> deleted})> existingByIds(
    Iterable<String> ids,
  );

  Future<Expense> createRecurring(
    RecurringRule rule,
    PlannedRecurringExpense planned,
  );

  Future<void> applyFromServer(Iterable<Expense> expenses);
}

final class DriftExpensesRepository implements ExpensesRepository {
  DriftExpensesRepository(
    this._db, {
    required CurrentUser currentUser,
    required OutboxQueue outbox,
    Now now = DateTime.now,
    this._onTodayExpense,
  }) : _writer = RepositoryWriter(
         _db,
         outbox: outbox,
         currentUser: currentUser,
         now: now,
       );

  static const String _entity = 'expense';

  static const int _idsPerQuery = 500;

  final AppDatabase _db;
  final RepositoryWriter _writer;
  final TodayExpenseListener? _onTodayExpense;

  OutboxQueue get _outbox => _writer.outbox;

  void _savedForToday(Expense expense, DateTime at, String action) {
    final listener = _onTodayExpense;
    if (listener == null) return;
    final today = LocalDate.fromDateTime(at.toLocal());
    if (expense.spentOn != today) return;
    final event = TodayExpenseSaved(
      expenseId: expense.id,
      budgetId: expense.budgetId,
      day: today,
      action: action,
    );
    _log.fine('$event is for today → today event');
    try {
      listener(event);
    } catch (e, st) {
      _log.warning(
        'today event for $event failed, the expense is saved anyway: '
        '${describeError(e)}',
        e,
        st,
      );
    }
  }

  @override
  Stream<List<Expense>> watchByBudget(String budgetId) => _writer.watch(
    _entity,
    'budget=$budgetId',
    (_db.select(_db.expenses)
          ..where((e) => e.budgetId.equals(budgetId) & e.deletedAt.isNull())
          ..orderBy([
            (e) => OrderingTerm.desc(e.spentOn),
            (e) => OrderingTerm.desc(e.createdAt),
            (e) => OrderingTerm.asc(e.id),
          ]))
        .watch()
        .map((rows) => [for (final r in rows) expenseFromRow(r)]),
  );

  @override
  Stream<Expense?> watchById(String id) => _writer.watch(
    _entity,
    'id=$id',
    (_db.select(_db.expenses)
          ..where((e) => e.id.equals(id) & e.deletedAt.isNull()))
        .watchSingleOrNull()
        .map((r) => r == null ? null : expenseFromRow(r)),
  );

  Future<ExpenseEntry?> _row(String id) => (_db.select(
    _db.expenses,
  )..where((e) => e.id.equals(id))).getSingleOrNull();

  Future<Expense> _live(String id) async {
    final row = await _row(id);
    if (row == null || row.deletedAt != null) {
      throw RepositoryException(
        RepositoryFailure.notFound,
        entity: _entity,
        id: id,
      );
    }
    return expenseFromRow(row);
  }

  void _validate(Expense e) {
    checkValid(validateAmount(e.amount), entity: _entity, id: e.id);
    checkValid(validateComment(e.comment), entity: _entity, id: e.id);
  }

  String _describe(Expense e, int outboxId, SyncOp op) =>
      'budget=${e.budgetId} category=${e.categoryId} '
      'amount=${e.amount.kopecks} outbox=${op.name}#$outboxId';

  @override
  Future<Expense> create({
    required String budgetId,
    required String categoryId,
    required Money amount,
    required LocalDate spentOn,
    String comment = '',
  }) async {
    final id = newId();
    late int outboxId;
    late DateTime at;
    final created = await _writer.edit(
      _entity,
      'create',
      id: id,
      describe: (e) => _describe(e, outboxId, SyncOp.upsert),
      body: (c) async {
        at = c.now;
        final expense = Expense(
          id: id,
          budgetId: budgetId,
          categoryId: categoryId,
          amount: amount,
          spentOn: spentOn,
          comment: normalizeText(comment),
          authorId: c.userId,
          createdAt: c.now,
          updatedAt: c.now,
          updatedBy: c.userId,
        );
        _validate(expense);
        await _db.into(_db.expenses).insert(expenseToRow(expense));
        outboxId = await _outbox.enqueueUpsert(expense);
        return expense;
      },
    );
    _savedForToday(created, at, 'create');
    return created;
  }

  @override
  Future<Expense> update(
    String id, {
    String? budgetId,
    String? categoryId,
    Money? amount,
    LocalDate? spentOn,
    String? comment,
  }) async {
    late int outboxId;
    late DateTime at;
    final updated = await _writer.edit(
      _entity,
      'update',
      id: id,
      describe: (e) => _describe(e, outboxId, SyncOp.upsert),
      body: (c) async {
        at = c.now;
        final current = await _live(id);
        final expense = current.copyWith(
          budgetId: budgetId,
          categoryId: categoryId,
          amount: amount,
          spentOn: spentOn,
          comment: comment == null ? null : normalizeText(comment),
          updatedAt: c.now,
          updatedBy: c.userId,
        );
        _validate(expense);
        await _db
            .into(_db.expenses)
            .insertOnConflictUpdate(expenseToRow(expense));
        outboxId = await _outbox.enqueueUpsert(expense);
        return expense;
      },
    );
    _savedForToday(updated, at, 'update');
    return updated;
  }

  @override
  Future<Expense> delete(String id) {
    late int outboxId;
    late DateTime notBefore;
    return _writer.edit(
      _entity,
      'delete',
      id: id,
      describe: (e) =>
          'budget=${e.budgetId} outbox=delete#$outboxId '
          'notBefore=${encodeInstant(notBefore)}',
      body: (c) async {
        final current = await _live(id);
        final tombstone = current.copyWith(
          deletedAt: c.now,
          updatedAt: c.now,
          updatedBy: c.userId,
        );
        notBefore = c.now.add(expenseUndoWindow);
        await _db
            .into(_db.expenses)
            .insertOnConflictUpdate(expenseToRow(tombstone));
        outboxId = await _outbox.enqueueDelete(
          SyncEntity.expense,
          id,
          at: c.now,
          notBefore: notBefore,
        );
        return tombstone;
      },
    );
  }

  @override
  Future<bool> undoDelete(String id) async {
    late String reason;
    final undone = await _writer.edit(
      _entity,
      'undo-delete',
      id: id,
      describe: (undone) => 'undone=$undone reason=$reason',
      body: (c) async {
        final row = await _row(id);
        if (row == null) {
          reason = 'not-found';
          return false;
        }
        if (row.deletedAt == null) {
          reason = 'not-deleted';
          return false;
        }
        final cancelled = await _outbox.cancelPendingDelete(
          SyncEntity.expense,
          id,
          now: c.now,
        );
        if (!cancelled) {
          reason = 'window-expired';
          return false;
        }
        final restored = expenseFromRow(row)
            .copyWith(deletedAt: null, updatedAt: c.now, updatedBy: c.userId);
        await _db
            .into(_db.expenses)
            .insertOnConflictUpdate(expenseToRow(restored));
        reason = 'in-window';
        return true;
      },
    );
    _log.info('expense undo delete id=$id undone=$undone reason=$reason');
    return undone;
  }

  @override
  Future<({Set<String> live, Set<String> deleted})> existingByIds(
    Iterable<String> ids,
  ) async {
    final all = ids.toSet().toList();
    final live = <String>{};
    final deleted = <String>{};
    final table = _db.expenses;
    for (var start = 0; start < all.length; start += _idsPerQuery) {
      final chunk = all.sublist(
        start,
        math.min(start + _idsPerQuery, all.length),
      );
      final query = _db.selectOnly(table)
        ..addColumns([table.id, table.deletedAt])
        ..where(table.id.isIn(chunk));
      for (final row in await query.get()) {
        final id = row.read(table.id)!;
        (row.read(table.deletedAt) == null ? live : deleted).add(id);
      }
    }
    return (live: live, deleted: deleted);
  }

  @override
  Future<Expense> createRecurring(
    RecurringRule rule,
    PlannedRecurringExpense planned,
  ) {
    late int outboxId;
    return _writer.edit(
      _entity,
      'create-recurring',
      id: planned.id,
      describe: (e) =>
          'rule=${rule.id} month=${planned.month} spentOn=${e.spentOn} '
          '${_describe(e, outboxId, SyncOp.upsert)}',
      body: (c) async {
        final expense = Expense(
          id: planned.id,
          budgetId: rule.budgetId,
          categoryId: rule.categoryId,
          amount: rule.amount,
          spentOn: planned.spentOn,
          comment: normalizeText(rule.title),
          authorId: c.userId,
          recurringId: rule.id,
          recurringMonth: planned.month,
          createdAt: c.now,
          updatedAt: c.now,
          updatedBy: c.userId,
        );
        _validate(expense);
        await _db.into(_db.expenses).insert(expenseToRow(expense));
        outboxId = await _outbox.enqueueUpsert(expense);
        return expense;
      },
    );
  }

  @override
  Future<void> applyFromServer(Iterable<Expense> expenses) {
    final list = expenses.toList();
    return _writer.sync(
      _entity,
      'apply',
      target: 'count=${list.length}',
      body: () async {
        await _db.batch((b) {
          b.insertAllOnConflictUpdate(_db.expenses, [
            for (final e in list) expenseToRow(e),
          ]);
        });
      },
    );
  }
}
