import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../data/api/api_exception.dart';
import '../../data/api/budgets_api.dart';
import '../../data/db/redact_db_error.dart';
import '../../data/providers.dart';
import '../../data/sync/budget_removed_notice.dart';
import '../../data/sync/pull_service.dart';
import '../../data/sync/sync_engine.dart';
import 'budget_invite.dart';

final _log = Logger('budgets');

enum BudgetAction {
  invite('invite'),
  renewInvite('new invite'),
  leave('leave'),
  delete('delete'),
  removeMember('remove member');

  const BudgetAction(this.logName);

  final String logName;
}

sealed class BudgetActionOutcome {
  const BudgetActionOutcome({required this.action, required this.budgetId});

  final BudgetAction action;
  final String budgetId;
}

final class BudgetActionDone extends BudgetActionOutcome {
  const BudgetActionDone({
    required super.action,
    required super.budgetId,
    required this.requestId,
    required this.synced,
    this.invite,
  });

  final String requestId;
  final bool synced;
  final BudgetInvite? invite;

  @override
  String toString() =>
      'BudgetActionDone(${action.logName} budgetId=$budgetId '
      'synced=$synced${invite == null ? '' : ' $invite'} rid=$requestId)';
}

final class BudgetActionFailed extends BudgetActionOutcome {
  const BudgetActionFailed({
    required super.action,
    required super.budgetId,
    required this.error,
    this.requestId,
  });

  final Object error;
  final String? requestId;

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
      'BudgetActionFailed(${action.logName} budgetId=$budgetId '
      '${_describe(error)} rid=${requestId ?? '-'})';
}

class BudgetActionsService {
  BudgetActionsService(this._ref);

  final Ref _ref;

  Future<BudgetActionOutcome> invite(
    String budgetId, {
    required bool renew,
  }) async {
    final action = renew ? BudgetAction.renewInvite : BudgetAction.invite;
    final sw = Stopwatch()..start();
    _log.fine(
      'budget ${action.logName} start budgetId=$budgetId → POST '
      '${budgetInvitesPath(budgetId)}',
    );
    final InviteReply reply;
    try {
      reply = await _ref
          .read(budgetsApiProvider)
          .createInvite(budgetId: budgetId);
    } catch (e, st) {
      return _failed(action, budgetId, sw, e, st);
    }
    final invite = BudgetInvite(code: reply.code, expiresAt: reply.expiresAt);
    _ref.read(budgetInvitesProvider.notifier).remember(budgetId, invite);
    _log.info(
      'budget ${action.logName} ok budgetId=$budgetId '
      'code=${maskInviteCode(reply.code)} '
      'expiresAt=${encodeInstant(reply.expiresAt)} '
      'status=${reply.statusCode} rid=${reply.requestId} '
      'in ${sw.elapsedMilliseconds}ms',
    );
    return BudgetActionDone(
      action: action,
      budgetId: budgetId,
      requestId: reply.requestId,
      synced: true,
      invite: invite,
    );
  }

  Future<BudgetActionOutcome> leave(String budgetId) => _change(
    BudgetAction.leave,
    budgetId,
    PullReason.budgetLeft,
    (api) => api.leave(budgetId: budgetId),
    own: true,
  );

  Future<BudgetActionOutcome> delete(String budgetId) => _change(
    BudgetAction.delete,
    budgetId,
    PullReason.budgetDeleted,
    (api) => api.delete(budgetId: budgetId),
    own: true,
  );

  Future<BudgetActionOutcome> removeMember(String budgetId, String memberId) =>
      _change(
        BudgetAction.removeMember,
        budgetId,
        PullReason.memberRemoved,
        (api) => api.removeMember(budgetId: budgetId, userId: memberId),
        memberId: memberId,
      );

  Future<BudgetActionOutcome> _change(
    BudgetAction action,
    String budgetId,
    PullReason reason,
    Future<BudgetActionReply> Function(BudgetsApi api) request, {
    bool own = false,
    String? memberId,
  }) async {
    final sw = Stopwatch()..start();
    final who = memberId == null ? '' : ' memberId=$memberId';
    final notices = _ref.read(budgetRemovedNoticeProvider.notifier);
    _log.fine('budget ${action.logName} start budgetId=$budgetId$who');
    if (own) notices.expectOwnRemoval(budgetId);
    final BudgetActionReply reply;
    try {
      reply = await request(_ref.read(budgetsApiProvider));
    } catch (e, st) {
      if (own) notices.ownRemovalSettled(budgetId, removed: false);
      return _failed(action, budgetId, sw, e, st, who: who);
    }
    final rid = reply.requestId;
    _log.fine(
      'budget ${action.logName} done on the server budgetId=$budgetId$who '
      'status=${reply.statusCode} rid=$rid in ${sw.elapsedMilliseconds}ms → '
      'pull reason=${reason.name}',
    );
    if (own) {
      _ref
          .read(budgetInvitesProvider.notifier)
          .forget(budgetId, reason: action.logName);
    }
    final synced = await _pull(action, budgetId, reason, rid, sw);
    if (own) {
      if (synced) notices.ownRemovalSettled(budgetId, removed: true);
      await _ref.read(budgetSelectionProvider.notifier).forgetGone(budgetId);
    }
    _log.info(
      'budget ${action.logName} ok budgetId=$budgetId$who '
      'status=${reply.statusCode} synced=$synced rid=$rid '
      'in ${sw.elapsedMilliseconds}ms',
    );
    return BudgetActionDone(
      action: action,
      budgetId: budgetId,
      requestId: rid,
      synced: synced,
    );
  }

  Future<bool> _pull(
    BudgetAction action,
    String budgetId,
    PullReason reason,
    String rid,
    Stopwatch sw,
  ) async {
    try {
      final pull = await _ref.read(syncEngineProvider).pullNow(reason);
      if (pull == null) {
        _log.warning(
          'budget ${action.logName} budgetId=$budgetId rid=$rid: done on the '
          'server, sync engine skipped the pull (no session or held) in '
          '${sw.elapsedMilliseconds}ms → the phone catches up on the next sync',
        );
        return false;
      }
      _log.fine(
        'budget ${action.logName} budgetId=$budgetId rid=$rid: pulled '
        '${pull.counts} removedBudgets=${pull.removedBudgets.length} '
        'cursor=${pull.cursorAfter}',
      );
      return true;
    } on PullFailure catch (f) {
      final error = redactDbError(f.error);
      _log.warning(
        'budget ${action.logName} budgetId=$budgetId rid=$rid: done on the '
        'server, pull failed stage=${f.stage.name} ${_describe(error)} '
        'pullRid=${f.requestId ?? '-'} in ${sw.elapsedMilliseconds}ms → the '
        'phone catches up on the next sync',
        error,
      );
      return false;
    } catch (e, st) {
      final error = redactDbError(e);
      _log.severe(
        'budget ${action.logName} budgetId=$budgetId rid=$rid: done on the '
        'server, pull crashed in ${sw.elapsedMilliseconds}ms: '
        '${describeError(error)}',
        error,
        st,
      );
      return false;
    }
  }

  BudgetActionFailed _failed(
    BudgetAction action,
    String budgetId,
    Stopwatch sw,
    Object error,
    StackTrace st, {
    String who = '',
  }) {
    final ms = sw.elapsedMilliseconds;
    switch (error) {
      case final ApiErrorResponse e
          when e.statusCode == 403 || e.statusCode == 404:
        _log.info(
          'budget ${action.logName} rejected budgetId=$budgetId$who '
          'reason=${e.error.code} status=${e.statusCode} rid=${e.requestId} '
          'in ${ms}ms → snackbar, role or membership on this phone is stale, '
          'pull reason=${PullReason.budgetDenied.name}',
        );
        unawaited(_refresh(action, budgetId));
      case final ApiErrorResponse e:
        _log.warning(
          'budget ${action.logName} rejected budgetId=$budgetId$who '
          'reason=${e.error.code} status=${e.statusCode} rid=${e.requestId} '
          'in ${ms}ms → snackbar, nothing changed',
        );
      case final ApiException e:
        _log.warning(
          'budget ${action.logName} failed budgetId=$budgetId$who '
          '${e.runtimeType}: ${e.details} rid=${e.requestId} '
          'in ${ms}ms → snackbar, a retry is safe',
          e,
          st,
        );
      default:
        _log.severe(
          'budget ${action.logName} failed budgetId=$budgetId$who before an '
          'answer in ${ms}ms → snackbar: ${describeError(error)}',
          error,
          st,
        );
    }
    return BudgetActionFailed(
      action: action,
      budgetId: budgetId,
      error: error,
      requestId: error is ApiException ? error.requestId : null,
    );
  }

  Future<void> _refresh(BudgetAction action, String budgetId) async {
    try {
      final pull = await _ref
          .read(syncEngineProvider)
          .pullNow(PullReason.budgetDenied);
      _log.fine(
        'budget ${action.logName} budgetId=$budgetId: refreshed after the '
        'refusal ${pull == null ? 'skipped (no session or held)' : '${pull.counts}'}',
      );
    } on PullFailure catch (f) {
      final error = redactDbError(f.error);
      _log.warning(
        'budget ${action.logName} budgetId=$budgetId: refresh after the '
        'refusal failed stage=${f.stage.name} ${_describe(error)} → roles '
        'catch up on the next sync',
        error,
      );
    } catch (e, st) {
      final error = redactDbError(e);
      _log.severe(
        'budget ${action.logName} budgetId=$budgetId: refresh after the '
        'refusal crashed: ${describeError(error)}',
        error,
        st,
      );
    }
  }
}

String _describe(Object? error) => switch (error) {
  null => 'no error',
  final ApiException e => '${e.runtimeType}: ${e.details}',
  final Object e => describeError(e),
};

final budgetActionsServiceProvider = Provider<BudgetActionsService>(
  BudgetActionsService.new,
  name: 'budgetActionsService',
);
