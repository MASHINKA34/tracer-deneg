import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/components/avatar.dart';
import '../../ui/components/category_badge.dart';
import '../../ui/components/fitting_text.dart';
import '../../ui/icons/app_icon.dart';
import '../../ui/theme/app_text.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/tokens/tokens.g.dart';
import '../month/month_header.dart' show avatarLetterOf;

const int profileAvatarsShown = 3;

CategoryColor profileBudgetColor(Budget budget) =>
    budget.kind == BudgetKind.personal
    ? CategoryColor.orange
    : CategoryColor.blue;

String profileBudgetName(AppLocalizations l10n, Budget budget) =>
    budget.kind == BudgetKind.personal
    ? l10n.profilePersonalBudget
    : budget.name;

String profileBudgetDetails(
  AppLocalizations l10n,
  Budget budget, {
  required int members,
  required bool open,
}) {
  final details = budget.kind == BudgetKind.personal
      ? l10n.profileBudgetPersonal
      : l10n.profileBudgetShared(members);
  return open ? l10n.profileBudgetOpenNow(details) : details;
}

class ProfileCard extends StatelessWidget {
  const ProfileCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
    color: context.colors.bgSurface,
    borderRadius: BorderRadius.circular(RadiusTokens.lg),
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );
}

class ProfileSectionHead extends StatelessWidget {
  const ProfileSectionHead({super.key, required this.title, this.count});

  final String title;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final count = this.count;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: FittingText(
                title,
                style: AppText.titleS.copyWith(color: colors.textPrimary),
              ),
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 8),
            Text(
              '$count',
              style: AppText.labelS.copyWith(color: colors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

class ProfileBudgetRow extends StatelessWidget {
  const ProfileBudgetRow({
    super.key,
    required this.leading,
    required this.title,
    this.titleColor,
    this.subtitle,
    this.trailing,
    required this.onTap,
  });

  final Widget leading;
  final String title;
  final Color? titleColor;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final subtitle = this.subtitle;
    final trailing = this.trailing;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 60),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittingText(
                      title,
                      style: AppText.labelM.copyWith(
                        color: titleColor ?? colors.textPrimary,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      FittingText(
                        subtitle,
                        style: AppText.caption.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 12), trailing],
            ],
          ),
        ),
      ),
    );
  }
}

class ProfileIconBox extends StatelessWidget {
  const ProfileIconBox({
    super.key,
    required this.icon,
    required this.background,
    required this.color,
  });

  final AppIcons icon;
  final Color background;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: CategoryBadge.size,
    height: CategoryBadge.size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(RadiusTokens.sm),
    ),
    child: AppIcon(icon, size: 20, color: color),
  );
}

class ProfileSelectedMark extends StatelessWidget {
  const ProfileSelectedMark({super.key});

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 28,
    child: Center(
      child: AppIcon(
        AppIcons.check,
        size: 20,
        color: context.mood.accentStrong,
      ),
    ),
  );
}

class ProfileChevron extends StatelessWidget {
  const ProfileChevron({super.key});

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 24,
    child: Center(
      child: AppIcon(
        AppIcons.chevronRight,
        size: 20,
        color: context.colors.textTertiary,
      ),
    ),
  );
}

class ProfileMemberAvatars extends StatelessWidget {
  const ProfileMemberAvatars({
    super.key,
    required this.members,
    required this.profiles,
  });

  final List<BudgetMember> members;
  final Map<String, MemberProfile> profiles;

  static const double _size = 24;
  static const double _step = 16;
  static const double _ring = 2;

  @override
  Widget build(BuildContext context) {
    final shown = members.take(profileAvatarsShown).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    final surface = context.colors.bgSurface;
    return ExcludeSemantics(
      child: SizedBox(
        width: _size + _step * (shown.length - 1),
        height: _size,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            for (final (i, member) in shown.indexed)
              Positioned(
                left: _step * i - _ring,
                top: -_ring,
                child: Container(
                  padding: const EdgeInsets.all(_ring),
                  decoration: BoxDecoration(
                    color: surface,
                    shape: BoxShape.circle,
                  ),
                  child: AppAvatar(
                    letter: avatarLetterOf(
                      profiles[member.userId]?.displayName ?? '',
                    ),
                    size: AvatarSize.s24,
                    color: member.avatarColor,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
