import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../core/clock.dart';
import '../../core/router.dart';
import '../../data/db/redact_db_error.dart';
import '../../data/providers.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/components/avatar.dart';
import '../../ui/components/bottom_nav.dart';
import '../../ui/components/tap_target.dart';
import '../../ui/icons/app_icon.dart';
import '../../ui/theme/app_text.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/tokens/tokens.g.dart';

final _log = Logger('month');

String avatarLetterOf(String name) {
  final letters = name.trim().characters;
  return letters.isEmpty ? '' : letters.first.toUpperCase();
}

class MonthHeader extends ConsumerWidget {
  const MonthHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(selectedBudgetIdProvider, _logSelected);
    final budgetId = ref.watch(selectedBudgetIdProvider).value;
    if (budgetId != null) {
      ref.listen(
        budgetProvider(budgetId),
        (previous, next) => _logBudget(budgetId, next),
      );
    }
    final budget = budgetId == null
        ? null
        : ref.watch(budgetProvider(budgetId)).value;
    final debugToday = kDebugMode ? ref.watch(todayOverrideProvider) : null;

    return MonthHeaderView(
      debugToday: debugToday,
      budgetName: budget?.name,
      budgetEmoji: budget?.emoji,
      avatarLetter: budget == null ? '' : avatarLetterOf(budget.name),
      onBudgetTap: budget == null
          ? null
          : () => _log.fine(
              'header budget tap budgetId=${budget.id}: no action, '
              'budget switcher is not available yet',
            ),
      onSearchTap: () {
        _log.fine('header search tap → ${AppRoutes.search}');
        context.pushNamed(AppRoutes.searchName);
      },
      onAvatarTap: () {
        _log.fine(
          'header avatar tap → ${AppNavTab.profile.name} tab '
          '(${AppRoutes.profile})',
        );
        StatefulNavigationShell.of(context).goBranch(AppNavTab.profile.index);
      },
    );
  }

  static void _logSelected(
    AsyncValue<String?>? previous,
    AsyncValue<String?> next,
  ) {
    switch (next) {
      case AsyncData(value: null):
        _log.fine('header without budget: no budget selected');
      case AsyncError(:final error, :final stackTrace):
        final cause = _cause(error);
        _log.warning(
          'header selected budget unavailable, ${_fallback(next)}: '
          '${describeError(cause)}',
          cause,
          stackTrace,
        );
      default:
    }
  }

  static void _logBudget(String budgetId, AsyncValue<Budget?> next) {
    switch (next) {
      case AsyncData(value: final Budget budget):
        _log.fine(
          'header budget shown budgetId=$budgetId kind=${budget.kind.name}',
        );
      case AsyncData(value: null):
        _log.warning(
          'header without budget: budgetId=$budgetId not found or deleted',
        );
      case AsyncError(:final error, :final stackTrace):
        final cause = _cause(error);
        _log.warning(
          'header budget budgetId=$budgetId load failed, ${_fallback(next)}: '
          '${describeError(cause)}',
          cause,
          stackTrace,
        );
      default:
    }
  }

  static String _fallback(AsyncValue<Object?> state) => state.hasValue
      ? 'keeping last shown budget'
      : 'showing header without budget';

  static Object _cause(Object error) {
    var cause = error;
    while (cause is ProviderException) {
      cause = cause.exception;
    }
    return redactDbError(cause);
  }
}

class MonthHeaderView extends StatelessWidget {
  const MonthHeaderView({
    super.key,
    this.budgetName,
    this.budgetEmoji,
    required this.avatarLetter,
    this.avatarColor = CategoryColor.blue,
    this.onBudgetTap,
    this.onSearchTap,
    this.onAvatarTap,
    this.debugToday,
  });

  final String? budgetName;
  final String? budgetEmoji;
  final String avatarLetter;
  final CategoryColor avatarColor;
  final VoidCallback? onBudgetTap;
  final VoidCallback? onSearchTap;
  final VoidCallback? onAvatarTap;
  final LocalDate? debugToday;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = AppLocalizations.of(context);
    final name = budgetName;
    final debugDay = debugToday;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Padding(
        padding: const EdgeInsets.only(
          left: 12,
          right: 10 - _HeaderButton.overhang,
        ),
        child: Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                heightFactor: 1,
                child: name == null
                    ? const SizedBox.shrink()
                    : _BudgetButton(
                        name: name,
                        emoji: budgetEmoji ?? '',
                        onTap: onBudgetTap,
                      ),
              ),
            ),
            const SizedBox(width: 6 - _HeaderButton.overhang),
            if (debugDay != null) _DebugTodayLabel(day: debugDay),
            _HeaderButton(
              label: l10n.a11ySearch,
              onTap: onSearchTap,
              child: SizedBox.square(
                dimension: 32,
                child: Center(
                  child: AppIcon(
                    AppIcons.search,
                    size: 22,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ),
            Semantics(
              container: true,
              label: l10n.syncDone,
              excludeSemantics: true,
              child: SizedBox(
                width: 32 - 2 * _HeaderButton.overhang,
                height: kMinTapTarget,
                child: Center(
                  child: AppIcon(
                    AppIcons.cloudCheck,
                    size: 20,
                    color: colors.statusSuccess,
                  ),
                ),
              ),
            ),
            _HeaderButton(
              label: l10n.a11yProfile,
              onTap: onAvatarTap,
              child: AppAvatar(
                letter: avatarLetter,
                size: AvatarSize.s32,
                color: avatarColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DebugTodayLabel extends StatelessWidget {
  const _DebugTodayLabel({required this.day});

  final LocalDate day;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final pattern = day.year == DateTime.now().year ? 'dd.MM' : 'dd.MM.yyyy';
    final date = DateFormat(
      pattern,
      'ru',
    ).format(DateTime(day.year, day.month, day.day));
    final text = 'debug $date';
    return Semantics(
      container: true,
      label: text,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.statusDanger,
          borderRadius: BorderRadius.circular(RadiusTokens.xs),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Text(
            text,
            maxLines: 1,
            softWrap: false,
            style: AppText.micro.copyWith(color: colors.textInverse),
          ),
        ),
      ),
    );
  }
}

class _BudgetButton extends StatelessWidget {
  const _BudgetButton({
    required this.name,
    required this.emoji,
    required this.onTap,
  });

  final String name;
  final String emoji;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = AppLocalizations.of(context);
    const shape = StadiumBorder();
    return Semantics(
      button: true,
      label: l10n.a11yChooseBudget(name),
      excludeSemantics: true,
      onTap: onTap,
      child: TapTarget(
        child: Material(
          color: colors.bgSurface,
          shape: shape.copyWith(side: BorderSide(color: colors.borderDefault)),
          child: InkWell(
            customBorder: shape,
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 36),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 1,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (emoji.isNotEmpty) ...[
                      Text(
                        emoji,
                        maxLines: 1,
                        style: AppText.bodyM.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.labelM.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    AppIcon(
                      AppIcons.chevronDown,
                      size: 16,
                      color: colors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.label,
    required this.onTap,
    required this.child,
  });

  final String label;
  final VoidCallback? onTap;
  final Widget child;

  static const double overhang = 2;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: kMinTapTarget,
          padding: const EdgeInsets.symmetric(horizontal: 6 + overhang),
          alignment: Alignment.center,
          child: Material(
            type: MaterialType.transparency,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
