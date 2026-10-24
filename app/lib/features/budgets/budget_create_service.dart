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

enum BudgetCreateStage { request, pull, select }

sealed class BudgetCreateOutcome {
  const BudgetCreateOutcome({required this.budgetId});

  final String budgetId;
}

final class BudgetCreated extends BudgetCreateOutcome {
  const BudgetCreated({
    required super.budgetId,
    required this.requestId,
    required this.replayed,
    required this.categories,
  });

  final String requestId;
  final bool replayed;
  final int categories;

  @override
  String toString() =>
      'BudgetCreated(budgetId=$budgetId replayed=$replayed '
      'categories=$categories rid=$requestId)';
}

final class BudgetCreateFailed extends BudgetCreateOutcome {
  const BudgetCreateFailed({
    required super.budgetId,
    required this.stage,
    this.error,
    this.requestId,
  });

  final BudgetCreateStage stage;
  final Object? error;
  final String? requestId;

  bool get createdOnServer => stage != BudgetCreateStage.request;

  bool get offline => switch (error) {
    ApiNetworkFailure() => true,
    ApiTimeout(phase: ApiTimeoutPhase.connect) => true,
    _ => false,
  };

  ApiErrorCode? get code => switch (error) {
    ApiErrorResponse(:final code) => code,
    _ => null,
  };

  @override
  String toString() =>
      'BudgetCreateFailed(budgetId=$budgetId stage=${stage.name} '
      '${_describe(error)} rid=${requestId ?? '-'})';
}

class BudgetCreateService {
  BudgetCreateService(this._ref);

  final Ref _ref;

  Future<BudgetCreateOutcome> create({
    required String budgetId,
    required String name,
    required String emoji,
  }) async {
    final sw = Stopwatch()..start();
    final from = _ref.read(selectedBudgetIdProvider).value;
    _log.fine(
      'budget create start budgetId=$budgetId '
      'nameLength=${textLength(name)} open=${from ?? '-'} → POST $budgetsPath',
    );

    final CreatedBudgetReply reply;
    try {
      reply = await _ref
          .read(budgetsApiProvider)
          .create(id: budgetId, name: name, emoji: emoji);
    } on ApiException catch (e, st) {
      final ms = sw.elapsedMilliseconds;
      switch (e) {
        case ApiErrorResponse(:final statusCode, :final error):
          _log.info(
            'budget create rejected budgetId=$budgetId code=${error.code} '
            'status=$statusCode rid=${e.requestId} in ${ms}ms → snackbar, '
            'nothing created',
          );
        default:
          _log.warning(
            'budget create failed budgetId=$budgetId ${e.runtimeType}: '
            '${e.details} rid=${e.requestId} in ${ms}ms → snackbar, nothing '
            'created on this phone; a retry sends the same id',
            e,
            st,
          );
      }
      return BudgetCreateFailed(
        budgetId: budgetId,
        stage: BudgetCreateStage.request,
        error: e,
        requestId: e.requestId,
      );
    } catch (e, st) {
      _log.severe(
        'budget create failed budgetId=$budgetId before an answer in '
        '${sw.elapsedMilliseconds}ms → snackbar, nothing created: '
        '${describeError(e)}',
        e,
        st,
      );
      return BudgetCreateFailed(
        budgetId: budgetId,
        stage: BudgetCreateStage.request,
        error: e,
      );
    }
    final rid = reply.requestId;
    final result = reply.replayed ? 'replayed' : 'created';
    _log.fine(
      'budget create POST ok budgetId=$budgetId result=$result '
      'status=${reply.statusCode} rid=$rid in ${sw.elapsedMilliseconds}ms → '
      'pull',
    );

    final PullResult? pull;
    try {
      pull = await _ref
          .read(syncEngineProvider)
          .pullNow(PullReason.budgetCreated);
    } on PullFailure catch (f) {
      final error = redactDbError(f.error);
      _log.warning(
        'budget create budgetId=$budgetId result=$result rid=$rid: pull failed '
        'stage=${f.stage.name} ${_describe(error)} '
        'pullRid=${f.requestId ?? '-'} in ${sw.elapsedMilliseconds}ms → '
        'snackbar, budget is on the server but not on this phone yet',
        error,
      );
      return BudgetCreateFailed(
        budgetId: budgetId,
        stage: BudgetCreateStage.pull,
        error: error,
        requestId: f.requestId ?? rid,
      );
    } catch (e, st) {
      final error = redactDbError(e);
      _log.severe(
        'budget create budgetId=$budgetId result=$result rid=$rid: pull '
        'crashed in ${sw.elapsedMilliseconds}ms → snackbar: '
        '${describeError(error)}',
        error,
        st,
      );
      return BudgetCreateFailed(
        budgetId: budgetId,
        stage: BudgetCreateStage.pull,
        error: error,
        requestId: rid,
      );
    }
    if (pull == null) {
      _log.warning(
        'budget create budgetId=$budgetId result=$result rid=$rid: sync '
        'engine skipped the pull (no session or held) in '
        '${sw.elapsedMilliseconds}ms → snackbar, budget is not on this phone '
        'yet',
      );
      return BudgetCreateFailed(
        budgetId: budgetId,
        stage: BudgetCreateStage.pull,
        requestId: rid,
      );
    }

    final int categories;
    try {
      final local = await _ref
          .read(budgetsRepositoryProvider)
          .watchById(budgetId)
          .first;
      if (local == null) {
        _log.warning(
          'budget create budgetId=$budgetId result=$result rid=$rid: pull '
          'done ${pull.counts} cursor=${pull.cursorAfter} but the budget is '
          'not in the local database in ${sw.elapsedMilliseconds}ms → '
          'snackbar, nothing selected',
        );
        return BudgetCreateFailed(
          budgetId: budgetId,
          stage: BudgetCreateStage.pull,
          requestId: rid,
        );
      }
      categories =
          (await _ref
                  .read(categoriesRepositoryProvider)
                  .watchByBudget(budgetId)
                  .first)
              .length;
    } catch (e, st) {
      final error = redactDbError(e);
      _log.severe(
        'budget create budgetId=$budgetId result=$result rid=$rid: reading '
        'the pulled budget failed in ${sw.elapsedMilliseconds}ms → snackbar: '
        '${describeError(error)}',
        error,
        st,
      );
      return BudgetCreateFailed(
        budgetId: budgetId,
        stage: BudgetCreateStage.pull,
        error: error,
        requestId: rid,
      );
    }

    try {
      await _ref
          .read(budgetSelectionProvider.notifier)
          .select(budgetId, from: from, by: 'budget create');
    } catch (e) {
      _log.warning(
        'budget create budgetId=$budgetId result=$result rid=$rid: pulled '
        'with categories=$categories, but the choice was not saved '
        '(${e.runtimeType}) in ${sw.elapsedMilliseconds}ms → snackbar, '
        'budgetId=${from ?? '-'} stays open',
      );
      return BudgetCreateFailed(
        budgetId: budgetId,
        stage: BudgetCreateStage.select,
        error: e,
        requestId: rid,
      );
    }

    _log.info(
      'budget create ok budgetId=$budgetId result=$result '
      'status=${reply.statusCode} categories=$categories '
      'pulled=${pull.counts.total} cursor=${pull.cursorAfter} rid=$rid '
      'in ${sw.elapsedMilliseconds}ms → selected',
    );
    return BudgetCreated(
      budgetId: budgetId,
      requestId: rid,
      replayed: reply.replayed,
      categories: categories,
    );
  }
}

String _describe(Object? error) => switch (error) {
  null => 'no error',
  final ApiException e => '${e.runtimeType}: ${e.details}',
  final Object e => describeError(e),
};

final budgetCreateServiceProvider = Provider<BudgetCreateService>(
  BudgetCreateService.new,
  name: 'budgetCreateService',
);
