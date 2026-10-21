import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../data/db/redact_db_error.dart';
import '../../data/providers.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/components/button.dart';
import '../../ui/components/chip.dart';
import '../../ui/components/fitting_text.dart';
import '../../ui/components/sheet.dart';
import '../../ui/components/text_field.dart';
import '../../ui/theme/app_text.dart';
import '../../ui/theme/app_theme.dart';
import 'expense_date_sheet.dart'
    show chipTapSlack, expenseSheetGap, expenseSheetLift;

final _log = Logger('expense');

const int commentChipMaxChars = 24;

const double _recentGap = 8;

String commentChipLabel(String comment) {
  final chars = comment.characters;
  if (chars.length <= commentChipMaxChars) return comment;
  return '${chars.take(commentChipMaxChars - 1).toString().trimRight()}…';
}

Future<String?> showExpenseCommentSheet(
  BuildContext context, {
  required String initial,
  required String? budgetId,
}) async {
  final sw = Stopwatch()..start();
  final root = Navigator.of(context, rootNavigator: true);
  _log.fine(
    'comment sheet opened length=${textLength(initial)} '
    'budgetId=${budgetId ?? '-'}',
  );
  final result = await showAppSheet<String>(
    root.context,
    builder: (context) => [
      ExpenseCommentSheet(initial: initial, budgetId: budgetId),
    ],
  );
  if (result == null) {
    _log.fine(
      'comment sheet closed without done after ${sw.elapsedMilliseconds}ms: '
      'back gesture, tap outside or swipe down, comment stays '
      'length=${textLength(initial)}',
    );
  } else {
    _log.fine(
      'comment sheet done length=${textLength(result)} '
      'after ${sw.elapsedMilliseconds}ms',
    );
  }
  return result;
}

final class _CommentLimit extends TextInputFormatter {
  final TextInputFormatter _limit = LengthLimitingTextInputFormatter(
    commentMaxLength,
    maxLengthEnforcement: MaxLengthEnforcement.enforced,
  );

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final result = _limit.formatEditUpdate(oldValue, newValue);
    if (result.text != newValue.text) {
      _log.fine(
        'comment input over max=$commentMaxLength: entered '
        '${textLength(newValue.text)} chars, kept ${textLength(result.text)}',
      );
    }
    return result;
  }
}

class ExpenseCommentSheet extends ConsumerStatefulWidget {
  const ExpenseCommentSheet({
    super.key,
    required this.initial,
    required this.budgetId,
  });

  final String initial;
  final String? budgetId;

  @override
  ConsumerState<ExpenseCommentSheet> createState() =>
      _ExpenseCommentSheetState();
}

class _ExpenseCommentSheetState extends ConsumerState<ExpenseCommentSheet> {
  late final TextEditingController _text = TextEditingController.fromValue(
    TextEditingValue(
      text: widget.initial,
      selection: TextSelection.collapsed(offset: widget.initial.length),
    ),
  );
  final TextInputFormatter _limit = _CommentLimit();
  late int _length = textLength(widget.initial);

  @override
  void initState() {
    super.initState();
    _text.addListener(_onText);
    final budgetId = widget.budgetId;
    if (budgetId == null) {
      _log.fine('comment sheet without budget: no recent comments');
      return;
    }
    ref.listenManual(
      recentCommentsProvider(budgetId),
      (previous, next) => _logRecent(budgetId, next),
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _text.removeListener(_onText);
    _text.dispose();
    super.dispose();
  }

  void _onText() {
    final length = textLength(_text.text);
    if (length == _length) return;
    setState(() => _length = length);
  }

  void _logRecent(String budgetId, AsyncValue<List<String>> next) {
    switch (next) {
      case AsyncData(value: final comments):
        _log.fine(
          'comment sheet recent budgetId=$budgetId count=${comments.length}',
        );
      case AsyncError(:final error, :final stackTrace):
        var cause = error;
        while (cause is ProviderException) {
          cause = cause.exception;
        }
        final redacted = redactDbError(cause);
        _log.severe(
          'comment sheet recent comments failed budgetId=$budgetId, sheet '
          'shown without them: ${describeError(redacted)}',
          redacted,
          stackTrace,
        );
      default:
    }
  }

  void _pick(int index, String comment) {
    _text.value = TextEditingValue(
      text: comment,
      selection: TextSelection.collapsed(offset: comment.length),
    );
    _log.fine('comment recent #$index picked length=${textLength(comment)}');
  }

  void _done() => Navigator.of(context).pop(normalizeText(_text.text));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final media = MediaQuery.of(context);
    final chipSlack = chipTapSlack(media.textScaler);
    final keyboard = math.max(
      0.0,
      media.viewInsets.bottom - media.viewPadding.bottom,
    );
    final budgetId = widget.budgetId;
    final recentValue = budgetId == null
        ? null
        : ref.watch(recentCommentsProvider(budgetId));
    final recent = recentValue == null || recentValue.hasError
        ? const <String>[]
        : recentValue.value ?? const <String>[];

    return Flexible(
      child: Transform.translate(
        offset: const Offset(0, -expenseSheetLift),
        child: Padding(
          padding: EdgeInsets.only(bottom: keyboard),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: FittingText(
                          l10n.expenseCommentTitle,
                          style: AppText.titleM.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      l10n.expenseCommentCounter(_length, commentMaxLength),
                      style: AppText.caption.tabular.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: expenseSheetGap),
                AppTextField(
                  label: l10n.expenseCommentLabel,
                  controller: _text,
                  autofocus: true,
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [_limit],
                  onSubmitted: (_) => _done(),
                ),
                if (recent.isNotEmpty) ...[
                  const SizedBox(height: expenseSheetGap),
                  Text(
                    l10n.expenseCommentRecent,
                    style: AppText.labelS.copyWith(color: colors.textTertiary),
                  ),
                  SizedBox(height: _recentGap - chipSlack),
                  Wrap(
                    spacing: _recentGap,
                    runSpacing: _recentGap - 2 * chipSlack,
                    children: [
                      for (final (i, comment) in recent.indexed)
                        AppChip(label: comment, onTap: () => _pick(i, comment)),
                    ],
                  ),
                  SizedBox(height: expenseSheetGap - chipSlack),
                ] else
                  const SizedBox(height: expenseSheetGap),
                AppButton(
                  label: l10n.expenseSheetDone,
                  expand: true,
                  onPressed: _done,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
