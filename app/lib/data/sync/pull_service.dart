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

final class PullResult {
  const PullResult({
    required this.reason,
    required this.pages,
    required this.counts,
    required this.cursorBefore,
    required this.cursorAfter,
    required this.syncedAt,
    required this.elapsed,
  });

  final PullReason reason;
  final int pages;
  final PullCounts counts;
  final int cursorBefore;
  final int cursorAfter;
  final DateTime syncedAt;
  final Duration elapsed;

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

  Future<PullResult> pull(PullReason reason, {int attempt = 1}) async {
    final sw = Stopwatch()..start();
    final int before;
    try {
      before = await _readCursor();
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
      final applied = Stopwatch()..start();
      final syncedAt = response.hasMore ? null : normalizeInstant(_now());
      try {
        await _apply(response, syncedAt: syncedAt);
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
      _log.fine(
        'pull page $number applied in one transaction '
        'entities=${pageCounts.total} $pageCounts '
        'cursor=$cursor→${response.cursor} hasMore=${response.hasMore} '
        'in ${applied.elapsedMilliseconds}ms rid=${page.requestId}',
      );
      cursor = response.cursor;
      if (syncedAt != null) {
        final result = PullResult(
          reason: reason,
          pages: pages,
          counts: counts,
          cursorBefore: before,
          cursorAfter: cursor,
          syncedAt: syncedAt,
          elapsed: sw.elapsed,
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

  Future<void> _apply(
    SyncPullResponse page, {
    DateTime? syncedAt,
  }) => _db.transaction(() async {
    if (page.budgets.isNotEmpty) {
      await _budgets.applyFromServer(page.budgets);
    }
    if (page.members.isNotEmpty) {
      await _members.applyMembersFromServer(page.members);
    }
    if (page.profiles.isNotEmpty) {
      await _members.applyProfilesFromServer(page.profiles);
    }
    if (page.categories.isNotEmpty) {
      await _categories.applyFromServer(page.categories);
    }
    if (page.recurring.isNotEmpty) {
      await _recurring.applyFromServer(page.recurring);
    }
    if (page.expenses.isNotEmpty) {
      await _expenses.applyFromServer(page.expenses);
    }
    if (page.removedBudgetIds.isNotEmpty) {
      await _budgets.removeBudgetData(page.removedBudgetIds);
    }
    await _saveState(
      SyncStatesCompanion(
        cursor: Value(page.cursor),
        lastSyncAt: syncedAt == null ? const Value.absent() : Value(syncedAt),
        lastError: syncedAt == null ? const Value.absent() : const Value(null),
      ),
    );
  });

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
