import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../core/clock.dart';
import '../../data/db/redact_db_error.dart';
import '../../data/providers.dart';

final _log = Logger('expense');

enum NewExpenseDateSource { today, route }

typedef ResolvedExpenseDate = ({
  LocalDate date,
  NewExpenseDateSource source,
  String? rejected,
});

const int _maxLoggedParameter = 32;

ResolvedExpenseDate resolveExpenseDate(String? requested, LocalDate today) {
  if (requested == null || requested.isEmpty) {
    return (date: today, source: NewExpenseDateSource.today, rejected: null);
  }
  final parsed = LocalDate.tryParse(requested);
  if (parsed == null) {
    return (
      date: today,
      source: NewExpenseDateSource.today,
      rejected: 'not a yyyy-mm-dd date',
    );
  }
  if (parsed.isAfter(today)) {
    return (
      date: today,
      source: NewExpenseDateSource.today,
      rejected: 'future date, expenses are recorded by fact',
    );
  }
  return (date: parsed, source: NewExpenseDateSource.route, rejected: null);
}

final class NewExpenseState {
  const NewExpenseState({
    required this.input,
    required this.date,
    this.saving = false,
  });

  final KeypadInput input;
  final LocalDate date;
  final bool saving;

  NewExpenseState copyWith({KeypadInput? input, bool? saving}) =>
      NewExpenseState(
        input: input ?? this.input,
        date: date,
        saving: saving ?? this.saving,
      );
}

enum NewExpenseSave { saved, zeroAmount, busy, noBudget, failed }

final class NewExpenseController extends Notifier<NewExpenseState> {
  NewExpenseController(this.requestedDate);

  final String? requestedDate;

  @override
  NewExpenseState build() {
    final today = ref.read(clockProvider).today();
    final resolved = resolveExpenseDate(requestedDate, today);
    final rejected = resolved.rejected;
    if (rejected != null) {
      final raw = requestedDate!;
      final shown = raw.length > _maxLoggedParameter
          ? '${raw.substring(0, _maxLoggedParameter)}… (${raw.length} chars)'
          : raw;
      _log.warning(
        'new expense date parameter "$shown" ignored: $rejected, '
        'using today=$today',
      );
    }
    _log.fine(
      'new expense opened date=${resolved.date} '
      'from=${resolved.source.name} today=$today',
    );
    return NewExpenseState(input: KeypadInput.empty, date: resolved.date);
  }

  bool digit(int digit) => _apply('digit $digit', state.input.digit(digit));

  bool comma() => _apply('comma', state.input.comma());

  bool backspace() => _apply('backspace', state.input.backspace());

  bool clear() {
    if (state.input.isEmpty) {
      _log.fine('keypad clear ignored: amount is already empty');
      return false;
    }
    state = state.copyWith(input: KeypadInput.empty);
    _log.fine('keypad clear: amount reset by long press on backspace');
    return true;
  }

  bool _apply(String key, KeypadInput? next) {
    final current = state.input;
    if (state.saving) {
      _log.fine('keypad $key ignored: expense is being saved');
      return false;
    }
    if (next == null) {
      _log.fine(
        'keypad $key rejected: ${_rejectReason(key, current)} '
        'text=${current.text}',
      );
      return false;
    }
    state = state.copyWith(input: next);
    _log.fine('keypad $key → text=${next.text} kopecks=${next.amount.kopecks}');
    return true;
  }

  static String _rejectReason(String key, KeypadInput current) {
    if (key == 'backspace') return 'amount is empty';
    if (key == 'comma') return 'comma is already entered';
    if (current.text == '0') return 'no leading zeros';
    final comma = current.text.indexOf(',');
    if (comma >= 0 && current.text.length - comma - 1 >= 2) {
      return 'only 2 digits after comma';
    }
    return 'more than ${Money(maxExpenseKopecks).format()}';
  }

  Future<NewExpenseSave> save(Category category) async {
    final current = state;
    if (current.saving) {
      _log.fine(
        'expense save category=${category.id} ignored: previous save is '
        'in progress',
      );
      return NewExpenseSave.busy;
    }
    if (!current.input.canSave) {
      _log.fine(
        'expense save category=${category.id} rejected: amount is zero, '
        'nothing saved',
      );
      return NewExpenseSave.zeroAmount;
    }
    state = current.copyWith(saving: true);
    final sw = Stopwatch()..start();
    String? budgetId;
    try {
      budgetId = await ref.read(selectedBudgetIdProvider.future);
      if (budgetId == null) {
        _log.warning(
          'expense save category=${category.id} date=${current.date} '
          'failed: no budget selected',
        );
        if (ref.mounted) state = state.copyWith(saving: false);
        return NewExpenseSave.noBudget;
      }
      final expense = await ref
          .read(expensesRepositoryProvider)
          .create(
            budgetId: budgetId,
            categoryId: category.id,
            amount: current.input.amount,
            spentOn: current.date,
          );
      _log.info(
        'expense saved id=${expense.id} budgetId=$budgetId '
        'category=${category.id} date=${current.date} '
        'in ${sw.elapsedMilliseconds}ms',
      );
      _log.fine(
        'expense saved id=${expense.id} amountKopecks=${expense.amount.kopecks}',
      );
      return NewExpenseSave.saved;
    } catch (e, st) {
      var cause = e;
      while (cause is ProviderException) {
        cause = cause.exception;
      }
      final redacted = redactDbError(cause);
      _log.severe(
        'expense save failed budgetId=${budgetId ?? 'unknown'} '
        'category=${category.id} date=${current.date} '
        'after ${sw.elapsedMilliseconds}ms, nothing saved: '
        '${describeError(redacted)}',
        redacted,
        st,
      );
      if (ref.mounted) state = state.copyWith(saving: false);
      return NewExpenseSave.failed;
    }
  }
}

final newExpenseControllerProvider = NotifierProvider.autoDispose
    .family<NewExpenseController, NewExpenseState, String?>(
      NewExpenseController.new,
      name: 'newExpenseController',
    );
