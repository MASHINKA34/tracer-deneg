import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../core/clock.dart';

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
}


final newExpenseControllerProvider = NotifierProvider.autoDispose
    .family<NewExpenseController, NewExpenseState, String?>(
      NewExpenseController.new,
      name: 'newExpenseController',
    );
