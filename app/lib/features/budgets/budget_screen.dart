import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../core/clock.dart';
import '../../core/router.dart';
import '../../data/api/api_error_text.dart';
import '../../data/api/api_exception.dart';
import '../../data/db/redact_db_error.dart';
import '../../data/providers.dart';
import '../../data/session/session.dart';
import '../../data/session/session_providers.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/components/dialog.dart';
import '../../ui/components/fitting_text.dart';
import '../../ui/components/list_row.dart';
import '../../ui/components/sheet.dart';
import '../../ui/components/snackbar.dart';
import '../../ui/icons/app_icon.dart';
import '../../ui/theme/app_text.dart';
import '../../ui/theme/app_theme.dart';
import '../expense/expense_snackbar_layer.dart';
import '../holidays/member_birthdays.dart';
import '../month/day_sheet.dart' show expenseCategory;
import '../profile/profile_budgets.dart' show ProfileCard;
import 'budget_actions_service.dart';
import 'budget_invite.dart';
import 'budget_screen_view.dart';
import 'expense_authors.dart';

final _log = Logger('budgets');

final _nav = Logger('nav');

const int budgetRecentLimit = 5;

enum BudgetScreenOpen { created }

Object _cause(Object error) {
  var cause = error;
  while (cause is ProviderException) {
    cause = cause.exception;
  }
  return redactDbError(cause);
}

List<BudgetMember> budgetMembersInOrder(List<BudgetMember> members) => [
  for (final m in members)
    if (m.role == MemberRole.owner) m,
  for (final m in members)
    if (m.role != MemberRole.owner) m,
];

String budgetMemberName(
  AppLocalizations l10n,
  BudgetMember member, {
  required SessionUser? user,
  required Map<String, MemberProfile> profiles,
}) {
  if (user != null && member.userId == user.userId) return user.displayName;
  return profiles[member.userId]?.displayName ?? l10n.budgetScreenSomeone;
}

String budgetActionFailureText(
  AppLocalizations l10n,
  BudgetActionFailed failure,
) => switch (failure.error) {
  final ApiException e => apiErrorText(l10n, e),
  _ => l10n.budgetScreenActionFailed,
};

class BudgetScreen extends ConsumerStatefulWidget {
  const BudgetScreen({
    super.key,
    required this.budgetId,
    this.inviteOnOpen = false,
  });

  final String budgetId;
  final bool inviteOnOpen;

  @override
  ConsumerState<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends ConsumerState<BudgetScreen> {
  final Stopwatch _sw = Stopwatch()..start();
  late bool _autoInvite = widget.inviteOnOpen;
  BudgetAction? _busy;
  Budget? _shown;
  bool _closing = false;
  bool _sharing = false;
  bool _menuOpen = false;
  bool _loggedShown = false;
  bool _inviteRevoked = false;
  String _closedBy = 'back';

  String get _id => widget.budgetId;

  @override
  void initState() {
    super.initState();
    _log.fine(
      'budget screen opened budgetId=$_id inviteOnOpen=${widget.inviteOnOpen}',
    );
    ref.listenManual(budgetProvider(_id), _onBudget, fireImmediately: true);
  }

  void _onBudget(AsyncValue<Budget?>? previous, AsyncValue<Budget?> next) {
    switch (next) {
      case AsyncData(value: final Budget budget)
          when budget.kind == BudgetKind.personal:
        _log.warning(
          'budget screen budgetId=$_id is a personal budget: it has no '
          'members, invites or roles → screen closed',
        );
        _closeLater('personal budget');
      case AsyncData(value: final Budget budget):
        _shown = budget;
      case AsyncData(value: null):
        final busy = _busy;
        if (busy == BudgetAction.leave || busy == BudgetAction.delete) {
          _log.fine(
            'budget screen budgetId=$_id: budget left this phone during own '
            '${busy!.logName} → kept on screen until the result',
          );
          return;
        }
        if (_closing) return;
        _log.info(
          'budget screen budgetId=$_id: budget is not on this phone '
          '(${_shown == null ? 'not found' : 'removed by sync'}) → screen '
          'closed',
        );
        _closeLater(_shown == null ? 'budget not found' : 'budget removed');
      case AsyncError(:final error, :final stackTrace):
        final cause = _cause(error);
        _log.severe(
          'budget screen budgetId=$_id: budget read failed → "not loaded" '
          'text: ${describeError(cause)}',
          cause,
          stackTrace,
        );
      default:
    }
  }

  void _closeLater(String reason) => Future.microtask(() {
    if (mounted) _close(reason);
  });

  void _close(String reason) {
    if (_closing) return;
    _closing = true;
    _closedBy = reason;
    if (context.canPop()) {
      context.pop();
      return;
    }
    _nav.fine(
      'budget screen closed by $reason with nothing under it → '
      '${AppRoutes.month}',
    );
    context.go(AppRoutes.month);
  }

  void _handlePop(bool didPop, Object? result) {
    if (!didPop) return;
    _nav.fine(
      'budget screen budgetId=$_id closed by $_closedBy'
      '${_busy == null ? '' : ' during ${_busy!.logName}'}',
    );
  }

  void _logFailure<T>(
    String what,
    AsyncValue<T>? previous,
    AsyncValue<T> next,
  ) {
    if (next case AsyncError(:final error, :final stackTrace)) {
      if (previous is AsyncError<T> && previous.error == error) return;
      final cause = _cause(error);
      _log.warning(
        'budget screen budgetId=$_id: $what unavailable, shown without it: '
        '${describeError(cause)}',
        cause,
        stackTrace,
      );
    }
  }

  void _snackbar(String text) => showAppSnackbar(context, text: text);

  bool _ignoredWhileBusy(String what) {
    final busy = _busy;
    if (busy == null && !_menuOpen) return false;
    _log.fine(
      'budget screen budgetId=$_id $what ignored: '
      '${busy == null ? 'a menu is open' : '${busy.logName} in progress'}',
    );
    return true;
  }

  Future<bool> _confirm({
    required String what,
    required String title,
    required String message,
    required String confirm,
    bool destructive = true,
  }) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showAppDialog<bool>(
      context,
      builder: (context) => AppDialog(
        title: title,
        message: message,
        textAlign: TextAlign.start,
        primary: AppDialogAction(
          confirm,
          () => Navigator.of(context).pop(true),
          destructive: destructive,
        ),
        secondary: AppDialogAction(
          l10n.budgetScreenCancel,
          () => Navigator.of(context).pop(false),
        ),
      ),
    );
    if (confirmed != true) {
      _log.fine(
        'budget screen budgetId=$_id $what dialog '
        '${confirmed == null ? 'dismissed' : '→ cancel'}: nothing done',
      );
    }
    return confirmed == true;
  }

  Future<bool> _pickInSheet({
    required String what,
    required String title,
    required AppIcons icon,
    required String label,
  }) async {
    _menuOpen = true;
    final bool? picked;
    try {
      picked = await showAppSheet<bool>(
        context,
        builder: (context) => [
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Semantics(
              header: true,
              child: FittingText(
                title,
                style: AppText.titleM.copyWith(
                  color: context.colors.textPrimary,
                ),
              ),
            ),
          ),
          ListRow(
            icon: icon,
            title: label,
            chevron: false,
            danger: true,
            onTap: () => Navigator.of(context).pop(true),
          ),
        ],
      );
    } finally {
      _menuOpen = false;
    }
    if (picked != true) {
      _log.fine(
        'budget screen budgetId=$_id $what sheet closed without a choice',
      );
    }
    return picked == true;
  }

  Future<void> _openMenu(Budget budget, MemberRole role) async {
    if (_ignoredWhileBusy('menu tap')) return;
    final l10n = AppLocalizations.of(context);
    final owner = role == MemberRole.owner;
    final action = owner ? BudgetAction.delete : BudgetAction.leave;
    _log.fine(
      'budget screen budgetId=$_id menu tap role=${role.name} → sheet with '
      '${action.logName}',
    );
    final picked = await _pickInSheet(
      what: 'menu',
      title: '${budget.emoji} ${budget.name}',
      icon: owner ? AppIcons.trash : AppIcons.logOut,
      label: owner ? l10n.budgetScreenDelete : l10n.budgetScreenLeave,
    );
    if (!mounted || !picked) return;
    _log.fine(
      'budget screen budgetId=$_id ${action.logName} picked → confirmation',
    );
    final confirmed = await _confirm(
      what: action.logName,
      title: owner
          ? l10n.budgetScreenDeleteTitle(budget.name)
          : l10n.budgetScreenLeaveTitle(budget.name),
      message: owner
          ? l10n.budgetScreenDeleteMessage
          : l10n.budgetScreenLeaveMessage,
      confirm: owner
          ? l10n.budgetScreenDeleteConfirm
          : l10n.budgetScreenLeaveConfirm,
    );
    if (!mounted || !confirmed) return;
    await _removeOwn(budget, action);
  }

  Future<void> _removeOwn(Budget budget, BudgetAction action) async {
    setState(() => _busy = action);
    final service = ref.read(budgetActionsServiceProvider);
    final outcome = action == BudgetAction.delete
        ? await service.delete(_id)
        : await service.leave(_id);
    if (!mounted) {
      _log.fine(
        'budget screen closed before the result $outcome → nothing more to '
        'show',
      );
      return;
    }
    final l10n = AppLocalizations.of(context);
    switch (outcome) {
      case BudgetActionDone():
        final root = Navigator.of(context, rootNavigator: true).context;
        final text = action == BudgetAction.delete
            ? l10n.budgetRemovedDeleted(budget.name)
            : l10n.budgetScreenLeft(budget.name);
        _log.fine(
          'budget screen budgetId=$_id ${action.logName} done → screen '
          'closed, snackbar over the previous screen',
        );
        _close(action.logName);
        if (!root.mounted) return;
        showAppSnackbar(
          root,
          text: text,
          margin: const EdgeInsets.fromLTRB(
            expenseSnackbarSide,
            0,
            expenseSnackbarSide,
            expenseSnackbarAboveAnchor,
          ),
        );
      case final BudgetActionFailed failure:
        setState(() => _busy = null);
        _snackbar(budgetActionFailureText(l10n, failure));
    }
  }

  Future<void> _memberMenu(
    Budget budget,
    BudgetMember member,
    String name,
  ) async {
    if (_ignoredWhileBusy('long press memberId=${member.userId}')) return;
    final l10n = AppLocalizations.of(context);
    _log.fine(
      'budget screen budgetId=$_id long press memberId=${member.userId} → '
      'sheet with ${BudgetAction.removeMember.logName}',
    );
    final picked = await _pickInSheet(
      what: 'member',
      title: name,
      icon: AppIcons.x,
      label: l10n.budgetScreenExclude,
    );
    if (!mounted || !picked) return;
    final confirmed = await _confirm(
      what: BudgetAction.removeMember.logName,
      title: l10n.budgetScreenExcludeTitle,
      message: l10n.budgetScreenExcludeMessage(name, budget.name),
      confirm: l10n.budgetScreenExclude,
    );
    if (!mounted || !confirmed) return;
    setState(() => _busy = BudgetAction.removeMember);
    final outcome = await ref
        .read(budgetActionsServiceProvider)
        .removeMember(_id, member.userId);
    if (!mounted) return;
    setState(() => _busy = null);
    switch (outcome) {
      case BudgetActionDone(:final inviteRevoked):
        if (inviteRevoked) {
          _log.fine(
            'budget screen budgetId=$_id: shown invite code revoked with the '
            'removal → «${l10n.budgetScreenInviteRevoked}» and '
            '«${l10n.budgetScreenInviteNew}» instead of the code',
          );
          setState(() => _inviteRevoked = true);
        }
        _snackbar(l10n.budgetScreenExcluded(name));
      case final BudgetActionFailed failure:
        _snackbar(budgetActionFailureText(l10n, failure));
    }
  }

  Future<void> _invite({required bool renew, required String by}) async {
    if (_ignoredWhileBusy('invite by $by')) return;
    final l10n = AppLocalizations.of(context);
    if (renew) {
      final current = ref.read(budgetInvitesProvider)[_id];
      _log.fine('budget screen budgetId=$_id new code tap → confirmation');
      final confirmed = await _confirm(
        what: BudgetAction.renewInvite.logName,
        title: l10n.budgetScreenRenewTitle,
        message: l10n.budgetScreenRenewMessage(current?.code ?? ''),
        confirm: l10n.budgetScreenRenewConfirm,
        destructive: false,
      );
      if (!mounted || !confirmed) return;
    } else {
      _log.fine('budget screen budgetId=$_id invite by $by → new code');
    }
    setState(
      () => _busy = renew ? BudgetAction.renewInvite : BudgetAction.invite,
    );
    final outcome = await ref
        .read(budgetActionsServiceProvider)
        .invite(_id, renew: renew);
    if (!mounted) return;
    setState(() {
      _busy = null;
      if (outcome is BudgetActionDone) _inviteRevoked = false;
    });
    if (outcome case final BudgetActionFailed failure) {
      _snackbar(budgetActionFailureText(l10n, failure));
    }
  }

  bool _usable(BudgetInvite invite, String what) {
    final now = ref.read(clockProvider).now();
    if (invite.activeAt(now)) return true;
    _log.info(
      'budget invite $what refused budgetId=$_id $invite: expired → '
      'snackbar, «${AppLocalizations.of(context).budgetScreenInviteCreate}» '
      'shown again',
    );
    ref.read(budgetInvitesProvider.notifier).forget(_id, reason: 'expired');
    _snackbar(AppLocalizations.of(context).budgetScreenInviteExpired);
    return false;
  }

  String _scrub(Object error, String code) =>
      describeError(error).replaceAll(code, maskInviteCode(code));

  Future<void> _copy(BudgetInvite invite) async {
    if (!_usable(invite, 'copy')) return;
    final l10n = AppLocalizations.of(context);
    final sw = Stopwatch()..start();
    try {
      await Clipboard.setData(ClipboardData(text: invite.code));
    } catch (e, st) {
      _log.warning(
        'budget invite copy failed budgetId=$_id '
        'code=${maskInviteCode(invite.code)} after '
        '${sw.elapsedMilliseconds}ms → snackbar: ${_scrub(e, invite.code)}',
        null,
        st,
      );
      if (mounted) _snackbar(l10n.budgetScreenInviteCopyFailed);
      return;
    }
    _log.info(
      'budget invite copied budgetId=$_id code=${maskInviteCode(invite.code)} '
      'in ${sw.elapsedMilliseconds}ms',
    );
    if (mounted) _snackbar(l10n.budgetScreenInviteCopied);
  }

  Future<void> _share(Budget budget, BudgetInvite invite) async {
    if (_sharing) {
      _log.fine('budget invite share tap ignored: share sheet is opening');
      return;
    }
    if (!_usable(invite, 'share')) return;
    final l10n = AppLocalizations.of(context);
    final sharer = ref.read(inviteCodeSharerProvider);
    final sw = Stopwatch()..start();
    _sharing = true;
    try {
      final result = await sharer.share(
        l10n.budgetScreenInviteShareText(budget.name, invite.code),
      );
      _log.info(
        'budget invite share result=${result.status.name} budgetId=$_id '
        'code=${maskInviteCode(invite.code)} '
        'target=${result.raw.isEmpty ? '-' : result.raw} '
        'in ${sw.elapsedMilliseconds}ms',
      );
    } catch (e, st) {
      _log.warning(
        'budget invite share failed budgetId=$_id '
        'code=${maskInviteCode(invite.code)} after '
        '${sw.elapsedMilliseconds}ms → snackbar: ${_scrub(e, invite.code)}',
        null,
        st,
      );
      if (mounted) _snackbar(l10n.budgetScreenInviteShareFailed);
    } finally {
      _sharing = false;
    }
  }

  void _logShown(
    List<BudgetMember> members,
    MemberRole? role,
    BudgetInvite? invite,
  ) {
    if (_loggedShown) return;
    _loggedShown = true;
    _log.fine(
      'budget screen shown budgetId=$_id role=${role?.name ?? 'none'} '
      'members=${members.length} invite=${invite == null ? 'none' : '$invite'} '
      'in ${_sw.elapsedMilliseconds}ms',
    );
    if (role == null) {
      _log.info(
        'budget screen budgetId=$_id: signed-in user is not an active member '
        'on this phone → no actions shown',
      );
    }
  }

  Widget _memberRow(
    AppLocalizations l10n,
    Budget budget,
    BudgetMember member, {
    required SessionUser? user,
    required Map<String, MemberProfile> profiles,
    required bool owner,
    required LocalDate today,
    required bool birthdaySoon,
  }) {
    final self = user != null && member.userId == user.userId;
    final name = budgetMemberName(l10n, member, user: user, profiles: profiles);
    final since = budgetDate(
      LocalDate.fromDateTime(member.joinedAt.toLocal()),
      today,
    );
    return BudgetMemberRow(
      key: ValueKey('member-${member.userId}'),
      name: self
          ? l10n.budgetScreenYou(name)
          : birthdaySoon
          ? l10n.budgetScreenMemberBirthday(name)
          : name,
      plainName: name,
      color: member.avatarColor,
      subtitle: member.role == MemberRole.owner
          ? l10n.budgetScreenOwner
          : l10n.budgetScreenMemberSince(since),
      onLongPress: owner && !self
          ? () => _memberMenu(budget, member, name)
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final budgetValue = ref.watch(budgetProvider(_id));
    final budget = budgetValue.value ?? _shown;
    ref.listen(
      budgetMembersProvider(_id),
      (previous, next) => _logFailure('members', previous, next),
    );
    final members = ref.watch(budgetMembersProvider(_id)).value;
    ref.listen(
      memberProfilesProvider,
      (previous, next) => _logFailure('member profiles', previous, next),
    );
    final profiles =
        ref.watch(memberProfilesProvider).value ??
        const <String, MemberProfile>{};
    final recentKey = (budgetId: _id, limit: budgetRecentLimit);
    ref.listen(
      recentExpensesProvider(recentKey),
      (previous, next) => _logFailure('recent expenses', previous, next),
    );
    final recent = ref.watch(recentExpensesProvider(recentKey));
    final authors = ref.watch(expenseAuthorsProvider(_id));
    ref.listen(
      categoriesProvider(_id),
      (previous, next) => _logFailure('categories', previous, next),
    );
    final categories = ref.watch(categoriesProvider(_id)).value ?? const [];
    final user = ref.watch(sessionProvider).user;
    final invites = ref.watch(budgetInvitesProvider);
    final clock = ref.watch(clockProvider);
    final today = clock.today();
    final birthdays = {
      for (final birthday in ref.watch(
        memberBirthdaysProvider((budgetId: _id, today: today)),
      ))
        birthday.userId,
    };

    MemberRole? role;
    for (final member in members ?? const <BudgetMember>[]) {
      if (user != null && member.userId == user.userId) role = member.role;
    }
    final owner = role == MemberRole.owner;
    final menuRole = role;
    final stored = invites[_id];
    final invite = stored != null && stored.activeAt(clock.now())
        ? stored
        : null;
    if (budget != null && members != null) {
      _logShown(members, role, invite);
      if (owner && _autoInvite && invite == null && _busy == null) {
        _autoInvite = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_invite(renew: false, by: 'budget created'));
        });
      }
    }

    final Widget content;
    if (budget == null) {
      content = budgetValue.hasError
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.budgetScreenNotLoaded,
                style: AppText.bodyM.copyWith(color: colors.textSecondary),
              ),
            )
          : const SizedBox.shrink();
    } else {
      final list = members ?? const <BudgetMember>[];
      final expenses = recent.value;
      content = SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(12, 4, 12, 16 + bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BudgetSectionHead(
              title: l10n.budgetScreenMembers,
              note: members == null ? null : '${list.length}',
            ),
            const SizedBox(height: 12),
            ProfileCard(
              children: [
                for (final member in budgetMembersInOrder(list))
                  _memberRow(
                    l10n,
                    budget,
                    member,
                    user: user,
                    profiles: profiles,
                    owner: owner,
                    today: today,
                    birthdaySoon: birthdays.contains(member.userId),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (owner) ...[
              BudgetInviteCard(
                invite: invite,
                revoked: _inviteRevoked,
                busy: _busy != null,
                onCreate: () => _invite(
                  renew: false,
                  by: _inviteRevoked ? 'new code after removal' : 'button',
                ),
                onCopy: () {
                  if (invite != null) unawaited(_copy(invite));
                },
                onShare: () {
                  if (invite != null) unawaited(_share(budget, invite));
                },
                onRenew: () => _invite(renew: true, by: 'new code'),
              ),
              const SizedBox(height: 12),
            ],
            BudgetSectionHead(
              title: l10n.budgetScreenRecent,
              note: l10n.budgetScreenRecentWho,
            ),
            const SizedBox(height: 12),
            ProfileCard(
              children: [
                if (expenses != null && expenses.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 18,
                    ),
                    child: Text(
                      l10n.budgetScreenRecentEmpty,
                      style: AppText.bodyM.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                for (final expense in expenses ?? const <Expense>[])
                  BudgetRecentRow(
                    key: ValueKey('recent-${expense.id}'),
                    expense: expense,
                    category: expenseCategory(expense, categories),
                    subtitle: recentExpenseSubtitle(l10n, expense, today),
                    when: recentExpenseWhen(l10n, expense, today),
                    author: authors?.of(expense.authorId),
                  ),
              ],
            ),
          ],
        ),
      );
    }

    return PopScope<Object?>(
      onPopInvokedWithResult: _handlePop,
      child: Scaffold(
        backgroundColor: colors.bgApp,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SafeArea(
              bottom: false,
              child: BudgetTopBar(
                title: budget == null ? '' : '${budget.emoji} ${budget.name}',
                subtitle: members == null
                    ? null
                    : l10n.budgetScreenSubtitle(members.length),
                onBack: () => _close('back button'),
                onMenu: budget == null || menuRole == null
                    ? null
                    : () => _openMenu(budget, menuRole),
              ),
            ),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }
}
