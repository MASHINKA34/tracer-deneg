import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../core/clock.dart';
import 'current_user.dart';
import 'db/app_database.dart';
import 'db/redact_db_error.dart';
import 'providers.dart';
import 'repositories/expenses_repository.dart';
import 'repositories/outbox_queue.dart';
import 'repositories/prefs_repository.dart';
import 'repositories/recurring_repository.dart';

final _log = Logger('recurring');

enum RecurringRunReason {
  startup('startup'),
  midnight('midnight'),
  dayChanged('day changed'),
  afterSync('after sync'),
  afterSave('after save'),
  background('background');

  const RecurringRunReason(this.label);

  final String label;
}

final class RecurringRunResult {
  const RecurringRunResult({
    required this.reason,
    required this.today,
    required this.rules,
    required this.created,
    required this.skippedExisting,
    required this.skippedDeleted,
    required this.failedRules,
    required this.elapsed,
    this.error,
  });

  final RecurringRunReason reason;
  final LocalDate today;
  final int rules;
  final int created;
  final int skippedExisting;
  final int skippedDeleted;
  final int failedRules;
  final Duration elapsed;
  final Object? error;

  int get skipped => skippedExisting + skippedDeleted;

  bool get ok => error == null && failedRules == 0;

  @override
  String toString() =>
      'RecurringRunResult(${reason.label} today=$today rules=$rules '
      'created=$created existing=$skippedExisting deleted=$skippedDeleted '
      'failedRules=$failedRules error=${error ?? '-'})';
}

final recurringServiceProvider = Provider<RecurringService>(
  (ref) => RecurringService(
    ref.watch(appDatabaseProvider),
    expenses: ref.watch(expensesRepositoryProvider),
    recurring: ref.watch(recurringRepositoryProvider),
    clock: ref.watch(clockProvider),
  ),
  name: 'recurringService',
);

final Expando<_RunQueue> _queues = Expando('recurring runs');

final class _RunQueue {
  Future<void> tail = Future.value();
  int pending = 0;
}

final class _Tally {
  int rules = 0;
  int created = 0;
  int skippedExisting = 0;
  int skippedDeleted = 0;
  int failedRules = 0;
}

final class RecurringService {
  RecurringService(
    this._db, {
    required this._expenses,
    required this._recurring,
    this._clock = const Clock(),
  });

  factory RecurringService.forDatabase(
    AppDatabase db, {
    Clock clock = const Clock(),
  }) {
    final outbox = DriftOutboxQueue(db, now: clock.now);
    final user = LocalPrefsCurrentUser(DriftPrefsRepository(db));
    return RecurringService(
      db,
      expenses: DriftExpensesRepository(
        db,
        currentUser: user,
        outbox: outbox,
        now: clock.now,
      ),
      recurring: DriftRecurringRepository(
        db,
        currentUser: user,
        outbox: outbox,
        now: clock.now,
      ),
      clock: clock,
    );
  }

  final AppDatabase _db;
  final ExpensesRepository _expenses;
  final RecurringRepository _recurring;
  final Clock _clock;

  Future<RecurringRunResult> afterSync() => run(RecurringRunReason.afterSync);

  Future<RecurringRunResult> forBackground() =>
      run(RecurringRunReason.background);

  Future<RecurringRunResult> run(RecurringRunReason reason) async {
    final queue = _queues[_db] ??= _RunQueue();
    final ahead = queue.pending;
    final previous = queue.tail;
    final done = Completer<void>();
    queue
      ..pending += 1
      ..tail = done.future;
    try {
      if (ahead > 0) {
        final waited = Stopwatch()..start();
        _log.fine(
          'run (${reason.label}) queued behind $ahead unfinished run(s)',
        );
        await previous;
        _log.fine(
          'run (${reason.label}) starts after waiting '
          '${waited.elapsedMilliseconds}ms',
        );
      }
      return await _generate(reason);
    } finally {
      queue.pending -= 1;
      done.complete();
    }
  }

  Future<RecurringRunResult> _generate(RecurringRunReason reason) async {
    final sw = Stopwatch()..start();
    final label = reason.label;
    final today = _clock.today();
    final tally = _Tally();
    var step = 'starting transaction';
    _log.fine('run ($label) started today=$today');
    try {
      await _db.transaction(() async {
        step = 'reading rules';
        await _generateIn(label, today, tally, (next) => step = next);
        step = 'committing';
      });
    } catch (e, st) {
      final error = redactDbError(e);
      _log.severe(
        'run ($label) failed today=$today step=$step '
        'after ${sw.elapsedMilliseconds}ms, transaction rolled back, '
        'nothing created: ${describeError(error)}',
        error,
        st,
      );
      return RecurringRunResult(
        reason: reason,
        today: today,
        rules: tally.rules,
        created: 0,
        skippedExisting: tally.skippedExisting,
        skippedDeleted: tally.skippedDeleted,
        failedRules: tally.failedRules,
        elapsed: sw.elapsed,
        error: error,
      );
    }
    final summary =
        'run ($label) today=$today rules=${tally.rules} '
        'created=${tally.created} '
        'skipped=${tally.skippedExisting + tally.skippedDeleted} '
        'existing=${tally.skippedExisting} deleted=${tally.skippedDeleted}';
    if (tally.failedRules == 0) {
      _log.info('$summary in ${sw.elapsedMilliseconds}ms');
    } else {
      _log.warning(
        '$summary failedRules=${tally.failedRules} '
        'in ${sw.elapsedMilliseconds}ms: errors above, failed rules retry '
        'on the next run',
      );
    }
    return RecurringRunResult(
      reason: reason,
      today: today,
      rules: tally.rules,
      created: tally.created,
      skippedExisting: tally.skippedExisting,
      skippedDeleted: tally.skippedDeleted,
      failedRules: tally.failedRules,
      elapsed: sw.elapsed,
    );
  }

  Future<void> _generateIn(
    String label,
    LocalDate today,
    _Tally tally,
    void Function(String step) step,
  ) async {
    var sw = Stopwatch()..start();
    final rules = await _recurring.liveRulesOfLiveBudgets();
    tally.rules = rules.length;
    _log.fine(
      'run ($label) rules read count=${rules.length} '
      'in ${sw.elapsedMilliseconds}ms',
    );

    final due = <({RecurringRule rule, List<String> ids})>[];
    for (final rule in rules) {
      try {
        due.add((
          rule: rule,
          ids: [
            for (final month in dueMonths(
              startMonth: rule.startMonth,
              dayOfMonth: rule.dayOfMonth,
              today: today,
            ))
              recurringExpenseId(rule.id, month),
          ],
        ));
      } catch (e, st) {
        tally.failedRules += 1;
        _log.severe(
          'run ($label) rule ${rule.id} skipped: charge months not computed '
          'budget=${rule.budgetId} day=${rule.dayOfMonth} '
          'month=${rule.startMonth}..${YearMonth.of(today)} today=$today: '
          '${describeError(e)}',
          e,
          st,
        );
      }
    }

    step('checking existing expenses');
    sw = Stopwatch()..start();
    final allIds = [for (final d in due) ...d.ids];
    final existing = await _expenses.existingByIds(allIds);
    final known = {...existing.live, ...existing.deleted};
    _log.fine(
      'run ($label) existing check ids=${allIds.length} '
      'live=${existing.live.length} deleted=${existing.deleted.length} '
      'in ${sw.elapsedMilliseconds}ms',
    );

    step('creating expenses');
    for (final (:rule, :ids) in due) {
      final planned = planRecurringExpenses(
        rule,
        today,
        existingExpenseIds: known,
      );
      final live = ids.where(existing.live.contains).length;
      final deleted = ids.where(existing.deleted.contains).length;
      tally
        ..skippedExisting += live
        ..skippedDeleted += deleted;
      final created = <YearMonth>[];
      for (final expense in planned) {
        try {
          await _expenses.createRecurring(rule, expense);
          created.add(expense.month);
          tally.created += 1;
        } catch (e, st) {
          tally.failedRules += 1;
          final error = redactDbError(e);
          _log.severe(
            'run ($label) rule ${rule.id} month=${expense.month} '
            'expense ${expense.id} not created, its changes rolled back, '
            'later months of this rule wait for the next run: '
            '${describeError(error)}',
            error,
            st,
          );
          break;
        }
      }
      _log.fine(
        'run ($label) rule ${rule.id} budget=${rule.budgetId} '
        'day=${rule.dayOfMonth} from=${rule.startMonth} due=${ids.length} '
        'created=${created.isEmpty ? '-' : created.join(',')} '
        'existing=$live deleted=$deleted',
      );
    }
  }
}
