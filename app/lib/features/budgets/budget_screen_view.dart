import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared/shared.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/components/avatar.dart';
import '../../ui/components/button.dart';
import '../../ui/components/expense_row.dart';
import '../../ui/components/fitting_text.dart';
import '../../ui/components/tap_target.dart';
import '../../ui/icons/app_icon.dart';
import '../../ui/theme/app_text.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/tokens/tokens.g.dart';
import '../month/day_sheet.dart' show expenseTime, spokenAmount;
import '../month/month_header.dart' show avatarLetterOf;
import 'budget_invite.dart';
import 'expense_authors.dart';

const double budgetInviteButton = 52;

const double budgetInviteGap = 8;

const double budgetInviteCodeSpacing = 17 * 0.08;

String budgetDayLabel(AppLocalizations l10n, LocalDate day, LocalDate today) {
  if (day == today) return l10n.budgetScreenToday;
  if (day == today.addDays(-1)) return l10n.budgetScreenYesterday;
  return budgetDate(day, today);
}

String budgetDate(LocalDate day, LocalDate today) => DateFormat(
  day.year == today.year ? 'd MMMM' : 'd MMMM y',
  'ru',
).format(DateTime(day.year, day.month, day.day));

String recentExpenseWhen(AppLocalizations l10n, Expense e, LocalDate today) {
  final day = budgetDayLabel(l10n, e.spentOn, today);
  final time = expenseTime(e);
  return time == null ? day : l10n.budgetScreenDayTime(day, time);
}

String recentExpenseSubtitle(
  AppLocalizations l10n,
  Expense e,
  LocalDate today,
) {
  final when = recentExpenseWhen(l10n, e, today);
  return e.comment.isEmpty ? when : '${e.comment} · $when';
}

String spellInviteCode(String code) =>
    code.split('-').map((part) => part.split('').join(' ')).join(', ');

class BudgetTopBar extends StatelessWidget {
  const BudgetTopBar({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onBack,
    this.onMenu,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onBack;
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final subtitle = this.subtitle;
    final menu = onMenu;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            _BarButton(
              icon: AppIcons.arrowLeft,
              size: 24,
              color: colors.textPrimary,
              label: l10n.a11yBack,
              onTap: onBack,
            ),
            const SizedBox(width: 2),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Semantics(
                      header: true,
                      child: FittingText(
                        title,
                        style: AppText.titleM.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    if (subtitle != null)
                      FittingText(
                        subtitle,
                        style: AppText.caption.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (menu != null)
              _BarButton(
                icon: AppIcons.more,
                size: 22,
                color: colors.textSecondary,
                label: l10n.budgetScreenMenu,
                onTap: menu,
              ),
          ],
        ),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.size,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final AppIcons icon;
  final double size;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    onTap: onTap,
    child: InkResponse(
      radius: 22,
      onTap: onTap,
      child: SizedBox.square(
        dimension: kMinTapTarget,
        child: Center(
          child: AppIcon(icon, size: size, color: color),
        ),
      ),
    ),
  );
}

class BudgetSectionHead extends StatelessWidget {
  const BudgetSectionHead({super.key, required this.title, this.note});

  final String title;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final note = this.note;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 8,
          runSpacing: 2,
          children: [
            Semantics(
              header: true,
              child: FittingText(
                title,
                style: AppText.titleS.copyWith(color: colors.textPrimary),
              ),
            ),
            if (note != null)
              ExcludeSemantics(
                child: Text(
                  note,
                  style: AppText.labelS.copyWith(color: colors.textTertiary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class BudgetMemberRow extends StatelessWidget {
  const BudgetMemberRow({
    super.key,
    required this.name,
    required this.plainName,
    required this.color,
    required this.subtitle,
    this.onLongPress,
  });

  final String name;
  final String plainName;
  final CategoryColor color;
  final String subtitle;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final longPress = onLongPress;
    return Semantics(
      label: '$name, $subtitle',
      excludeSemantics: true,
      onLongPress: longPress,
      onLongPressHint: longPress == null
          ? null
          : AppLocalizations.of(context).budgetScreenMemberHint,
      child: InkWell(
        onLongPress: longPress,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                AppAvatar(letter: avatarLetterOf(plainName), color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittingText(
                        name,
                        style: AppText.labelM.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      FittingText(
                        subtitle,
                        style: AppText.caption.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class BudgetRecentRow extends StatelessWidget {
  const BudgetRecentRow({
    super.key,
    required this.expense,
    required this.category,
    required this.subtitle,
    required this.when,
    this.author,
  });

  final Expense expense;
  final Category? category;
  final String subtitle;
  final String when;
  final ExpenseAuthorView? author;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final other = presetCategories.last;
    final category = this.category;
    final title = category?.name ?? other.name;
    final author = this.author;
    final name = author == null ? null : expenseAuthorName(l10n, author);
    final label = [
      title,
      if (expense.comment.isNotEmpty) expense.comment,
      when,
      spokenAmount(l10n, expense.amount),
      if (name != null) l10n.budgetScreenAddedBy(name),
    ].join(', ');
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: withAuthorColors(
        author,
        ExpenseRow(
          emoji: category?.emoji ?? other.emoji,
          color: category == null ? other.color : category.color,
          title: title,
          subtitle: subtitle,
          amount: expense.amount.format(),
          author: author == null ? null : expenseRowAuthor(l10n, author),
        ),
      ),
    );
  }
}

class BudgetInviteCard extends StatelessWidget {
  const BudgetInviteCard({
    super.key,
    required this.invite,
    required this.busy,
    required this.onCreate,
    required this.onCopy,
    required this.onShare,
    required this.onRenew,
    this.revoked = false,
  });

  final BudgetInvite? invite;
  final bool revoked;
  final bool busy;
  final VoidCallback onCreate;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback onRenew;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final mood = context.mood;
    final invite = this.invite;
    final onSoft = AppText.caption.copyWith(color: mood.onSoft);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
      decoration: BoxDecoration(
        color: mood.soft,
        borderRadius: BorderRadius.circular(RadiusTokens.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: FittingText(
              l10n.budgetScreenInviteTitle,
              style: AppText.titleS.copyWith(color: mood.onSoft),
            ),
          ),
          const SizedBox(height: 12),
          Text(l10n.budgetScreenInviteText, style: onSoft),
          const SizedBox(height: 12),
          if (invite == null && revoked) ...[
            Text(
              l10n.budgetScreenInviteRevoked,
              style: AppText.bodyM.copyWith(color: mood.onSoft),
            ),
            const SizedBox(height: 12),
            AppButton(
              label: l10n.budgetScreenInviteNew,
              expand: true,
              onPressed: busy ? null : onCreate,
            ),
          ] else if (invite == null)
            AppButton(
              label: l10n.budgetScreenInviteCreate,
              expand: true,
              onPressed: busy ? null : onCreate,
            )
          else
            _CodeRow(code: invite.code, onCopy: onCopy, onShare: onShare),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 18),
                  child: Text(l10n.budgetScreenInviteTtl, style: onSoft),
                ),
              ),
              if (invite != null)
                Semantics(
                  button: true,
                  enabled: !busy,
                  label: l10n.budgetScreenInviteRenew,
                  excludeSemantics: true,
                  onTap: busy ? null : onRenew,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(RadiusTokens.xs),
                    onTap: busy ? null : onRenew,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 0, 20),
                      child: Text(
                        l10n.budgetScreenInviteRenew,
                        style: AppText.labelS.copyWith(
                          color: busy
                              ? context.colors.textDisabled
                              : mood.accentStrong,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CodeRow extends StatelessWidget {
  const _CodeRow({
    required this.code,
    required this.onCopy,
    required this.onShare,
  });

  final String code;
  final VoidCallback onCopy;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final mood = context.mood;
    final style = AppText.displayS.copyWith(
      color: colors.textPrimary,
      letterSpacing: budgetInviteCodeSpacing,
    );
    final box = Semantics(
      label: l10n.budgetScreenInviteCode(spellInviteCode(code)),
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: budgetInviteButton),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.bgSurface,
          borderRadius: BorderRadius.circular(RadiusTokens.md),
        ),
        child: FittingText(code, style: style, textAlign: TextAlign.center),
      ),
    );
    final copy = _SquareButton(
      icon: AppIcons.copy,
      background: mood.accent,
      color: mood.onAccent,
      label: l10n.budgetScreenInviteCopy,
      onTap: onCopy,
    );
    final share = _SquareButton(
      icon: AppIcons.share,
      background: colors.bgSurface,
      color: mood.onSoft,
      label: l10n.budgetScreenInviteShare,
      onTap: onShare,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final buttons = budgetInviteButton * 2 + budgetInviteGap * 2;
        final codeWidth = FittingText.widestWord(context, code, style) + 12 * 2;
        if (codeWidth <= constraints.maxWidth - buttons) {
          return Row(
            children: [
              Expanded(child: box),
              const SizedBox(width: budgetInviteGap),
              copy,
              const SizedBox(width: budgetInviteGap),
              share,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            box,
            const SizedBox(height: budgetInviteGap),
            Row(
              children: [
                copy,
                const SizedBox(width: budgetInviteGap),
                share,
              ],
            ),
          ],
        );
      },
    );
  }
}

class _SquareButton extends StatelessWidget {
  const _SquareButton({
    required this.icon,
    required this.background,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final AppIcons icon;
  final Color background;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    onTap: onTap,
    child: Material(
      color: background,
      borderRadius: BorderRadius.circular(RadiusTokens.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox.square(
          dimension: budgetInviteButton,
          child: Center(child: AppIcon(icon, size: 22, color: color)),
        ),
      ),
    ),
  );
}
