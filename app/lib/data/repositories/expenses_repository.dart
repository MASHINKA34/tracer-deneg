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

  Future<void> applyFromServer(Iterable<Expense> expenses);
}

final class DriftExpensesRepository implements ExpensesRepository {
  DriftExpensesRepository(
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

  static const String _entity = 'expense';

  final AppDatabase _db;
  final RepositoryWriter _writer;

  OutboxQueue get _outbox => _writer.outbox;

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
    return _writer.edit(
      _entity,
      'create',
      id: id,
      describe: (e) => _describe(e, outboxId, SyncOp.upsert),
      body: (c) async {
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
  }

  @override
  Future<Expense> update(
    String id, {
    String? budgetId,
    String? categoryId,
    Money? amount,
    LocalDate? spentOn,
    String? comment,
  }) {
    late int outboxId;
    return _writer.edit(
      _entity,
      'update',
      id: id,
      describe: (e) => _describe(e, outboxId, SyncOp.upsert),
      body: (c) async {
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
