import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../core/clock.dart';
import '../../data/db/redact_db_error.dart';
import '../../data/providers.dart';
import '../../data/repositories/expenses_repository.dart';
import '../../data/repositories/repository_errors.dart';

final _log = Logger('expense');

const Duration expenseNoticeDuration = Duration(seconds: 5);

sealed class ExpenseSnack {
  const ExpenseSnack();
}

final class ExpenseUndoOffer extends ExpenseSnack {
  const ExpenseUndoOffer({
    required this.expense,
    required this.from,
    required this.deletedAt,
  });

  final Expense expense;
  final String from;
  final DateTime deletedAt;

  DateTime get until => deletedAt.add(expenseUndoWindow);
}

enum ExpenseDeleteProblem { deleteFailed, undoFailed }

final class ExpenseDeleteNotice extends ExpenseSnack {
  const ExpenseDeleteNotice(this.problem);

  final ExpenseDeleteProblem problem;
}

final class ExpenseDeleteController extends Notifier<ExpenseSnack?> {
  Timer? _timer;

  @override
  ExpenseSnack? build() {
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  DateTime _now() => ref.read(clockProvider).now();

  void _show(ExpenseSnack snack, Duration lifetime) {
    _timer?.cancel();
    state = snack;
    _timer = Timer(lifetime.isNegative ? Duration.zero : lifetime, () {
      if (!ref.mounted || !identical(state, snack)) return;
      switch (snack) {
        case ExpenseUndoOffer(:final expense, :final deletedAt):
          _log.fine(
            'expense undo window expired id=${expense.id} after '
            '${_now().difference(deletedAt).inMilliseconds}ms: snackbar '
            'hidden, expense stays deleted, outbox delete is due',
          );
        case ExpenseDeleteNotice(:final problem):
          _log.fine('expense notice ${problem.name} hidden by timeout');
      }
      state = null;
    });
  }

  void _replaceOffer(String id) {
    if (state case ExpenseUndoOffer(:final expense)) {
      _log.fine(
        'expense undo offer id=${expense.id} replaced by id=$id: '
        'id=${expense.id} stays deleted',
      );
    }
  }

  Future<bool> delete(Expense expense, {required String from}) async {
    final id = expense.id;
    final sw = Stopwatch()..start();
    _log.fine(
      'expense delete requested id=$id from=$from '
      'kopecks=${expense.amount.kopecks}',
    );
    try {
      final tombstone = await ref.read(expensesRepositoryProvider).delete(id);
      if (!ref.mounted) return true;
      _replaceOffer(id);
      final offer = ExpenseUndoOffer(
        expense: expense,
        from: from,
        deletedAt: tombstone.deletedAt ?? _now(),
      );
      _show(offer, offer.until.difference(_now()));
      _log.info(
        'expense deleted id=$id budgetId=${expense.budgetId} from=$from in '
        '${sw.elapsedMilliseconds}ms, undo snackbar for '
        '${expenseUndoWindow.inSeconds}s',
      );
      return true;
    } on RepositoryException catch (e, st) {
      if (e.failure == RepositoryFailure.notFound) {
        _log.warning(
          'expense delete id=$id from=$from after ${sw.elapsedMilliseconds}ms: '
          'expense is already deleted or missing, nothing to undo',
        );
        return true;
      }
      _log.severe(
        'expense delete rejected id=$id from=$from after '
        '${sw.elapsedMilliseconds}ms, expense kept: ${e.code}',
        e,
        st,
      );
      _fail(ExpenseDeleteProblem.deleteFailed);
      return false;
    } catch (e, st) {
      final redacted = _redact(e);
      _log.severe(
        'expense delete failed id=$id from=$from after '
        '${sw.elapsedMilliseconds}ms, expense kept, error snackbar: '
        '${describeError(redacted)}',
        redacted,
        st,
      );
      _fail(ExpenseDeleteProblem.deleteFailed);
      return false;
    }
  }

  Future<bool> undo() async {
    final offer = state;
    if (offer is! ExpenseUndoOffer) {
      _log.fine('expense undo tap ignored: no undo offer is shown');
      return false;
    }
    _timer?.cancel();
    state = null;
    final id = offer.expense.id;
    final elapsed = _now().difference(offer.deletedAt);
    final inTime = elapsed < expenseUndoWindow;
    final sw = Stopwatch()..start();
    try {
      final undone = await ref.read(expensesRepositoryProvider).undoDelete(id);
      if (undone) {
        _log.info(
          'expense undo id=$id from=${offer.from} inTime=$inTime '
          'after ${elapsed.inMilliseconds}ms of '
          '${expenseUndoWindow.inMilliseconds}ms: expense restored in '
          '${sw.elapsedMilliseconds}ms',
        );
        return true;
      }
      _log.info(
        'expense undo id=$id from=${offer.from} inTime=$inTime '
        'after ${elapsed.inMilliseconds}ms of '
        '${expenseUndoWindow.inMilliseconds}ms: not restored, the undo '
        'window is over or the expense changed, it stays deleted',
      );
      _fail(ExpenseDeleteProblem.undoFailed);
      return false;
    } catch (e, st) {
      final redacted = _redact(e);
      _log.severe(
        'expense undo failed id=$id from=${offer.from} inTime=$inTime after '
        '${sw.elapsedMilliseconds}ms, expense stays deleted, error snackbar: '
        '${describeError(redacted)}',
        redacted,
        st,
      );
      _fail(ExpenseDeleteProblem.undoFailed);
      return false;
    }
  }

  void _fail(ExpenseDeleteProblem problem) {
    if (!ref.mounted) return;
    if (state case ExpenseUndoOffer(:final expense)) {
      _log.fine(
        'expense undo offer id=${expense.id} replaced by ${problem.name} '
        'notice: id=${expense.id} stays deleted',
      );
    }
    _show(ExpenseDeleteNotice(problem), expenseNoticeDuration);
  }

  static Object _redact(Object error) {
    var cause = error;
    while (cause is ProviderException) {
      cause = cause.exception;
    }
    return redactDbError(cause);
  }
}

final expenseDeleteProvider =
    NotifierProvider<ExpenseDeleteController, ExpenseSnack?>(
      ExpenseDeleteController.new,
      name: 'expenseDelete',
    );
