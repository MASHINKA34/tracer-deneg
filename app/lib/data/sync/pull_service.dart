import 'package:drift/drift.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../api/api_exception.dart';
import '../api/sync_api.dart';
import '../db/app_database.dart';
import '../db/redact_db_error.dart';
import '../repositories/budgets_repository.dart';
import '../repositories/categories_repository.dart';
import '../repositories/expenses_repository.dart';
import '../repositories/members_repository.dart';
import '../repositories/outbox_queue.dart';
import '../repositories/recurring_repository.dart';

final _log = Logger('sync');

const int _lastErrorLength = 300;

enum PullReason { login, register, recover, manual, retry }

final class PullCounts {
  const PullCounts({
    this.budgets = 0,
    this.members = 0,
    this.profiles = 0,
    this.categories = 0,
    this.expenses = 0,
    this.recurring = 0,
    this.removed = 0,
  });

  factory PullCounts.of(SyncPullResponse page) => PullCounts(
    budgets: page.budgets.length,
    members: page.members.length,
    profiles: page.profiles.length,
    categories: page.categories.length,
    expenses: page.expenses.length,
    recurring: page.recurring.length,
    removed: page.removedBudgetIds.length,
  );

  final int budgets;
  final int members;
  final int profiles;
  final int categories;
  final int expenses;
  final int recurring;
  final int removed;

  int get total =>
      budgets +
      members +
      profiles +
      categories +
      expenses +
      recurring +
      removed;

  PullCounts operator +(PullCounts other) => PullCounts(
    budgets: budgets + other.budgets,
    members: members + other.members,
    profiles: profiles + other.profiles,
    categories: categories + other.categories,
    expenses: expenses + other.expenses,
    recurring: recurring + other.recurring,
    removed: removed + other.removed,
  );

  @override
  bool operator ==(Object other) =>
      other is PullCounts &&
      other.budgets == budgets &&
      other.members == members &&
      other.profiles == profiles &&
      other.categories == categories &&
      other.expenses == expenses &&
      other.recurring == recurring &&
      other.removed == removed;

  @override
  int get hashCode => Object.hash(
    budgets,
    members,
    profiles,
    categories,
    expenses,
    recurring,
    removed,
  );

  @override
  String toString() =>
      'budgets=$budgets members=$members profiles=$profiles '
      'categories=$categories expenses=$expenses recurring=$recurring '
      'removed=$removed';
}

final class RemovedBudget {
  const RemovedBudget({
    required this.budgetId,
    required this.name,
    required this.kind,
    required this.ownerId,
    required this.wasSelected,
  });

  final String budgetId;
  final String name;
  final BudgetKind kind;
  final String ownerId;
  final bool wasSelected;

  @override
  String toString() =>
      'RemovedBudget($budgetId ${kind.name} owner=$ownerId '
      'selected=$wasSelected)';
}

typedef SelectedBudgetReader = Future<String?> Function();

typedef BudgetsRemovedHandler = void Function(List<RemovedBudget> removed);

typedef RejectedEntity = ({SyncEntity entity, String id});

final class PullResult {
  const PullResult({
    required this.reason,
    required this.pages,
    required this.counts,
    required this.cursorBefore,
    required this.cursorAfter,
    required this.syncedAt,
    required this.elapsed,
    this.applyElapsed = Duration.zero,
    this.kept = 0,
    this.removedBudgets = const [],
  });

  final PullReason reason;
  final int pages;
  final PullCounts counts;
  final int cursorBefore;
  final int cursorAfter;
  final DateTime syncedAt;
  final Duration elapsed;
  final Duration applyElapsed;
  final int kept;
  final List<RemovedBudget> removedBudgets;

  @override
  String toString() =>
      'PullResult(${reason.name} pages=$pages $counts '
      'cursor=$cursorBefore→$cursorAfter in ${elapsed.inMilliseconds}ms)';
}

enum PullStage { prepare, request, apply }

final class PullStalled implements Exception {
  const PullStalled({required this.cursor, required this.answered});

  final int cursor;
  final int answered;

  @override
  String toString() =>
      'PullStalled: server answered hasMore=true with cursor=$answered, '
      'not after cursor=$cursor';
}

final class PullFailure implements Exception {
  const PullFailure({
    required this.reason,
    required this.stage,
    required this.page,
    required this.cursor,
    required this.pagesApplied,
    required this.attempt,
    required this.error,
    this.requestId,
  });

  final PullReason reason;
  final PullStage stage;
  final int page;
  final int cursor;
  final int pagesApplied;
  final int attempt;
  final Object error;
  final String? requestId;

  String get errorType => error.runtimeType.toString();

  bool get expected => switch (error) {
    ApiNetworkFailure() || ApiTimeout() || ApiSessionExpired() => true,
    ApiErrorResponse(:final statusCode) => statusCode == 401,
    _ => false,
  };

  String get description => switch (error) {
    final ApiException e => '${e.runtimeType}: ${e.details}',
    final Object e => describeError(e),
  };

  @override
  String toString() =>
      'PullFailure(${reason.name} ${stage.name} page=$page cursor=$cursor '
      'attempt=$attempt $description rid=${requestId ?? '-'})';
}

class PullService {
  PullService({
    required this._api,
    required this._db,
    required this._budgets,
    required this._members,
    required this._categories,
    required this._recurring,
    required this._expenses,
    this._now = DateTime.now,
    this.pageSize = pullPageSize,
  });

  final SyncApi _api;
  final AppDatabase _db;
  final BudgetsRepository _budgets;
  final MembersRepository _members;
  final CategoriesRepository _categories;
  final RecurringRepository _recurring;
  final ExpensesRepository _expenses;
  final Now _now;
  final int pageSize;

  Future<PullResult> pull(
    PullReason reason, {
    int attempt = 1,
    int? from,
    SelectedBudgetReader? selectedBudget,
    BudgetsRemovedHandler? onRemoved,
  }) async {
    final sw = Stopwatch()..start();
    final int before;
    var stored = 0;
    try {
      stored = await _readCursor();
      if (from != null && from < stored) {
        _log.info(
          'pull reason=${reason.name} re-reads from cursor=$from instead of '
          'stored cursor=$stored: rejected changes come back from the server',
        );
        before = from;
      } else {
        before = stored;
      }
    } catch (e, st) {
      throw await _failed(
        sw,
        reason: reason,
        stage: PullStage.prepare,
        page: 1,
        cursor: -1,
        pagesApplied: 0,
        attempt: attempt,
        error: redactDbError(e),
        stackTrace: st,
      );
    }
    _log.fine(
      'pull start reason=${reason.name} cursor=$before limit=$pageSize '
      'attempt=$attempt',
    );
    var cursor = before;
    var pages = 0;
    var counts = const PullCounts();
    var kept = 0;
    var applyElapsed = Duration.zero;
    final removedBudgets = <RemovedBudget>[];
    while (true) {
      final number = pages + 1;
      final PullPage page;
      try {
        page = await _api.pull(SyncPullQuery(cursor: cursor, limit: pageSize));
      } on ApiException catch (e, st) {
        throw await _failed(
          sw,
          reason: reason,
          stage: PullStage.request,
          page: number,
          cursor: cursor,
          pagesApplied: pages,
          attempt: attempt,
          error: e,
          stackTrace: st,
          requestId: e.requestId,
        );
      }
      final response = page.response;
      if (response.hasMore && response.cursor <= cursor) {
        throw await _failed(
          sw,
          reason: reason,
          stage: PullStage.request,
          page: number,
          cursor: cursor,
          pagesApplied: pages,
          attempt: attempt,
          error: PullStalled(cursor: cursor, answered: response.cursor),
          stackTrace: StackTrace.current,
          requestId: page.requestId,
        );
      }
      final selected = response.removedBudgetIds.isEmpty
          ? null
          : await _selectedBefore(selectedBudget, reason, number);
      final applied = Stopwatch()..start();
      final syncedAt = response.hasMore ? null : normalizeInstant(_now());
      final _Applied outcome;
      try {
        outcome = await _apply(
          response,
          syncedAt: syncedAt,
          selected: selected,
          floor: syncedAt == null ? 0 : stored,
        );
      } catch (e, st) {
        throw await _failed(
          sw,
          reason: reason,
          stage: PullStage.apply,
          page: number,
          cursor: cursor,
          pagesApplied: pages,
          attempt: attempt,
          error: redactDbError(e),
          stackTrace: st,
          requestId: page.requestId,
        );
      }
      final pageCounts = PullCounts.of(response);
      pages = number;
      counts += pageCounts;
      kept += outcome.kept.total;
      applyElapsed += applied.elapsed;
      _log.fine(
        'pull page $number applied in one transaction '
        'entities=${pageCounts.total} $pageCounts '
        'cursor=$cursor→${response.cursor} hasMore=${response.hasMore} '
        'in ${applied.elapsedMilliseconds}ms rid=${page.requestId}',
      );
      if (outcome.kept.total > 0) {
        _log.info(
          'pull page $number: local unsynced changes win over the server '
          'version (newer edit or pending delete) ${outcome.kept} '
          'rid=${page.requestId}',
        );
      }
      if (outcome.removed.isNotEmpty) {
        removedBudgets.addAll(outcome.removed);
        _budgetsRemoved(onRemoved, outcome.removed, reason, number);
      }
      cursor = syncedAt != null && response.cursor < stored
          ? stored
          : response.cursor;
      if (syncedAt != null) {
        final result = PullResult(
          reason: reason,
          pages: pages,
          counts: counts,
          cursorBefore: before,
          cursorAfter: cursor,
          syncedAt: syncedAt,
          elapsed: sw.elapsed,
          applyElapsed: applyElapsed,
          kept: kept,
          removedBudgets: List.unmodifiable(removedBudgets),
        );
        _log.info(
          'pull done reason=${reason.name} pages=$pages '
          'entities=${counts.total} $counts cursor=$before→$cursor '
          'in ${sw.elapsedMilliseconds}ms',
        );
        return result;
      }
    }
  }

  Future<int> _readCursor() async {
    final row = await (_db.select(
      _db.syncStates,
    )..where((s) => s.id.equals(0))).getSingleOrNull();
    if (row == null) {
      _log.warning(
        'sync_state row id=0 is missing → pulling from cursor=0, the row is '
        'created with the first page',
      );
      return 0;
    }
    return row.cursor;
  }

  Future<int?> rereadCursor(Iterable<RejectedEntity> rejected) async {
    final byEntity = <SyncEntity, Set<String>>{};
    for (final r in rejected) {
      (byEntity[r.entity] ??= <String>{}).add(r.id);
    }
    int? lowest;
    var unknown = 0;
    for (final MapEntry(key: entity, value: ids) in byEntity.entries) {
      final seqs = await _serverSeqs(entity, ids.toList());
      unknown += ids.length - seqs.length;
      for (final seq in seqs.values) {
        if (lowest == null || seq < lowest) lowest = seq;
      }
    }
    final from = lowest == null ? null : (lowest > 0 ? lowest - 1 : 0);
    _log.fine(
      'rejected changes re-read plan entities=${rejected.length} '
      'neverPulled=$unknown from=${from ?? '-'}',
    );
    return from;
  }

  Future<Map<String, int>> _serverSeqs(
    SyncEntity entity,
    List<String> ids,
  ) async {
    final (
      TableInfo<Table, Object?> table,
      Expression<String> id,
      Expression<int> seq,
    ) = switch (entity) {
      SyncEntity.budget => (_db.budgets, _db.budgets.id, _db.budgets.serverSeq),
      SyncEntity.category => (
        _db.categories,
        _db.categories.id,
        _db.categories.serverSeq,
      ),
      SyncEntity.recurring => (
        _db.recurringRules,
        _db.recurringRules.id,
        _db.recurringRules.serverSeq,
      ),
      SyncEntity.expense => (
        _db.expenses,
        _db.expenses.id,
        _db.expenses.serverSeq,
      ),
    };
    final query = _db.selectOnly(table)
      ..addColumns([id, seq])
      ..where(id.isIn(ids) & seq.isNotNull());
    return {for (final row in await query.get()) row.read(id)!: row.read(seq)!};
  }

  Future<String?> _selectedBefore(
    SelectedBudgetReader? read,
    PullReason reason,
    int page,
  ) async {
    if (read == null) return null;
    try {
      return await read();
    } catch (e, st) {
      final error = redactDbError(e);
      _log.warning(
        'pull reason=${reason.name} page=$page: selected budget not read '
        'before removing budgets → treated as not selected: '
        '${describeError(error)}',
        error,
        st,
      );
      return null;
    }
  }

  void _budgetsRemoved(
    BudgetsRemovedHandler? handler,
    List<RemovedBudget> removed,
    PullReason reason,
    int page,
  ) {
    if (handler == null) return;
    try {
      handler(removed);
    } catch (e, st) {
      _log.severe(
        'pull reason=${reason.name} page=$page: budgets removed '
        '[${[for (final r in removed) r.budgetId].join(',')}], but the '
        'notice handler failed: ${describeError(e)}',
        e,
        st,
      );
    }
  }

  Future<_Applied> _apply(
    SyncPullResponse page, {
    DateTime? syncedAt,
    String? selected,
    int floor = 0,
  }) => _db.transaction(() async {
    var kept = const _Kept();
    if (page.budgets.isNotEmpty) {
      final guarded = await _guard(
        SyncEntity.budget,
        page.budgets,
        _localBudgets,
        (b, deletedAt) => b.copyWith(deletedAt: deletedAt),
      );
      kept += guarded.kept;
      if (guarded.apply.isNotEmpty) {
        await _budgets.applyFromServer(guarded.apply);
      }
    }
    if (page.members.isNotEmpty) {
      await _members.applyMembersFromServer(page.members);
    }
    if (page.profiles.isNotEmpty) {
      await _members.applyProfilesFromServer(page.profiles);
    }
    if (page.categories.isNotEmpty) {
      final guarded = await _guard(
        SyncEntity.category,
        page.categories,
        _localCategories,
        (c, deletedAt) => c.copyWith(deletedAt: deletedAt),
      );
      kept += guarded.kept;
      if (guarded.apply.isNotEmpty) {
        await _categories.applyFromServer(guarded.apply);
      }
    }
    if (page.recurring.isNotEmpty) {
      final guarded = await _guard(
        SyncEntity.recurring,
        page.recurring,
        _localRecurring,
        (r, deletedAt) => r.copyWith(deletedAt: deletedAt),
      );
      kept += guarded.kept;
      if (guarded.apply.isNotEmpty) {
        await _recurring.applyFromServer(guarded.apply);
      }
    }
    if (page.expenses.isNotEmpty) {
      final guarded = await _guard(
        SyncEntity.expense,
        page.expenses,
        _localExpenses,
        (e, deletedAt) => e.copyWith(deletedAt: deletedAt),
      );
      kept += guarded.kept;
      if (guarded.apply.isNotEmpty) {
        await _expenses.applyFromServer(guarded.apply);
      }
    }
    var removed = const <RemovedBudget>[];
    if (page.removedBudgetIds.isNotEmpty) {
      removed = await _removedInfo(page.removedBudgetIds, selected);
      await _budgets.removeBudgetData(page.removedBudgetIds);
    }
    await _saveState(
      SyncStatesCompanion(
        cursor: Value(page.cursor < floor ? floor : page.cursor),
        lastSyncAt: syncedAt == null ? const Value.absent() : Value(syncedAt),
        lastError: syncedAt == null ? const Value.absent() : const Value(null),
      ),
    );
    return _Applied(kept: kept, removed: removed);
  });

  Future<List<RemovedBudget>> _removedInfo(
    List<String> ids,
    String? selected,
  ) async {
    final rows = await (_db.select(
      _db.budgets,
    )..where((b) => b.id.isIn(ids))).get();
    return [
      for (final row in rows)
        RemovedBudget(
          budgetId: row.id,
          name: row.name,
          kind: row.kind,
          ownerId: row.ownerId,
          wasSelected: row.id == selected,
        ),
    ];
  }

  Future<({List<T> apply, _Kept kept})> _guard<T extends SyncRecord>(
    SyncEntity entity,
    List<T> incoming,
    Future<Map<String, _LocalVersion>> Function(List<String> ids) locals,
    T Function(T record, DateTime deletedAt) asTombstone,
  ) async {
    final pending = await _pendingOf(entity, [for (final r in incoming) r.id]);
    if (pending.isEmpty) return (apply: incoming, kept: const _Kept());
    final local = await locals(pending.keys.toList());
    final apply = <T>[];
    var keptCount = 0;
    var merged = 0;
    for (final record in incoming) {
      final waiting = pending[record.id];
      final mine = local[record.id];
      if (waiting == null || mine == null || record.deletedAt != null) {
        apply.add(record);
        continue;
      }
      final localDeletedAt = mine.deletedAt;
      if (localDeletedAt != null) {
        final lastEdit = waiting.lastEdit;
        if (lastEdit != null && !record.updatedAt.isAfter(lastEdit)) {
          keptCount++;
        } else {
          apply.add(asTombstone(record, localDeletedAt));
          merged++;
        }
      } else if (mine.updatedAt.isAfter(record.updatedAt)) {
        keptCount++;
      } else {
        apply.add(record);
      }
    }
    return (
      apply: apply,
      kept: _Kept.of(entity, kept: keptCount, merged: merged),
    );
  }

  Future<Map<String, _Waiting>> _pendingOf(
    SyncEntity entity,
    List<String> ids,
  ) async {
    final o = _db.outbox;
    final query = _db.selectOnly(o)
      ..addColumns([o.entityId, o.op, o.createdAt])
      ..where(o.entity.equalsValue(entity) & o.entityId.isIn(ids));
    final waiting = <String, _Waiting>{};
    for (final row in await query.get()) {
      final id = row.read(o.entityId)!;
      final current = waiting[id] ?? const _Waiting();
      waiting[id] = row.readWithConverter(o.op) == SyncOp.upsert
          ? current.edit(row.readWithConverter(o.createdAt)!)
          : current;
    }
    return waiting;
  }

  Future<Map<String, _LocalVersion>> _localBudgets(List<String> ids) async => {
    for (final r in await (_db.select(
      _db.budgets,
    )..where((t) => t.id.isIn(ids))).get())
      r.id: (updatedAt: r.updatedAt, deletedAt: r.deletedAt),
  };

  Future<Map<String, _LocalVersion>> _localCategories(List<String> ids) async =>
      {
        for (final r in await (_db.select(
          _db.categories,
        )..where((t) => t.id.isIn(ids))).get())
          r.id: (updatedAt: r.updatedAt, deletedAt: r.deletedAt),
      };

  Future<Map<String, _LocalVersion>> _localRecurring(List<String> ids) async =>
      {
        for (final r in await (_db.select(
          _db.recurringRules,
        )..where((t) => t.id.isIn(ids))).get())
          r.id: (updatedAt: r.updatedAt, deletedAt: r.deletedAt),
      };

  Future<Map<String, _LocalVersion>> _localExpenses(List<String> ids) async => {
    for (final r in await (_db.select(
      _db.expenses,
    )..where((t) => t.id.isIn(ids))).get())
      r.id: (updatedAt: r.updatedAt, deletedAt: r.deletedAt),
  };

  Future<void> _saveState(SyncStatesCompanion values) async {
    final updated = await (_db.update(
      _db.syncStates,
    )..where((s) => s.id.equals(0))).write(values);
    if (updated == 0) {
      await _db
          .into(_db.syncStates)
          .insert(values.copyWith(id: const Value(0)));
    }
  }

  Future<PullFailure> _failed(
    Stopwatch sw, {
    required PullReason reason,
    required PullStage stage,
    required int page,
    required int cursor,
    required int pagesApplied,
    required int attempt,
    required Object error,
    required StackTrace stackTrace,
    String? requestId,
  }) async {
    final failure = PullFailure(
      reason: reason,
      stage: stage,
      page: page,
      cursor: cursor,
      pagesApplied: pagesApplied,
      attempt: attempt,
      error: error,
      requestId: requestId,
    );
    final kept = pagesApplied == 0
        ? 'nothing applied'
        : '$pagesApplied page(s) applied and kept';
    final lost = switch (stage) {
      PullStage.prepare => 'cursor not read',
      PullStage.request => 'page $page not received',
      PullStage.apply => 'page $page rolled back',
    };
    _log.log(
      failure.expected ? Level.WARNING : Level.SEVERE,
      'pull failed reason=${reason.name} stage=${stage.name} page=$page '
      'cursor=$cursor attempt=$attempt ${failure.description} '
      'rid=${requestId ?? '-'} after ${sw.elapsedMilliseconds}ms → $kept, $lost, local data kept',
      error,
      stackTrace,
    );
    await _rememberError(failure);
    return failure;
  }

  Future<void> _rememberError(PullFailure failure) async {
    var text =
        '${failure.stage.name} ${failure.description} '
        'rid=${failure.requestId ?? '-'}';
    if (text.length > _lastErrorLength) {
      text = '${text.substring(0, _lastErrorLength)}…';
    }
    try {
      await _saveState(SyncStatesCompanion(lastError: Value(text)));
    } catch (e, st) {
      final error = redactDbError(e);
      _log.warning(
        'pull failure not saved to sync_state.lastError '
        'reason=${failure.reason.name}: ${describeError(error)}',
        error,
        st,
      );
    }
  }
}

typedef _LocalVersion = ({DateTime updatedAt, DateTime? deletedAt});

final class _Waiting {
  const _Waiting({this.lastEdit});

  final DateTime? lastEdit;

  _Waiting edit(DateTime at) {
    final last = lastEdit;
    return _Waiting(lastEdit: last == null || at.isAfter(last) ? at : last);
  }
}

final class _Kept {
  const _Kept({this.kept = const {}, this.merged = const {}});

  factory _Kept.of(
    SyncEntity entity, {
    required int kept,
    required int merged,
  }) => _Kept(
    kept: {if (kept > 0) entity: kept},
    merged: {if (merged > 0) entity: merged},
  );

  final Map<SyncEntity, int> kept;
  final Map<SyncEntity, int> merged;

  int get total =>
      kept.values.fold(0, (a, b) => a + b) +
      merged.values.fold(0, (a, b) => a + b);

  _Kept operator +(_Kept other) =>
      _Kept(kept: _sum(kept, other.kept), merged: _sum(merged, other.merged));

  static Map<SyncEntity, int> _sum(
    Map<SyncEntity, int> a,
    Map<SyncEntity, int> b,
  ) => {
    for (final entity in SyncEntity.values)
      if ((a[entity] ?? 0) + (b[entity] ?? 0) > 0)
        entity: (a[entity] ?? 0) + (b[entity] ?? 0),
  };

  @override
  String toString() {
    String part(Map<SyncEntity, int> counts) => counts.isEmpty
        ? '-'
        : [for (final e in counts.entries) '${e.key.name}=${e.value}']
              .join(',');
    return 'kept=${part(kept)} tombstonesWithServerData=${part(merged)}';
  }
}

final class _Applied {
  const _Applied({required this.kept, required this.removed});

  final _Kept kept;
  final List<RemovedBudget> removed;
}
