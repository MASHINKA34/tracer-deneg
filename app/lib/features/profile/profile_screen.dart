import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../core/router.dart';
import '../../data/db/redact_db_error.dart';
import '../../data/providers.dart';
import '../../data/session/session_providers.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/components/category_badge.dart';
import '../../ui/components/fitting_text.dart';
import '../../ui/components/list_row.dart';
import '../../ui/components/snackbar.dart';
import '../../ui/icons/app_icon.dart';
import '../../ui/theme/app_text.dart';
import '../../ui/theme/app_theme.dart';
import '../auth/sign_out_service.dart';
import '../expense/expense_snackbar_layer.dart';
import 'profile_account_card.dart';
import 'profile_budgets.dart';
import 'sign_out_dialog.dart';
import 'theme_mode.dart';

final _log = Logger('profile');

Duration? _noRetry(int retryCount, Object error) => null;

final profileBudgetsProvider = StreamProvider.autoDispose<List<Budget>>(
  (ref) {
    final ownerId = ref.watch(sessionProvider.select((s) => s.userId));
    return ref
        .watch(budgetsRepositoryProvider)
        .watchAll()
        .map((budgets) => visibleBudgets(budgets, ownerId));
  },
  name: 'profileBudgets',
  retry: _noRetry,
);

String themeModeLabel(AppLocalizations l10n, ThemeMode mode) => switch (mode) {
  ThemeMode.system => l10n.themeSystem,
  ThemeMode.light => l10n.themeLight,
  ThemeMode.dark => l10n.themeDark,
};

int userCategoryCount(List<Category> categories) =>
    categories.where((c) => !c.isSystem).length;

Object _cause(Object error) {
  var cause = error;
  while (cause is ProviderException) {
    cause = cause.exception;
  }
  return redactDbError(cause);
}

void _logUnavailable<T>(
  String what,
  AsyncValue<T>? previous,
  AsyncValue<T> next,
) {
  if (next case AsyncError(:final error, :final stackTrace)) {
    if (previous is AsyncError<T> && previous.error == error) return;
    final cause = _cause(error);
    _log.warning(
      'profile $what unavailable, shown without it: ${describeError(cause)}',
      cause,
      stackTrace,
    );
  }
}

enum ProfileStub {
  budget,
  createBudget,
  joinBudget,
  holidays,
  reminders,
  sendLogs,
  deleteAccount,
}

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final Stopwatch _sw = Stopwatch()..start();
  bool _loggedSession = false;
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    _log.fine('profile screen opened');
    ref.listenManual(profileBudgetsProvider, _onBudgets, fireImmediately: true);
    ref.listenManual(lastSyncAtProvider, _onLastSync, fireImmediately: true);
  }

  void _onBudgets(
    AsyncValue<List<Budget>>? previous,
    AsyncValue<List<Budget>> next,
  ) {
    switch (next) {
      case AsyncData(value: final budgets):
        final shared = budgets.where((b) => b.kind == BudgetKind.shared).length;
        _log.fine(
          'profile budgets shown count=${budgets.length} shared=$shared '
          'in ${_sw.elapsedMilliseconds}ms',
        );
      case AsyncError(:final error, :final stackTrace):
        final cause = _cause(error);
        _log.severe(
          'profile budgets load failed after ${_sw.elapsedMilliseconds}ms, '
          'showing error text instead of the list: ${describeError(cause)}',
          cause,
          stackTrace,
        );
      default:
    }
  }

  void _onLastSync(
    AsyncValue<DateTime?>? previous,
    AsyncValue<DateTime?> next,
  ) {
    switch (next) {
      case AsyncData(value: final at):
        _log.fine(
          'profile sync status lastSyncAt=${at == null ? 'never' : encodeInstant(at)}',
        );
      case AsyncError(:final error, :final stackTrace):
        final cause = _cause(error);
        _log.warning(
          'profile last sync time unavailable, showing "not synced": '
          '${describeError(cause)}',
          cause,
          stackTrace,
        );
      default:
    }
  }

  void _push(String row, String location) {
    _log.fine('profile row $row tap → $location');
    context.push(location);
  }

  Future<void> _signOut() async {
    if (_signingOut) {
      _log.fine('profile sign out tap ignored: sign-out already open');
      return;
    }
    _signingOut = true;
    try {
      final service = ref.read(signOutServiceProvider);
      final queue = await service.queueSize();
      if (!mounted) return;
      if (queue == null) {
        _showSnackbar(AppLocalizations.of(context).signOutFailed);
        return;
      }
      final done = await showSignOutDialog(context, queueSize: queue);
      if (!mounted || done != true) return;
      _log.fine(
        'profile signed out, sign-in not forced by the gate → '
        '${AppRoutes.login}',
      );
      context.go(AppRoutes.login);
    } finally {
      _signingOut = false;
    }
  }

  void _showSnackbar(String text) => showAppSnackbar(
    context,
    text: text,
    margin: const EdgeInsets.fromLTRB(
      expenseSnackbarSide,
      0,
      expenseSnackbarSide,
      expenseSnackbarAboveAnchor,
    ),
  );

  void _stub(ProfileStub stub, {String details = ''}) {
    _log.fine(
      'profile ${stub.name} tap$details: not in the app yet → '
      '"soon" snackbar',
    );
    showAppSnackbar(
      context,
      text: AppLocalizations.of(context).profileSoonSnackbar,
      margin: const EdgeInsets.fromLTRB(
        expenseSnackbarSide,
        0,
        expenseSnackbarSide,
        expenseSnackbarAboveAnchor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final user = ref.watch(sessionProvider).user;
    if (user == null && !_loggedSession) {
      _loggedSession = true;
      _log.fine('profile without session: account card hidden');
    }
    ref.listen(
      memberProfilesProvider,
      (previous, next) => _logUnavailable('member profiles', previous, next),
    );
    final profiles = ref.watch(memberProfilesProvider);
    final selectedId = ref.watch(selectedBudgetIdProvider).value;
    if (selectedId != null) {
      ref.listen(
        categoriesProvider(selectedId),
        (previous, next) => _logUnavailable(
          'category count of budgetId=$selectedId',
          previous,
          next,
        ),
      );
    }
    final categoryCount = selectedId == null
        ? null
        : ref.watch(categoriesProvider(selectedId)).value;
    final self = user == null ? null : profiles.value?[user.userId];

    return Scaffold(
      backgroundColor: colors.bgApp,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(title: l10n.profileTitle),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(12, 4, 12, 16 + bottom),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (user != null) ...[
                      ProfileAccountCard(
                        name: self?.displayName ?? user.displayName,
                        login: user.login,
                        color: self?.avatarColor ?? CategoryColor.blue,
                        lastSyncAt: ref.watch(lastSyncAtProvider).value,
                      ),
                      const SizedBox(height: 12),
                    ],
                    _Budgets(
                      selectedId: selectedId,
                      profiles: profiles.value ?? const {},
                      onStub: _stub,
                    ),
                    const SizedBox(height: 12),
                    ProfileSectionHead(title: l10n.profileSettings),
                    const SizedBox(height: 12),
                    ProfileCard(
                      children: [
                        ListRow(
                          icon: AppIcons.calendar,
                          title: l10n.profileHolidays,
                          value: l10n.profileSoon,
                          onTap: () => _stub(ProfileStub.holidays),
                        ),
                        ListRow(
                          icon: AppIcons.tag,
                          title: l10n.profileCategories,
                          value: categoryCount == null
                              ? null
                              : '${userCategoryCount(categoryCount)}',
                          onTap: () =>
                              _push('categories', AppRoutes.categories),
                        ),
                        ListRow(
                          icon: AppIcons.moon,
                          title: l10n.profileTheme,
                          value: themeModeLabel(
                            l10n,
                            ref.watch(themeModeProvider),
                          ),
                          onTap: () => _push('theme', AppRoutes.theme),
                        ),
                        ListRow(
                          icon: AppIcons.bell,
                          title: l10n.profileReminders,
                          value: l10n.profileSoon,
                          onTap: () => _stub(ProfileStub.reminders),
                        ),
                        ListRow(
                          icon: AppIcons.download,
                          title: l10n.profileExport,
                          onTap: () => _push('export', AppRoutes.export),
                        ),
                        ListRow(
                          icon: AppIcons.link,
                          title: l10n.profileRecoveryCode,
                          value: l10n.profileRecoveryCodeValue,
                          onTap: () =>
                              _push('recovery code', AppRoutes.recoveryReissue),
                        ),
                        ListRow(
                          icon: AppIcons.message,
                          title: l10n.profileSendLogs,
                          value: l10n.profileSoon,
                          onTap: () => _stub(ProfileStub.sendLogs),
                        ),
                        ListRow(
                          icon: AppIcons.logOut,
                          title: l10n.profileSignOut,
                          chevron: false,
                          danger: true,
                          onTap: _signOut,
                        ),
                        ListRow(
                          icon: AppIcons.trash,
                          title: l10n.profileDeleteAccount,
                          value: l10n.profileSoon,
                          chevron: false,
                          danger: true,
                          onTap: () => _stub(ProfileStub.deleteAccount),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 60),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Semantics(
          header: true,
          child: FittingText(
            title,
            style: AppText.titleL.copyWith(color: context.colors.textPrimary),
          ),
        ),
      ),
    ),
  );
}

class _Budgets extends ConsumerWidget {
  const _Budgets({
    required this.selectedId,
    required this.profiles,
    required this.onStub,
  });

  final String? selectedId;
  final Map<String, MemberProfile> profiles;
  final void Function(ProfileStub stub, {String details}) onStub;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final mood = context.mood;
    final budgets = ref.watch(profileBudgetsProvider);
    final list = budgets.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProfileSectionHead(title: l10n.profileBudgets, count: list?.length),
        const SizedBox(height: 12),
        ProfileCard(
          children: [
            if (budgets.hasError && list == null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 18,
                ),
                child: Text(
                  l10n.profileLoadFailed,
                  style: AppText.bodyM.copyWith(color: colors.textSecondary),
                ),
              ),
            for (final budget in list ?? const <Budget>[])
              _BudgetRow(
                budget: budget,
                open: budget.id == selectedId,
                profiles: profiles,
                onTap: () => onStub(
                  ProfileStub.budget,
                  details: ' budgetId=${budget.id} kind=${budget.kind.name}',
                ),
              ),
            ProfileBudgetRow(
              leading: ProfileIconBox(
                icon: AppIcons.plus,
                background: mood.soft,
                color: mood.accentStrong,
              ),
              title: l10n.profileCreateBudget,
              titleColor: mood.accentStrong,
              subtitle: l10n.profileCreateBudgetHint,
              onTap: () => onStub(ProfileStub.createBudget),
            ),
            ProfileBudgetRow(
              leading: ProfileIconBox(
                icon: AppIcons.link,
                background: colors.bgSurface2,
                color: colors.textSecondary,
              ),
              title: l10n.profileJoinBudget,
              trailing: const ProfileChevron(),
              onTap: () => onStub(ProfileStub.joinBudget),
            ),
          ],
        ),
      ],
    );
  }
}

class _BudgetRow extends ConsumerWidget {
  const _BudgetRow({
    required this.budget,
    required this.open,
    required this.profiles,
    required this.onTap,
  });

  final Budget budget;
  final bool open;
  final Map<String, MemberProfile> profiles;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final shared = budget.kind == BudgetKind.shared;
    if (shared) {
      ref.listen(
        budgetMembersProvider(budget.id),
        (previous, next) =>
            _logUnavailable('members of budgetId=${budget.id}', previous, next),
      );
    }
    final list = shared
        ? ref.watch(budgetMembersProvider(budget.id)).value ??
              const <BudgetMember>[]
        : const <BudgetMember>[];
    Widget? trailing;
    if (open) {
      trailing = const ProfileSelectedMark();
    } else if (list.isNotEmpty) {
      trailing = ProfileMemberAvatars(members: list, profiles: profiles);
    }
    return ProfileBudgetRow(
      leading: CategoryBadge(
        emoji: budget.emoji,
        color: profileBudgetColor(budget),
      ),
      title: profileBudgetName(l10n, budget),
      subtitle: profileBudgetDetails(
        l10n,
        budget,
        members: list.length,
        open: open,
      ),
      trailing: trailing,
      onTap: onTap,
    );
  }
}
