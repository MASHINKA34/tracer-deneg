import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart' as pg;
import 'package:shared/shared.dart';

import '../db/database.dart';
import 'sync_notifier.dart';

final _log = Logger('sync');

const Duration pushFutureTolerance = Duration(minutes: 5);

const Duration pushReplayWindow = Duration(hours: 24);

final RegExp _batchIdPattern = RegExp(r'^[A-Za-z0-9._-]{1,64}$');

bool isValidBatchId(String batchId) => _batchIdPattern.hasMatch(batchId);

const int _int4Min = -2147483648;
const int _int4Max = 2147483647;
final DateTime _minInstant = DateTime.utc(1);
final DateTime _maxInstant = DateTime.utc(10000);

const Map<SyncEntity, String> _tables = {
  SyncEntity.budget: 'budgets',
  SyncEntity.category: 'categories',
  SyncEntity.recurring: 'recurring_rules',
  SyncEntity.expense: 'expenses',
};

const Map<SyncEntity, String> _wipedOnDelete = {
  SyncEntity.category: 'name',
  SyncEntity.recurring: 'title',
  SyncEntity.expense: 'comment',
};

const Map<SyncEntity, int> _applyOrder = {
  SyncEntity.budget: 0,
  SyncEntity.category: 1,
  SyncEntity.recurring: 2,
  SyncEntity.expense: 3,
};

const String _activeBudgetsSql =
    'SELECT m.budget_id FROM budget_members m '
    'JOIN budgets b ON b.id = m.budget_id '
    r'WHERE m.user_id = $1::uuid AND m.left_at IS NULL '
    'AND b.deleted_at IS NULL';

class PushResult {
  const PushResult({required this.response, required this.replayed});

  final SyncPushResponse response;
  final bool replayed;
}

typedef _Problem = ({String code, String field, String problem});

final class _Done {
  const _Done.applied({
    this.written,
    this.visibleSeq,
    this.budgetIds = const {},
  }) : code = null;

  const _Done.rejected(String this.code, {this.visibleSeq})
    : written = null,
      budgetIds = const {};

  final String? code;
  final int? written;
  final int? visibleSeq;
  final Set<String> budgetIds;
}

final class _Stored {
  const _Stored({
    required this.budgetId,
    required this.updatedAt,
    required this.deletedAt,
    required this.seq,
    required this.isSystem,
  });

  final String budgetId;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int seq;
  final bool isSystem;
}

final class _Batch {
  _Batch({
    required this.userId,
    required this.batchId,
    required this.budgets,
    required this.serverNow,
  });

  final String userId;
  final String batchId;
  final Set<String> budgets;
  final DateTime serverNow;
  final Map<String, String?> categoryBudgets = {};
  int clamped = 0;
}

final class _Outcome {
  const _Outcome.replay(this.response, {required this.storedAt})
    : results = const [];

  const _Outcome.applied(this.response, this.results) : storedAt = null;

  final SyncPushResponse response;
  final List<_Done> results;
  final DateTime? storedAt;

  bool get replayed => storedAt != null;
}

class PushService {
  PushService({
    required this.db,
    this._notifier = const NoopSyncNotifier(),
    this._now = DateTime.now,
  });

  final Database db;
  final SyncNotifier _notifier;
  final DateTime Function() _now;

  Future<PushResult> push({
    required String userId,
    required SyncPushRequest request,
  }) async {
    final sw = Stopwatch()..start();
    final context = {
      'userId': userId,
      'batchId': request.batchId,
      'changes': request.changes.length,
    };
    final serverNow = normalizeInstant(_now());
    final _Outcome outcome;
    try {
      outcome = await db.transaction(
        'sync push',
        (tx) => _run(tx, userId, request, serverNow),
      );
    } catch (e) {
      _log.warning(
        'push failed ${formatContext(context)} '
        'in ${sw.elapsedMilliseconds}ms: ${describeError(e)}',
      );
      rethrow;
    }
    final response = outcome.response;
    if (outcome.replayed) {
      _log.info(
        'push replay of known batch, nothing applied again '
        'userId=$userId batchId=${request.batchId} '
        'changes=${request.changes.length} '
        'storedApplied=${response.applied.length} '
        'storedRejected=${response.rejected.length} '
        'cursor=${response.cursor} '
        'storedAt=${encodeInstant(outcome.storedAt!)} '
        'in ${sw.elapsedMilliseconds}ms',
      );
      return PushResult(response: response, replayed: true);
    }

    final written = [
      for (final result in outcome.results)
        if (result.written != null) result,
    ];
    final budgetIds = {for (final result in written) ...result.budgetIds};
    _log.info(
      'push userId=$userId batchId=${request.batchId} '
      'changes=${request.changes.length} '
      'applied=${response.applied.length} '
      'rejected=${response.rejected.length} '
      'codes=${_codes(response.rejected)} writes=${written.length} '
      'budgets=[${(budgetIds.toList()..sort()).join(',')}] '
      'cursor=${response.cursor} in ${sw.elapsedMilliseconds}ms',
    );
    if (written.isNotEmpty) {
      _notify(
        BudgetsChanged(
          reason: 'push',
          userId: userId,
          budgetIds: budgetIds,
          cursor: response.cursor,
        ),
        context,
      );
    }
    return PushResult(response: response, replayed: false);
  }

  void _notify(BudgetsChanged event, Map<String, Object?> context) {
    try {
      _notifier.budgetsChanged(event);
      _log.fine('push change event handed to notifier $event');
    } catch (e, st) {
      _log.warning(
        'push change event failed after commit, clients learn on next pull '
        '${formatContext(context)} event=$event: ${describeError(e)}',
        e,
        st,
      );
    }
  }

  Future<_Outcome> _run(
    DbSession tx,
    String userId,
    SyncPushRequest request,
    DateTime serverNow,
  ) async {
    final context = {'userId': userId, 'batchId': request.batchId};
    await tx.execute(
      r'DELETE FROM push_batches WHERE user_id = $1::uuid '
      r'AND created_at <= now() - make_interval(hours => $2::int)',
      parameters: [userId, pushReplayWindow.inHours],
      what: 'drop expired push batches of user',
      logParams: {...context, 'windowHours': pushReplayWindow.inHours},
    );
    final claimed = await tx.execute(
      r'INSERT INTO push_batches (user_id, batch_id, response) '
      r"VALUES ($1::uuid, $2, 'null'::jsonb) "
      'ON CONFLICT (user_id, batch_id) DO NOTHING RETURNING created_at',
      parameters: [userId, request.batchId],
      what: 'claim push batch id',
      logParams: context,
    );
    if (claimed.isEmpty) {
      final rows = await tx.execute(
        r'SELECT response, created_at FROM push_batches '
        r'WHERE user_id = $1::uuid AND batch_id = $2',
        parameters: [userId, request.batchId],
        what: 'read stored push response',
        logParams: context,
      );
      final row = rows.single;
      return _Outcome.replay(
        SyncPushResponse.fromJson(_decodeJson(row[0])),
        storedAt: row[1]! as DateTime,
      );
    }

    final memberships = await tx.execute(
      _activeBudgetsSql,
      parameters: [userId],
      what: 'active budgets of pushing user',
      logParams: context,
    );
    final batch = _Batch(
      userId: userId,
      batchId: request.batchId,
      budgets: {for (final row in memberships) row[0]! as String},
      serverNow: serverNow,
    );
    final changes = request.changes;
    final order = [for (var i = 0; i < changes.length; i++) i]
      ..sort((a, b) {
        final byEntity = _applyOrder[changes[a].entity]!.compareTo(
          _applyOrder[changes[b].entity]!,
        );
        if (byEntity != 0) return byEntity;
        final byId = changes[a].id.compareTo(changes[b].id);
        return byId != 0 ? byId : a.compareTo(b);
      });
    _log.fine(
      'push apply started ${formatContext(context)} '
      'changes=${changes.length} memberOf=${batch.budgets.length} '
      'serverNow=${encodeInstant(serverNow)}',
    );
    final results = List<_Done?>.filled(changes.length, null);
    for (final index in order) {
      results[index] = await _applyChange(tx, batch, changes[index]);
    }
    final done = results.cast<_Done>();

    var cursor = 0;
    for (final result in done) {
      final seq = result.visibleSeq;
      if (seq != null && seq > cursor) cursor = seq;
    }
    final response = SyncPushResponse(
      applied: [
        for (var i = 0; i < changes.length; i++)
          if (done[i].code == null) changes[i].id,
      ],
      rejected: [
        for (var i = 0; i < changes.length; i++)
          if (done[i].code case final code?)
            SyncRejection(id: changes[i].id, code: code),
      ],
      cursor: cursor,
    );
    await tx.execute(
      r'UPDATE push_batches SET response = $3 '
      r'WHERE user_id = $1::uuid AND batch_id = $2',
      parameters: [
        userId,
        request.batchId,
        pg.TypedValue(pg.Type.jsonb, response.toJson()),
      ],
      what: 'store push response for replays',
      logParams: {
        ...context,
        'applied': response.applied.length,
        'rejected': response.rejected.length,
        'clamped': batch.clamped,
      },
    );
    return _Outcome.applied(response, done);
  }

  Future<_Done> _applyChange(
    DbSession tx,
    _Batch batch,
    SyncChange change,
  ) async {
    if (!isUuid(change.id)) {
      return _invalid(batch, change, (
        code: ApiErrorCode.badRequest.code,
        field: 'id',
        problem: 'not a canonical lowercase uuid',
      ));
    }
    if (!_inRange(change.updatedAt)) {
      return _invalid(batch, change, (
        code: ApiErrorCode.validationFailed.code,
        field: 'updatedAt',
        problem: 'outside years 1-9999',
      ));
    }
    final at = _clamp(batch, change);
    return change.op == SyncOp.delete
        ? _delete(tx, batch, change, at)
        : _upsert(tx, batch, change, at);
  }

  DateTime _clamp(_Batch batch, SyncChange change) {
    final limit = batch.serverNow.add(pushFutureTolerance);
    if (!change.updatedAt.isAfter(limit)) return change.updatedAt;
    batch.clamped++;
    _log.warning(
      'push change updatedAt is in the future, clamped to server time '
      'entity=${change.entity.name} op=${change.op.name} id=${change.id} '
      'incoming=${encodeInstant(change.updatedAt)} '
      'serverNow=${encodeInstant(batch.serverNow)} '
      'toleranceMs=${pushFutureTolerance.inMilliseconds} '
      'userId=${batch.userId} batchId=${batch.batchId}',
    );
    return batch.serverNow;
  }

  Future<_Done> _delete(
    DbSession tx,
    _Batch batch,
    SyncChange change,
    DateTime at,
  ) async {
    final stored = await _lock(tx, batch, change);
    if (stored == null) {
      return _denied(batch, change, 'record not found', budgetId: null);
    }
    if (!batch.budgets.contains(stored.budgetId)) {
      return _denied(
        batch,
        change,
        'not a member of record budget',
        budgetId: stored.budgetId,
      );
    }
    if (change.entity == SyncEntity.budget) {
      _log.warning(
        'push change rejected by rights reason=${ApiErrorCode.forbidden.code} '
        'entity=${change.entity.name} op=${change.op.name} id=${change.id} '
        'problem="budget deletion goes through DELETE /budgets/{id}" '
        'userId=${batch.userId} batchId=${batch.batchId}',
      );
      return _Done.rejected(
        ApiErrorCode.forbidden.code,
        visibleSeq: stored.seq,
      );
    }
    if (stored.isSystem) {
      return _invalid(batch, change, (
        code: ApiErrorCode.validationFailed.code,
        field: 'isSystem',
        problem: 'system category cannot be deleted',
      ), visibleSeq: stored.seq);
    }
    if (stored.deletedAt != null) {
      _log.fine(
        'push change already deleted, nothing to write '
        'entity=${change.entity.name} id=${change.id} '
        'budgetId=${stored.budgetId} seq=${stored.seq}',
      );
      return _Done.applied(visibleSeq: stored.seq);
    }
    final table = _tables[change.entity]!;
    final wiped = _wipedOnDelete[change.entity]!;
    final rows = await tx.execute(
      'UPDATE $table SET deleted_at = \$2::timestamptz, '
      r'updated_at = greatest(updated_at, $2::timestamptz), '
      'updated_by = \$3::uuid, $wiped = \'\' WHERE id = \$1::uuid '
      'RETURNING seq',
      parameters: [change.id, at, batch.userId],
      what: 'tombstone $table row and wipe $wiped',
      logParams: {'id': change.id, 'budgetId': stored.budgetId},
    );
    final seq = rows.single[0]! as int;
    _log.fine(
      'push change applied as tombstone entity=${change.entity.name} '
      'id=${change.id} budgetId=${stored.budgetId} '
      'seq=${stored.seq}→$seq '
      'storedUpdatedAt=${encodeInstant(stored.updatedAt)} '
      'deletedAt=${encodeInstant(at)} wiped=$wiped',
    );
    return _Done.applied(
      written: seq,
      visibleSeq: seq,
      budgetIds: {stored.budgetId},
    );
  }

  Future<_Done> _upsert(
    DbSession tx,
    _Batch batch,
    SyncChange change,
    DateTime at,
  ) async {
    final SyncRecord record;
    try {
      record = change.decodeRecord();
    } on FormatException catch (e) {
      return _invalid(batch, change, (
        code: ApiErrorCode.badRequest.code,
        field: 'data',
        problem: truncateBody(e.message, maxBytes: 200),
      ));
    }
    if (record.deletedAt != null) {
      return _invalid(batch, change, (
        code: ApiErrorCode.badRequest.code,
        field: 'data.deletedAt',
        problem: 'upsert must not carry deletedAt, send op delete',
      ));
    }
    final malformed = _malformed(record);
    if (malformed != null) return _invalid(batch, change, malformed);
    final target = _budgetOf(record);

    for (var attempt = 1; ; attempt++) {
      final stored = await _lock(tx, batch, change);
      if (stored != null && !batch.budgets.contains(stored.budgetId)) {
        return _denied(
          batch,
          change,
          'not a member of record budget',
          budgetId: stored.budgetId,
        );
      }
      if (!batch.budgets.contains(target)) {
        return _denied(
          batch,
          change,
          'not a member of target budget',
          budgetId: target,
          visibleSeq: stored?.seq,
        );
      }
      final problem =
          _invalidValue(record, stored) ??
          await _invalidReference(tx, batch, record, target);
      if (problem != null) {
        return _invalid(batch, change, problem, visibleSeq: stored?.seq);
      }

      if (stored == null) {
        final seq = await _insert(tx, batch, record, at);
        if (seq == null) {
          if (attempt >= 2) {
            throw StateError(
              'push ${change.entity.name} ${change.id}: insert conflicted '
              'twice but the row is still not visible',
            );
          }
          _log.fine(
            'push change lost insert race to a concurrent writer, '
            'retrying as update entity=${change.entity.name} id=${change.id}',
          );
          continue;
        }
        if (record is Category) batch.categoryBudgets[record.id] = target;
        _log.fine(
          'push change applied as insert entity=${change.entity.name} '
          'id=${change.id} budgetId=$target seq=$seq '
          'updatedAt=${encodeInstant(at)}',
        );
        return _Done.applied(
          written: seq,
          visibleSeq: seq,
          budgetIds: {target},
        );
      }

      if (stored.deletedAt != null) {
        return _conflict(
          batch,
          change,
          stored,
          at,
          'record is deleted, tombstone wins over edit',
        );
      }
      if (at.isBefore(stored.updatedAt)) {
        return _conflict(
          batch,
          change,
          stored,
          at,
          'older than stored version, last edit wins',
        );
      }
      final seq = await _update(tx, batch, record, at);
      _log.fine(
        'push change applied as update entity=${change.entity.name} '
        'id=${change.id} budgetId=${stored.budgetId}'
        '${stored.budgetId == target ? '' : '→$target'} '
        'seq=${stored.seq}→$seq '
        'updatedAt=${encodeInstant(stored.updatedAt)}→${encodeInstant(at)}',
      );
      return _Done.applied(
        written: seq,
        visibleSeq: seq,
        budgetIds: {stored.budgetId, target},
      );
    }
  }

  Future<_Stored?> _lock(DbSession tx, _Batch batch, SyncChange change) async {
    final sql = switch (change.entity) {
      SyncEntity.budget =>
        'SELECT id, updated_at, deleted_at, seq, false FROM budgets '
            r'WHERE id = $1::uuid FOR NO KEY UPDATE',
      SyncEntity.category =>
        'SELECT budget_id, updated_at, deleted_at, seq, is_system '
            r'FROM categories WHERE id = $1::uuid FOR NO KEY UPDATE',
      SyncEntity.recurring =>
        'SELECT budget_id, updated_at, deleted_at, seq, false '
            r'FROM recurring_rules WHERE id = $1::uuid FOR NO KEY UPDATE',
      SyncEntity.expense =>
        'SELECT budget_id, updated_at, deleted_at, seq, false '
            r'FROM expenses WHERE id = $1::uuid FOR NO KEY UPDATE',
    };
    final rows = await tx.execute(
      sql,
      parameters: [change.id],
      what: 'lock stored ${change.entity.name}',
      logParams: {'id': change.id, 'batchId': batch.batchId},
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return _Stored(
      budgetId: row[0]! as String,
      updatedAt: row[1]! as DateTime,
      deletedAt: row[2] as DateTime?,
      seq: row[3]! as int,
      isSystem: row[4]! as bool,
    );
  }

  Future<_Problem?> _invalidReference(
    DbSession tx,
    _Batch batch,
    SyncRecord record,
    String target,
  ) async {
    final categoryId = switch (record) {
      Expense(:final categoryId) => categoryId,
      RecurringRule(:final categoryId) => categoryId,
      _ => null,
    };
    if (categoryId == null) return null;
    final String? categoryBudget;
    if (batch.categoryBudgets.containsKey(categoryId)) {
      categoryBudget = batch.categoryBudgets[categoryId];
    } else {
      final rows = await tx.execute(
        r'SELECT budget_id FROM categories WHERE id = $1::uuid',
        parameters: [categoryId],
        what: 'find budget of referenced category',
        logParams: {'categoryId': categoryId, 'batchId': batch.batchId},
      );
      categoryBudget = rows.isEmpty ? null : rows.single[0]! as String;
      batch.categoryBudgets[categoryId] = categoryBudget;
    }
    if (categoryBudget == target) return null;
    return (
      code: ApiErrorCode.validationFailed.code,
      field: 'categoryId',
      problem: categoryBudget == null
          ? 'category $categoryId not found'
          : 'category $categoryId is in another budget',
    );
  }

  Future<int?> _insert(
    DbSession tx,
    _Batch batch,
    SyncRecord record,
    DateTime at,
  ) async {
    final (String sql, List<Object?> parameters) = switch (record) {
      Category c => (
        'INSERT INTO categories (id, budget_id, name, emoji, color, '
            'sort_order, is_system, updated_at, updated_by) VALUES '
            r'($1::uuid, $2::uuid, $3, $4, $5::text, $6::int, false, '
            r'$7::timestamptz, $8::uuid) '
            'ON CONFLICT (id) DO NOTHING RETURNING seq',
        [
          c.id,
          c.budgetId,
          normalizeText(c.name),
          normalizeText(c.emoji),
          c.color?.name,
          c.sortOrder,
          at,
          batch.userId,
        ],
      ),
      RecurringRule r => (
        'INSERT INTO recurring_rules (id, budget_id, category_id, title, '
            'amount_kopecks, day_of_month, start_month, created_at, '
            r'updated_at, updated_by) VALUES ($1::uuid, $2::uuid, '
            r'$3::uuid, $4, $5::bigint, $6::int, $7, $8::timestamptz, '
            r'$9::timestamptz, $10::uuid) '
            'ON CONFLICT (id) DO NOTHING RETURNING seq',
        [
          r.id,
          r.budgetId,
          r.categoryId,
          normalizeText(r.title),
          r.amount.kopecks,
          r.dayOfMonth,
          r.startMonth.toJson(),
          r.createdAt,
          at,
          batch.userId,
        ],
      ),
      Expense e => (
        'INSERT INTO expenses (id, budget_id, category_id, amount_kopecks, '
            'spent_on, comment, author_id, recurring_id, recurring_month, '
            r'created_at, updated_at, updated_by) VALUES ($1::uuid, '
            r'$2::uuid, $3::uuid, $4::bigint, $5::date, $6, $7::uuid, '
            r'$8::uuid, $9::text, $10::timestamptz, $11::timestamptz, '
            r'$7::uuid) ON CONFLICT (id) DO NOTHING RETURNING seq',
        [
          e.id,
          e.budgetId,
          e.categoryId,
          e.amount.kopecks,
          e.spentOn.toJson(),
          normalizeText(e.comment),
          batch.userId,
          e.recurringId,
          e.recurringMonth?.toJson(),
          e.createdAt,
          at,
        ],
      ),
      _ => throw StateError(
        'push ${record.syncEntity.name} ${record.id}: '
        'only categories, recurring rules and expenses are created by push',
      ),
    };
    final table = _tables[record.syncEntity]!;
    final rows = await tx.execute(
      sql,
      parameters: parameters,
      what: 'insert $table row',
      logParams: {
        'id': record.id,
        'budgetId': _budgetOf(record),
        'batchId': batch.batchId,
      },
    );
    return rows.isEmpty ? null : rows.single[0]! as int;
  }

  Future<int> _update(
    DbSession tx,
    _Batch batch,
    SyncRecord record,
    DateTime at,
  ) async {
    final (String sql, List<Object?> parameters) = switch (record) {
      Budget b => (
        r'UPDATE budgets SET name = $2, emoji = $3, '
            r'updated_at = $4::timestamptz, updated_by = $5::uuid '
            r'WHERE id = $1::uuid RETURNING seq',
        [b.id, normalizeText(b.name), normalizeText(b.emoji), at, batch.userId],
      ),
      Category c => (
        r'UPDATE categories SET name = $2, emoji = $3, color = $4::text, '
            r'sort_order = $5::int, updated_at = $6::timestamptz, '
            r'updated_by = $7::uuid WHERE id = $1::uuid RETURNING seq',
        [
          c.id,
          normalizeText(c.name),
          normalizeText(c.emoji),
          c.color?.name,
          c.sortOrder,
          at,
          batch.userId,
        ],
      ),
      RecurringRule r => (
        r'UPDATE recurring_rules SET budget_id = $2::uuid, '
            r'category_id = $3::uuid, title = $4, amount_kopecks = $5::bigint, '
            r'day_of_month = $6::int, start_month = $7, '
            r'updated_at = $8::timestamptz, updated_by = $9::uuid '
            r'WHERE id = $1::uuid RETURNING seq',
        [
          r.id,
          r.budgetId,
          r.categoryId,
          normalizeText(r.title),
          r.amount.kopecks,
          r.dayOfMonth,
          r.startMonth.toJson(),
          at,
          batch.userId,
        ],
      ),
      Expense e => (
        r'UPDATE expenses SET budget_id = $2::uuid, category_id = $3::uuid, '
            r'amount_kopecks = $4::bigint, spent_on = $5::date, comment = $6, '
            r'updated_at = $7::timestamptz, updated_by = $8::uuid '
            r'WHERE id = $1::uuid RETURNING seq',
        [
          e.id,
          e.budgetId,
          e.categoryId,
          e.amount.kopecks,
          e.spentOn.toJson(),
          normalizeText(e.comment),
          at,
          batch.userId,
        ],
      ),
      _ => throw StateError(
        'push ${record.syncEntity.name} ${record.id}: unknown record type',
      ),
    };
    final table = _tables[record.syncEntity]!;
    final rows = await tx.execute(
      sql,
      parameters: parameters,
      what: 'update $table row',
      logParams: {
        'id': record.id,
        'budgetId': _budgetOf(record),
        'batchId': batch.batchId,
      },
    );
    return rows.single[0]! as int;
  }

  _Done _denied(
    _Batch batch,
    SyncChange change,
    String problem, {
    required String? budgetId,
    int? visibleSeq,
  }) {
    _log.warning(
      'push change rejected by rights reason=${ApiErrorCode.notFound.code} '
      'entity=${change.entity.name} op=${change.op.name} id=${change.id} '
      '${formatContext({'problem': problem, 'budgetId': budgetId})} '
      'userId=${batch.userId} batchId=${batch.batchId}',
    );
    return _Done.rejected(ApiErrorCode.notFound.code, visibleSeq: visibleSeq);
  }

  _Done _invalid(
    _Batch batch,
    SyncChange change,
    _Problem problem, {
    int? visibleSeq,
  }) {
    final id = isUuid(change.id)
        ? change.id
        : truncateBody(change.id, maxBytes: 64);
    _log.warning(
      'push change rejected reason=${problem.code} '
      'entity=${change.entity.name} op=${change.op.name} '
      '${formatContext({'id': id, 'field': problem.field, 'problem': problem.problem})} '
      'userId=${batch.userId} batchId=${batch.batchId}',
    );
    return _Done.rejected(problem.code, visibleSeq: visibleSeq);
  }

  _Done _conflict(
    _Batch batch,
    SyncChange change,
    _Stored stored,
    DateTime at,
    String problem,
  ) {
    _log.info(
      'push change rejected reason=${ApiErrorCode.conflict.code} '
      'entity=${change.entity.name} op=${change.op.name} id=${change.id} '
      'problem="$problem" budgetId=${stored.budgetId} seq=${stored.seq} '
      'storedUpdatedAt=${encodeInstant(stored.updatedAt)} '
      'storedDeletedAt=${stored.deletedAt == null ? '-' : encodeInstant(stored.deletedAt!)} '
      'incomingUpdatedAt=${encodeInstant(at)} '
      'userId=${batch.userId} batchId=${batch.batchId}',
    );
    return _Done.rejected(ApiErrorCode.conflict.code, visibleSeq: stored.seq);
  }
}

String _budgetOf(SyncRecord record) => switch (record) {
  Budget(:final id) => id,
  Category(:final budgetId) => budgetId,
  RecurringRule(:final budgetId) => budgetId,
  Expense(:final budgetId) => budgetId,
  _ => throw StateError('unknown record type ${record.runtimeType}'),
};

_Problem? _malformed(SyncRecord record) {
  _Problem? uuid(String field, String? value) => value == null || isUuid(value)
      ? null
      : (
          code: ApiErrorCode.badRequest.code,
          field: field,
          problem: 'not a canonical lowercase uuid',
        );
  final checks = switch (record) {
    Category c => [uuid('budgetId', c.budgetId)],
    RecurringRule r => [
      uuid('budgetId', r.budgetId),
      uuid('categoryId', r.categoryId),
    ],
    Expense e => [
      uuid('budgetId', e.budgetId),
      uuid('categoryId', e.categoryId),
      uuid('recurringId', e.recurringId),
    ],
    _ => const <_Problem?>[],
  };
  return checks.nonNulls.firstOrNull;
}

_Problem? _invalidValue(SyncRecord record, _Stored? stored) {
  _Problem? rule(String field, ValidationError? error) => error == null
      ? null
      : (code: error.code, field: field, problem: 'shared validation');
  _Problem? failed(String field, String problem) => (
    code: ApiErrorCode.validationFailed.code,
    field: field,
    problem: problem,
  );
  _Problem? text(String field, String value) =>
      value.contains('\u0000') ? failed(field, 'contains NUL character') : null;
  _Problem? instant(String field, DateTime value) =>
      _inRange(value) ? null : failed(field, 'outside years 1-9999');

  final checks = switch (record) {
    Budget b => [
      text('name', b.name),
      rule('name', validateBudgetName(b.name)),
      text('emoji', b.emoji),
      rule('emoji', validateEmoji(b.emoji)),
    ],
    Category c => [
      text('name', c.name),
      rule('name', validateCategoryName(c.name)),
      text('emoji', c.emoji),
      rule('emoji', validateEmoji(c.emoji)),
      if (c.sortOrder < _int4Min || c.sortOrder > _int4Max)
        failed('sortOrder', 'outside 32-bit integer'),
      if (stored != null && stored.budgetId != c.budgetId)
        failed('budgetId', 'category cannot move to another budget'),
      if (stored == null && c.isSystem)
        failed('isSystem', 'system category is created only by server'),
    ],
    RecurringRule r => [
      text('title', r.title),
      rule('title', validateRecurringTitle(r.title)),
      rule('amountKopecks', validateAmount(r.amount)),
      rule('dayOfMonth', validateDayOfMonth(r.dayOfMonth)),
      instant('createdAt', r.createdAt),
    ],
    Expense e => [
      rule('amountKopecks', validateAmount(e.amount)),
      text('comment', e.comment),
      rule('comment', validateComment(e.comment)),
      if ((e.recurringId == null) != (e.recurringMonth == null))
        failed('recurringMonth', 'recurringId and recurringMonth go together'),
      instant('createdAt', e.createdAt),
    ],
    _ => const <_Problem?>[],
  };
  return checks.nonNulls.firstOrNull;
}

bool _inRange(DateTime instant) =>
    !instant.isBefore(_minInstant) && instant.isBefore(_maxInstant);

Object? _decodeJson(Object? value) =>
    value is String ? jsonDecode(value) : value;

String _codes(List<SyncRejection> rejected) {
  if (rejected.isEmpty) return '-';
  final counts = <String, int>{};
  for (final rejection in rejected) {
    counts[rejection.code] = (counts[rejection.code] ?? 0) + 1;
  }
  final codes = counts.keys.toList()..sort();
  return codes.map((code) => '$code:${counts[code]}').join(',');
}
