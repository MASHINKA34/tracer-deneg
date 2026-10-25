import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../core/clock.dart';
import '../../data/db/redact_db_error.dart';
import '../../data/providers.dart';

final _log = Logger('month');

enum MonthStepSource { arrow, swipe }

final class MonthController extends Notifier<YearMonth> {
  @override
  YearMonth build() {
    final today = ref.watch(clockProvider).today();
    final month = YearMonth.of(today);
    _log.fine('selected month=$month (current) today=$today');
    return month;
  }

  void previous(MonthStepSource source) {
    final from = state;
    state = from.previous;
    _log.fine('month $from → $state by=${source.name}');
  }

  bool next(MonthStepSource source) {
    final today = ref.read(clockProvider).today();
    final from = state;
    if (!canGoToNextMonth(from, today)) {
      _log.fine(
        'month next by=${source.name} ignored: $from is the current month, '
        '${from.next} is in the future today=$today',
      );
      return false;
    }
    state = from.next;
    _log.fine('month $from → $state by=${source.name}');
    return true;
  }

  bool open(YearMonth month) {
    final today = ref.read(clockProvider).today();
    final from = state;
    if (!canOpenMonth(month, today)) {
      _log.warning(
        'month open $month by=picker ignored: future month today=$today, '
        'staying on $from',
      );
      return false;
    }
    if (month == from) {
      _log.fine('month open $month by=picker: already shown');
      return true;
    }
    state = month;
    _log.fine('month $from → $state by=picker');
    return true;
  }

  void openCurrent({required String by}) {
    final today = ref.read(clockProvider).today();
    final current = YearMonth.of(today);
    final from = state;
    if (from == current) {
      _log.fine('month open current by=$by: $current is already shown');
      return;
    }
    state = current;
    _log.fine('month $from → $state by=$by (current month) today=$today');
  }
}

final monthControllerProvider = NotifierProvider<MonthController, YearMonth>(
  MonthController.new,
  name: 'monthController',
);

final class OpenDaySheet extends Notifier<LocalDate?> {
  @override
  LocalDate? build() => null;

  bool open(LocalDate day) {
    if (state != null) return false;
    state = day;
    return true;
  }

  void close(LocalDate day) {
    if (state == day) state = null;
  }
}

final openDaySheetProvider = NotifierProvider<OpenDaySheet, LocalDate?>(
  OpenDaySheet.new,
  name: 'openDaySheet',
);

final class MonthPickerOpen extends Notifier<bool> {
  @override
  bool build() => false;

  bool open() {
    if (state) return false;
    state = true;
    return true;
  }

  void close() => state = false;
}

final monthPickerOpenProvider = NotifierProvider<MonthPickerOpen, bool>(
  MonthPickerOpen.new,
  name: 'monthPickerOpen',
);

final class ShownMonth {
  const ShownMonth({
    required this.month,
    required this.budgetId,
    required this.dayTotals,
  });

  final YearMonth month;
  final String? budgetId;
  final Map<int, Money> dayTotals;
}

Duration? _noRetry(int retryCount, Object error) => null;

final shownMonthProvider = StreamProvider.autoDispose<ShownMonth>(
  _watchShownMonth,
  name: 'shownMonth',
  retry: _noRetry,
);

Stream<ShownMonth> _watchShownMonth(Ref ref) async* {
  final month = ref.watch(monthControllerProvider);
  final queries = ref.watch(monthQueriesProvider);
  final selected = ref.watch(selectedBudgetIdProvider.future);
  final sw = Stopwatch()..start();

  final String? budgetId;
  try {
    budgetId = await selected;
  } catch (e, st) {
    _logFailed('unknown', month, sw, 'selected budget unavailable', e, st);
    rethrow;
  }
  if (budgetId == null) {
    _log.fine(
      'month shown month=$month without budget: no budget selected, '
      'card without sums in ${sw.elapsedMilliseconds}ms',
    );
    yield ShownMonth(month: month, budgetId: null, dayTotals: const {});
    return;
  }

  var first = true;
  try {
    await for (final totals in queries.watchDayTotals(budgetId, month)) {
      if (first) {
        _log.fine(
          'month shown budgetId=$budgetId month=$month '
          'daysWithSpending=${totals.length} '
          'data built in ${sw.elapsedMilliseconds}ms',
        );
        first = false;
      } else {
        _log.fine(
          'month data updated budgetId=$budgetId month=$month '
          'daysWithSpending=${totals.length}',
        );
      }
      yield ShownMonth(month: month, budgetId: budgetId, dayTotals: totals);
    }
  } catch (e, st) {
    _logFailed(budgetId, month, sw, 'day totals stream failed', e, st);
    rethrow;
  }
}

void _logFailed(
  String budgetId,
  YearMonth month,
  Stopwatch sw,
  String what,
  Object error,
  StackTrace stackTrace,
) {
  var cause = error;
  while (cause is ProviderException) {
    cause = cause.exception;
  }
  final redacted = redactDbError(cause);
  _log.severe(
    'month data failed budgetId=$budgetId month=$month: $what '
    'after ${sw.elapsedMilliseconds}ms, showing card without sums: '
    '${describeError(redacted)}',
    redacted,
    stackTrace,
  );
}
