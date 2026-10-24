import 'dart:async';

import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import 'db/redact_db_error.dart';
import 'repositories/prefs_repository.dart';

final _log = Logger('budgets');

Stream<R> combineLatest<A, B, R>(
  Stream<A> first,
  Stream<B> second,
  R Function(A a, B b) combine,
) {
  late final StreamController<R> controller;
  StreamSubscription<A>? firstSub;
  StreamSubscription<B>? secondSub;
  late A lastFirst;
  late B lastSecond;
  var hasFirst = false;
  var hasSecond = false;
  var done = 0;

  void emit() {
    if (!hasFirst || !hasSecond) return;
    final R value;
    try {
      value = combine(lastFirst, lastSecond);
    } catch (e, st) {
      controller.addError(e, st);
      return;
    }
    controller.add(value);
  }

  void finished() {
    done++;
    if (done == 2) unawaited(controller.close());
  }

  controller = StreamController<R>(
    onListen: () {
      firstSub = first.listen(
        (value) {
          lastFirst = value;
          hasFirst = true;
          emit();
        },
        onError: controller.addError,
        onDone: finished,
      );
      secondSub = second.listen(
        (value) {
          lastSecond = value;
          hasSecond = true;
          emit();
        },
        onError: controller.addError,
        onDone: finished,
      );
    },
    onPause: () {
      firstSub?.pause();
      secondSub?.pause();
    },
    onResume: () {
      firstSub?.resume();
      secondSub?.resume();
    },
    onCancel: () => Future.wait([?firstSub?.cancel(), ?secondSub?.cancel()]),
  );
  return controller.stream;
}

final class BudgetSelection {
  BudgetSelection(this._prefs);

  final PrefsRepository _prefs;

  Future<void> select(
    String budgetId, {
    required String? from,
    required String by,
  }) async {
    final sw = Stopwatch()..start();
    try {
      await _prefs.setString(PrefKeys.selectedBudgetId, budgetId);
      _log.info(
        'selected budget changed budgetId=$budgetId from=${from ?? '-'} '
        'by=$by in ${sw.elapsedMilliseconds}ms',
      );
    } catch (e, st) {
      final error = redactDbError(e);
      _log.severe(
        'selected budget change failed budgetId=$budgetId '
        'from=${from ?? '-'} by=$by after ${sw.elapsedMilliseconds}ms, '
        'the previous budget stays open: ${describeError(error)}',
        error,
        st,
      );
      rethrow;
    }
  }

  Future<void> forgetGone(String budgetId) async {
    try {
      await _prefs.remove(PrefKeys.selectedBudgetId);
      _log.fine('stored choice budgetId=$budgetId cleared: the budget is gone');
    } catch (e, st) {
      final error = redactDbError(e);
      _log.warning(
        'stored choice budgetId=$budgetId not cleared: '
        '${describeError(error)} → personal budget is shown anyway, '
        'cleared on the next change',
        error,
        st,
      );
    }
  }
}
