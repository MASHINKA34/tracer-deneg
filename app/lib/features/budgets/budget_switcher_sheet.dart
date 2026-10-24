import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../core/clock.dart';
import '../../core/router.dart';
import '../../data/db/redact_db_error.dart';
import '../../data/providers.dart';
import '../../data/session/session_providers.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/components/category_badge.dart';
import '../../ui/components/fitting_text.dart';
import '../../ui/components/sheet.dart';
import '../../ui/components/snackbar.dart';
import '../../ui/icons/app_icon.dart';
import '../../ui/theme/app_text.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/tokens/tokens.g.dart';
import '../expense/expense_snackbar_layer.dart';
import '../profile/profile_budgets.dart';

final _log = Logger('budgets');

Duration? _noRetry(int retryCount, Object error) => null;

const EdgeInsets budgetSheetPadding = EdgeInsets.fromLTRB(12, 10, 12, 24);

const double budgetSheetSpacing = 12;

const List<String> _monthKeys = [
  'january',
  'february',
  'march',
  'april',
  'may',
  'june',
  'july',
  'august',
  'september',
  'october',
  'november',
  'december',
];

final switcherBudgetsProvider = StreamProvider.autoDispose<List<Budget>>(
  (ref) {
    final ownerId = ref.watch(sessionProvider.select((s) => s.userId));
    return ref
        .watch(budgetsRepositoryProvider)
        .watchAll()
        .map((budgets) => visibleBudgets(budgets, ownerId));
  },
  name: 'switcherBudgets',
  retry: _noRetry,
);

sealed class BudgetSheetChoice {
  const BudgetSheetChoice();
}

final class BudgetPicked extends BudgetSheetChoice {
  const BudgetPicked(this.budgetId);

  final String budgetId;

  @override
  String toString() => 'budgetId=$budgetId';
}

final class CreateSharedBudget extends BudgetSheetChoice {
  const CreateSharedBudget();

  @override
  String toString() => 'create shared budget';
}

final class JoinBudgetByCode extends BudgetSheetChoice {
  const JoinBudgetByCode();

  @override
  String toString() => 'join by invite code';
}

Object _cause(Object error) {
  var cause = error;
  while (cause is ProviderException) {
    cause = cause.exception;
  }
  return redactDbError(cause);
}

String budgetSpentLine(AppLocalizations l10n, Money total, YearMonth month) =>
    l10n.budgetSwitcherSpent(
      total.formatTotal(),
      l10n.monthPrepositional(_monthKeys[month.month - 1]),
    );

Future<BudgetSheetChoice?> showBudgetSheet(
  BuildContext context, {
  required String? current,
  required String purpose,
  bool actions = true,
}) async {
  final sw = Stopwatch()..start();
  final root = Navigator.of(context, rootNavigator: true);
  _log.fine(
    'budget sheet opened for=$purpose current=${current ?? '-'} '
    'actions=$actions',
  );
  final choice = await showAppSheet<BudgetSheetChoice>(
    root.context,
    padding: budgetSheetPadding,
    spacing: budgetSheetSpacing,
    builder: (context) => [
      BudgetSheet(
        current: current,
        actions: actions,
        onChoice: (choice) => Navigator.of(context).pop(choice),
      ),
    ],
  );
  if (choice == null) {
    _log.fine(
      'budget sheet for=$purpose closed without choice after '
      '${sw.elapsedMilliseconds}ms: back gesture, tap outside or swipe down',
    );
  } else {
    _log.fine(
      'budget sheet for=$purpose choice $choice after '
      '${sw.elapsedMilliseconds}ms',
    );
  }
  return choice;
}

Future<void> openBudgetSwitcher(BuildContext context, WidgetRef ref) async {
  final current = ref.read(selectedBudgetIdProvider).value;
  final selection = ref.read(budgetSelectionProvider.notifier);
  final choice = await showBudgetSheet(
    context,
    current: current,
    purpose: 'switcher',
  );
  if (!context.mounted) {
    if (choice != null) {
      _log.warning(
        'budget switcher choice $choice dropped: the main screen is gone',
      );
    }
    return;
  }
  final l10n = AppLocalizations.of(context);
  switch (choice) {
    case null:
      return;
    case BudgetPicked(:final budgetId) when budgetId == current:
      _log.fine(
        'budget switcher: budgetId=$budgetId is already open, nothing changes',
      );
    case BudgetPicked(:final budgetId):
      try {
        await selection.select(budgetId, from: current, by: 'switcher');
      } catch (e) {
        _log.fine(
          'budget switcher: budgetId=$budgetId not saved (${e.runtimeType}) '
          '→ snackbar, budgetId=${current ?? '-'} stays open',
        );
        if (context.mounted) {
          _snackbar(context, l10n.budgetSwitcherFailed);
        }
      }
    case CreateSharedBudget():
      _log.fine('budget switcher: $choice → ${AppRoutes.newBudget}');
      unawaited(context.push<void>(AppRoutes.newBudget));
    case JoinBudgetByCode():
      _log.fine('budget switcher: $choice is not available yet → snackbar');
      _snackbar(context, l10n.budgetSwitcherSoon);
  }
}

void _snackbar(BuildContext context, String text) => showAppSnackbar(
  context,
  text: text,
  margin: const EdgeInsets.fromLTRB(
    expenseSnackbarSide,
    0,
    expenseSnackbarSide,
    expenseSnackbarAboveAnchor,
  ),
);

class BudgetSheet extends ConsumerWidget {
  const BudgetSheet({
    super.key,
    required this.current,
    required this.onChoice,
    this.actions = true,
  });

  final String? current;
  final ValueChanged<BudgetSheetChoice> onChoice;
  final bool actions;

  static void _logBudgets(
    AsyncValue<List<Budget>>? previous,
    AsyncValue<List<Budget>> next,
  ) {
    switch (next) {
      case AsyncData(value: final budgets) when previous?.value == null:
        _log.fine(
          'budget sheet shows ${budgets.length} budgets '
          '(${budgets.where((b) => b.kind == BudgetKind.shared).length} '
          'shared)',
        );
      case AsyncError(:final error, :final stackTrace):
        final cause = _cause(error);
        _log.warning(
          'budget sheet list failed → «not loaded» text instead of budgets: '
          '${describeError(cause)}',
          cause,
          stackTrace,
        );
      default:
    }
  }

  static void _logProfiles(
    AsyncValue<Map<String, MemberProfile>>? previous,
    AsyncValue<Map<String, MemberProfile>> next,
  ) {
    if (next case AsyncError(:final error, :final stackTrace)) {
      final cause = _cause(error);
      _log.warning(
        'budget sheet member profiles failed → avatars without letters: '
        '${describeError(cause)}',
        cause,
        stackTrace,
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final mood = context.mood;
    ref.listen(switcherBudgetsProvider, _logBudgets);
    ref.listen(memberProfilesProvider, _logProfiles);
    final budgets = ref.watch(switcherBudgetsProvider);
    final list = budgets.value;
    final user = ref.watch(sessionProvider).user;
    final profiles = {
      if (user != null)
        user.userId: MemberProfile(
          userId: user.userId,
          displayName: user.displayName,
          avatarColor: CategoryColor.blue,
        ),
      ...?ref.watch(memberProfilesProvider).value,
    };
    final month = YearMonth.of(ref.watch(clockProvider).today());
    return Flexible(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Semantics(
                header: true,
                child: FittingText(
                  l10n.budgetSwitcherTitle,
                  style: AppText.titleM.copyWith(color: colors.textPrimary),
                ),
              ),
            ),
            const SizedBox(height: budgetSheetSpacing),
            Material(
              color: colors.bgSurface2,
              borderRadius: BorderRadius.circular(RadiusTokens.lg),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (budgets.hasError && list == null)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 18,
                        ),
                        child: FittingText(
                          l10n.budgetSwitcherLoadFailed,
                          style: AppText.bodyM.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    for (final budget in list ?? const <Budget>[])
                      BudgetSheetRow(
                        budget: budget,
                        month: month,
                        selected: budget.id == current,
                        profiles: profiles,
                        onTap: () => onChoice(BudgetPicked(budget.id)),
                      ),
                  ],
                ),
              ),
            ),
            if (actions) ...[
              const SizedBox(height: budgetSheetSpacing),
              Material(
                type: MaterialType.transparency,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ActionRow(
                        title: l10n.budgetSwitcherCreate,
                        leading: ProfileIconBox(
                          icon: AppIcons.plus,
                          background: mood.soft,
                          color: mood.accentStrong,
                        ),
                        titleColor: mood.accentStrong,
                        onTap: () => onChoice(const CreateSharedBudget()),
                      ),
                      _ActionRow(
                        title: l10n.budgetSwitcherJoin,
                        leading: ProfileIconBox(
                          icon: AppIcons.link,
                          background: colors.bgSurface2,
                          color: colors.textSecondary,
                        ),
                        onTap: () => onChoice(const JoinBudgetByCode()),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class BudgetSheetRow extends ConsumerWidget {
  const BudgetSheetRow({
    super.key,
    required this.budget,
    required this.month,
    required this.selected,
    required this.profiles,
    required this.onTap,
  });

  final Budget budget;
  final YearMonth month;
  final bool selected;
  final Map<String, MemberProfile> profiles;
  final VoidCallback onTap;

  void _logTotal(AsyncValue<Money> next) {
    if (next case AsyncError(:final error, :final stackTrace)) {
      final cause = _cause(error);
      _log.warning(
        'budget sheet month total budgetId=${budget.id} month=$month failed '
        '→ row without the amount: ${describeError(cause)}',
        cause,
        stackTrace,
      );
    }
  }

  void _logMembers(AsyncValue<List<BudgetMember>> next) {
    if (next case AsyncError(:final error, :final stackTrace)) {
      final cause = _cause(error);
      _log.warning(
        'budget sheet members budgetId=${budget.id} failed → row without '
        'members and avatars: ${describeError(cause)}',
        cause,
        stackTrace,
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final shared = budget.kind == BudgetKind.shared;
    final key = (budgetId: budget.id, month: month);
    ref.listen(monthTotalProvider(key), (previous, next) => _logTotal(next));
    final total = ref.watch(monthTotalProvider(key)).value;
    List<BudgetMember>? members = const [];
    if (shared) {
      ref.listen(
        budgetMembersProvider(budget.id),
        (previous, next) => _logMembers(next),
      );
      members = ref.watch(budgetMembersProvider(budget.id)).value;
    }
    final who = !shared
        ? l10n.budgetSwitcherOnlyYou
        : members == null
        ? null
        : l10n.budgetSwitcherMembers(members.length);
    final subtitle = [
      ?who,
      if (total != null) budgetSpentLine(l10n, total, month),
    ].join('$nbsp· ');
    final avatars = members != null && members.isNotEmpty
        ? ProfileMemberAvatars(
            members: members,
            profiles: profiles,
            ring: colors.bgSurface2,
          )
        : null;
    Widget? trailing;
    if (avatars != null && selected) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          avatars,
          const SizedBox(width: 12),
          const ProfileSelectedMark(),
        ],
      );
    } else if (selected) {
      trailing = const ProfileSelectedMark();
    } else {
      trailing = avatars;
    }
    return Semantics(
      button: true,
      selected: selected,
      label: subtitle.isEmpty ? budget.name : '${budget.name}, $subtitle',
      excludeSemantics: true,
      onTap: onTap,
      child: ProfileBudgetRow(
        leading: CategoryBadge(
          emoji: budget.emoji,
          color: profileBudgetColor(budget),
        ),
        title: budget.name,
        subtitle: subtitle.isEmpty ? null : subtitle,
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.title,
    required this.leading,
    required this.onTap,
    this.titleColor,
  });

  final String title;
  final Widget leading;
  final Color? titleColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: title,
    excludeSemantics: true,
    onTap: onTap,
    child: ProfileBudgetRow(
      leading: leading,
      title: title,
      titleColor: titleColor,
      onTap: onTap,
    ),
  );
}
