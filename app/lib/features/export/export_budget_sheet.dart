import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../data/providers.dart';
import '../../data/session/session_providers.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/components/fitting_text.dart';
import '../../ui/components/radio.dart';
import '../../ui/components/sheet.dart';
import '../../ui/theme/app_text.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/tokens/tokens.g.dart';
import 'export_rows.dart';

final _log = Logger('export');

Duration? _noRetry(int retryCount, Object error) => null;

final exportBudgetsProvider = StreamProvider.autoDispose<List<Budget>>(
  (ref) {
    final ownerId = ref.watch(sessionProvider.select((s) => s.userId));
    return ref
        .watch(budgetsRepositoryProvider)
        .watchAll()
        .map((budgets) => visibleBudgets(budgets, ownerId));
  },
  name: 'exportBudgets',
  retry: _noRetry,
);

Future<String?> showExportBudgetSheet(
  BuildContext context, {
  required List<Budget> budgets,
  required String? current,
}) async {
  final sw = Stopwatch()..start();
  final root = Navigator.of(context, rootNavigator: true);
  _log.fine(
    'export budget sheet opened current=$current budgets=${budgets.length}',
  );
  final chosen = await showAppSheet<String>(
    root.context,
    builder: (context) => [
      ExportBudgetSheet(
        budgets: budgets,
        current: current,
        onSelected: (id) => Navigator.of(context).pop(id),
      ),
    ],
  );
  if (chosen == null) {
    _log.fine(
      'export budget sheet closed without choice after '
      '${sw.elapsedMilliseconds}ms: back gesture, tap outside or swipe down, '
      'budget stays $current',
    );
  } else {
    _log.fine(
      'export budget sheet choice budgetId=$chosen after '
      '${sw.elapsedMilliseconds}ms',
    );
  }
  return chosen;
}

class ExportBudgetSheet extends StatelessWidget {
  const ExportBudgetSheet({
    super.key,
    required this.budgets,
    required this.current,
    required this.onSelected,
  });

  final List<Budget> budgets;
  final String? current;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    return Flexible(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              header: true,
              child: FittingText(
                l10n.exportBudget,
                style: AppText.titleM.copyWith(color: colors.textPrimary),
              ),
            ),
            const SizedBox(height: 16),
            Material(
              color: colors.bgSurface2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(RadiusTokens.lg),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final budget in budgets)
                    _BudgetOption(
                      emoji: budget.emoji,
                      name: exportBudgetName(l10n, budget),
                      selected: budget.id == current,
                      onTap: () => onSelected(budget.id),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BudgetOption extends StatelessWidget {
  const _BudgetOption({
    required this.emoji,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final String emoji;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MergeSemantics(
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
            child: Row(
              children: [
                ExcludeSemantics(
                  child: Text(
                    emoji,
                    style: AppText.bodyL.copyWith(color: colors.textPrimary),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FittingText(
                    name,
                    style: AppText.bodyL.copyWith(color: colors.textPrimary),
                  ),
                ),
                AppRadio(selected: selected, onTap: onTap),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
