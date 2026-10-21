import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/components/button.dart';
import '../../ui/components/sheet.dart';
import '../../ui/tokens/tokens.g.dart';
import 'new_expense_screen.dart'
    show
        ExpenseAmountView,
        ExpenseKeypad,
        amountShakeDuration,
        caretBlinkInterval;

final _log = Logger('expense');

Future<Money?> showExpenseAmountSheet(
  BuildContext context, {
  required Money initial,
}) async {
  final sw = Stopwatch()..start();
  final root = Navigator.of(context, rootNavigator: true);
  _log.fine('amount sheet opened kopecks=${initial.kopecks}');
  final result = await showAppSheet<Money>(
    root.context,
    builder: (context) => [ExpenseAmountSheet(initial: initial)],
  );
  if (result == null) {
    _log.fine(
      'amount sheet closed without done after ${sw.elapsedMilliseconds}ms: '
      'back gesture, tap outside or swipe down, amount stays '
      'kopecks=${initial.kopecks}',
    );
  } else {
    _log.fine(
      'amount sheet done kopecks=${result.kopecks} '
      'after ${sw.elapsedMilliseconds}ms',
    );
  }
  return result;
}

class ExpenseAmountSheet extends StatefulWidget {
  const ExpenseAmountSheet({super.key, required this.initial});

  final Money initial;

  @override
  State<ExpenseAmountSheet> createState() => _ExpenseAmountSheetState();
}

class _ExpenseAmountSheetState extends State<ExpenseAmountSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: amountShakeDuration,
  );
  late KeypadInput _input = _initialInput();
  Timer? _blink;
  bool _caretOn = true;
  bool _animate = true;

  KeypadInput _initialInput() {
    final kopecks = widget.initial.kopecks;
    if (kopecks < 0 || kopecks > maxExpenseKopecks) {
      _log.warning(
        'amount sheet initial amount is out of range '
        'max=$maxExpenseKopecks, starting from empty input',
      );
      return KeypadInput.empty;
    }
    return KeypadInput.fromMoney(widget.initial);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animate = !MediaQuery.disableAnimationsOf(context);
    if (animate != _animate || _blink == null && animate) {
      _animate = animate;
      _caretOn = true;
      _startBlink();
    }
  }

  @override
  void dispose() {
    _blink?.cancel();
    _shake.dispose();
    super.dispose();
  }

  void _startBlink() {
    _blink?.cancel();
    _blink = null;
    if (!_animate) return;
    _blink = Timer.periodic(caretBlinkInterval, (_) {
      if (mounted) setState(() => _caretOn = !_caretOn);
    });
  }

  void _press(String key, KeypadInput? next, {bool shake = true}) {
    HapticFeedback.lightImpact();
    if (next == null) {
      _log.fine('amount sheet keypad $key rejected text=${_input.text}');
      if (shake && _animate) _shake.forward(from: 0);
      return;
    }
    setState(() {
      _input = next;
      _caretOn = true;
    });
    _startBlink();
    _log.fine(
      'amount sheet keypad $key → text=${next.text} '
      'kopecks=${next.amount.kopecks}',
    );
  }

  void _clear() {
    HapticFeedback.lightImpact();
    if (_input.isEmpty) {
      _log.fine('amount sheet clear ignored: amount is already empty');
      return;
    }
    setState(() => _input = KeypadInput.empty);
    _log.fine('amount sheet clear: amount reset by long press on backspace');
  }

  void _done() {
    if (!_input.canSave) {
      _log.fine('amount sheet done ignored: amount is zero');
      return;
    }
    Navigator.of(context).pop(_input.amount);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Flexible(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExpenseAmountView(input: _input, caretOn: _caretOn, shake: _shake),
            ExpenseKeypad(
              keyHeight: ExpenseKeypad.keyHeightFor(
                context,
                space: MediaQuery.sizeOf(context).height / 2,
                bottomInset: 0,
              ),
              bottomInset: 0,
              borderRadius: BorderRadius.circular(RadiusTokens.lg),
              onDigit: (d) => _press('digit $d', _input.digit(d)),
              onComma: () => _press('comma', _input.comma()),
              onBackspace: () =>
                  _press('backspace', _input.backspace(), shake: false),
              onClear: _clear,
            ),
            const SizedBox(height: 16),
            AppButton(
              label: l10n.expenseSheetDone,
              onPressed: _input.canSave ? _done : null,
              expand: true,
            ),
          ],
        ),
      ),
    );
  }
}
