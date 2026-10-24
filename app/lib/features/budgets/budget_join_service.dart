import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../data/api/api_exception.dart';
import '../../data/api/budgets_api.dart';
import '../../data/db/redact_db_error.dart';
import '../../data/providers.dart';
import '../../data/sync/pull_service.dart';
import '../../data/sync/sync_engine.dart';

final _log = Logger('budgets');

enum BudgetJoinStage { request, pull, select }

sealed class BudgetJoinOutcome {
  const BudgetJoinOutcome();
}

final class BudgetJoined extends BudgetJoinOutcome {
  const BudgetJoined({
    required this.budgetId,
    required this.requestId,
    required this.categories,
    required this.expenses,
  });

  final String budgetId;
  final String requestId;
  final int categories;
  final int expenses;

  @override
  String toString() =>
      'BudgetJoined(budgetId=$budgetId categories=$categories '
      'expenses=$expenses rid=$requestId)';
}

final class BudgetJoinFailed extends BudgetJoinOutcome {
  const BudgetJoinFailed({
    required this.stage,
    this.budgetId,
    this.error,
    this.requestId,
  });

  final BudgetJoinStage stage;
  final String? budgetId;
  final Object? error;
  final String? requestId;

  bool get joinedOnServer => stage != BudgetJoinStage.request;

  bool get offline => switch (error) {
    ApiNetworkFailure() => true,
    ApiTimeout(phase: ApiTimeoutPhase.connect) => true,
    _ => false,
  };

  ApiErrorCode? get code => switch (error) {
    ApiErrorResponse(:final code) => code,
    _ => null,
  };

  bool get inviteNotFound => code == ApiErrorCode.inviteNotFound;

  @override
  String toString() =>
      'BudgetJoinFailed(stage=${stage.name} budgetId=${budgetId ?? '-'} '
      '${_describe(error)} rid=${requestId ?? '-'})';
}

class BudgetJoinService {
  BudgetJoinService(this._ref);

  final Ref _ref;

  Future<BudgetJoinOutcome> join({required String code}) async {
    final sw = Stopwatch()..start();
    final masked = maskInviteCode(code);
    final from = _ref.read(selectedBudgetIdProvider).value;
    _log.fine(
      'budget join start code=$masked open=${from ?? '-'} → '
      'POST $joinBudgetPath',
    );

    final JoinedBudgetReply reply;
    try {
      reply = await _ref.read(budgetsApiProvider).join(code: code);
    } on ApiException catch (e, st) {
      final ms = sw.elapsedMilliseconds;
      switch (e) {
        case ApiErrorResponse(:final statusCode, :final error)
            when error.code == ApiErrorCode.inviteNotFound.code:
          _log.info(
            'budget join rejected code=$masked reason=${error.code} '
            'status=$statusCode rid=${e.requestId} in ${ms}ms → error under '
            'the code field, not joined',
          );
        case ApiErrorResponse(:final statusCode, :final error):
          _log.warning(
            'budget join rejected code=$masked reason=${error.code} '
            'status=$statusCode rid=${e.requestId} in ${ms}ms → snackbar, '
            'not joined',
          );
        default:
          _log.warning(
            'budget join failed code=$masked ${e.runtimeType}: ${e.details} '
            'rid=${e.requestId} in ${ms}ms → snackbar, not joined on this '
            'phone; a retry with the same code is safe',
            e,
            st,
          );
      }
      return BudgetJoinFailed(
        stage: BudgetJoinStage.request,
        error: e,
        requestId: e.requestId,
      );
    } catch (e, st) {
      _log.severe(
        'budget join failed code=$masked before an answer in '
        '${sw.elapsedMilliseconds}ms → snackbar, not joined: '
        '${describeError(e)}',
        e,
        st,
      );
      return BudgetJoinFailed(stage: BudgetJoinStage.request, error: e);
    }
    final rid = reply.requestId;
    final budgetId = reply.budget.id;
    _log.fine(
      'budget join POST ok budgetId=$budgetId kind=${reply.budget.kind.name} '
      'status=${reply.statusCode} rid=$rid in ${sw.elapsedMilliseconds}ms → '
      'pull',
    );

    final PullResult? pull;
    try {
      pull = await _ref
          .read(syncEngineProvider)
          .pullNow(PullReason.budgetJoined);
    } on PullFailure catch (f) {
      final error = redactDbError(f.error);
      _log.warning(
        'budget join budgetId=$budgetId rid=$rid: pull failed '
        'stage=${f.stage.name} ${_describe(error)} '
        'pullRid=${f.requestId ?? '-'} in ${sw.elapsedMilliseconds}ms → '
        'snackbar, joined on the server but the budget is not on this phone '
        'yet',
        error,
      );
      return BudgetJoinFailed(
        stage: BudgetJoinStage.pull,
        budgetId: budgetId,
        error: error,
        requestId: f.requestId ?? rid,
      );
    } catch (e, st) {
      final error = redactDbError(e);
      _log.severe(
        'budget join budgetId=$budgetId rid=$rid: pull crashed in '
        '${sw.elapsedMilliseconds}ms → snackbar: ${describeError(error)}',
        error,
        st,
      );
      return BudgetJoinFailed(
        stage: BudgetJoinStage.pull,
        budgetId: budgetId,
        error: error,
        requestId: rid,
      );
    }
    if (pull == null) {
      _log.warning(
        'budget join budgetId=$budgetId rid=$rid: sync engine skipped the '
        'pull (no session or held) in ${sw.elapsedMilliseconds}ms → '
        'snackbar, budget is not on this phone yet',
      );
      return BudgetJoinFailed(
        stage: BudgetJoinStage.pull,
        budgetId: budgetId,
        requestId: rid,
      );
    }

    final int categories;
    final int expenses;
    try {
      final local = await _ref
          .read(budgetsRepositoryProvider)
          .watchById(budgetId)
          .first;
      if (local == null) {
        _log.warning(
          'budget join budgetId=$budgetId rid=$rid: pull done ${pull.counts} '
          'cursor=${pull.cursorAfter} but the budget is not in the local '
          'database in ${sw.elapsedMilliseconds}ms → snackbar, nothing '
          'selected',
        );
        return BudgetJoinFailed(
          stage: BudgetJoinStage.pull,
          budgetId: budgetId,
          requestId: rid,
        );
      }
      categories =
          (await _ref
                  .read(categoriesRepositoryProvider)
                  .watchByBudget(budgetId)
                  .first)
              .length;
      expenses =
          (await _ref
                  .read(expensesRepositoryProvider)
                  .watchByBudget(budgetId)
                  .first)
              .length;
    } catch (e, st) {
      final error = redactDbError(e);
      _log.severe(
        'budget join budgetId=$budgetId rid=$rid: reading the pulled budget '
        'failed in ${sw.elapsedMilliseconds}ms → snackbar: '
        '${describeError(error)}',
        error,
        st,
      );
      return BudgetJoinFailed(
        stage: BudgetJoinStage.pull,
        budgetId: budgetId,
        error: error,
        requestId: rid,
      );
    }

    try {
      await _ref
          .read(budgetSelectionProvider.notifier)
          .select(budgetId, from: from, by: 'budget join');
    } catch (e) {
      _log.warning(
        'budget join budgetId=$budgetId rid=$rid: pulled with '
        'categories=$categories expenses=$expenses, but the choice was not '
        'saved (${e.runtimeType}) in ${sw.elapsedMilliseconds}ms → snackbar, '
        'budgetId=${from ?? '-'} stays open',
      );
      return BudgetJoinFailed(
        stage: BudgetJoinStage.select,
        budgetId: budgetId,
        error: e,
        requestId: rid,
      );
    }

    _log.info(
      'budget join ok budgetId=$budgetId code=$masked '
      'status=${reply.statusCode} categories=$categories expenses=$expenses '
      'pulled=${pull.counts.total} cursor=${pull.cursorAfter} rid=$rid '
      'in ${sw.elapsedMilliseconds}ms → selected',
    );
    return BudgetJoined(
      budgetId: budgetId,
      requestId: rid,
      categories: categories,
      expenses: expenses,
    );
  }
}

String _describe(Object? error) => switch (error) {
  null => 'no error',
  final ApiException e => '${e.runtimeType}: ${e.details}',
  final Object e => describeError(e),
};

final budgetJoinServiceProvider = Provider<BudgetJoinService>(
  BudgetJoinService.new,
  name: 'budgetJoinService',
);
