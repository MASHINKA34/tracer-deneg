import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/icons/app_icon.dart';
import '../../ui/theme/app_theme.dart';
import 'expense_delete_controller.dart';

final _log = Logger('expense');

class ExpenseSwipeToDelete extends ConsumerWidget {
  const ExpenseSwipeToDelete({
    super.key,
    required this.expense,
    required this.from,
    required this.child,
  });

  final Expense expense;
  final String from;
  final Widget child;

  static const double _iconSize = 22;

  static const double _iconPadding = 20;

  Future<bool> _delete(WidgetRef ref, String how) {
    _log.fine('expense ${expense.id} $how in $from → delete with undo');
    return ref
        .read(expenseDeleteProvider.notifier)
        .delete(expense, from: '$from $how');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    return Semantics(
      customSemanticsActions: {
        CustomSemanticsAction(
          label: AppLocalizations.of(context).expenseEditDelete,
        ): () =>
            _delete(ref, 'talkback action'),
      },
      child: Dismissible(
        key: ValueKey<String>('expense-swipe-${expense.id}'),
        direction: DismissDirection.endToStart,
        resizeDuration: null,
        confirmDismiss: (_) => _delete(ref, 'swipe'),
        background: ColoredBox(
          color: colors.statusDanger,
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(end: _iconPadding),
              child: AppIcon(
                AppIcons.trash,
                size: _iconSize,
                color: colors.textInverse,
              ),
            ),
          ),
        ),
        child: child,
      ),
    );
  }
}
