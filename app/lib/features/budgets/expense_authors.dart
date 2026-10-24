import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../data/providers.dart';
import '../../data/session/session.dart';
import '../../data/session/session_providers.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/components/expense_row.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/tokens/tokens.g.dart';
import '../month/month_header.dart' show avatarLetterOf;

final _log = Logger('budgets');

sealed class ExpenseAuthorView {
  const ExpenseAuthorView(this.userId);

  final String userId;
}

final class MemberAuthor extends ExpenseAuthorView {
  const MemberAuthor(super.userId, {required this.name, required this.color});

  final String name;
  final CategoryColor color;
}

final class RemovedAuthor extends ExpenseAuthorView {
  const RemovedAuthor(super.userId);
}

final class ExpenseAuthors {
  ExpenseAuthors({
    required this.budgetId,
    required List<BudgetMember> members,
    required this.profiles,
    required this.user,
  }) : _members = {for (final m in members) m.userId: m};

  final String budgetId;
  final Map<String, BudgetMember> _members;
  final Map<String, MemberProfile> profiles;
  final SessionUser? user;
  final Set<String> _reported = {};

  ExpenseAuthorView? of(String authorId) {
    final member = _members[authorId];
    final profile = profiles[authorId];
    final user = this.user;
    if (user != null && authorId == user.userId) {
      final color = member?.avatarColor ?? profile?.avatarColor;
      if (color == null) return null;
      return MemberAuthor(authorId, name: user.displayName, color: color);
    }
    if (member == null) {
      if (profile == null) _report(authorId, 'not a member → removed member');
      return RemovedAuthor(authorId);
    }
    if (profile == null) {
      _report(authorId, 'active member → no avatar');
      return null;
    }
    return MemberAuthor(
      authorId,
      name: profile.displayName,
      color: member.avatarColor,
    );
  }

  void _report(String authorId, String outcome) {
    if (!_reported.add(authorId)) return;
    _log.fine(
      'author profile missing userId=$authorId budgetId=$budgetId '
      'members=${_members.length} profiles=${profiles.length}: $outcome',
    );
  }
}

final expenseAuthorsProvider = Provider.autoDispose
    .family<ExpenseAuthors?, String>((ref, budgetId) {
      final budget = ref.watch(budgetProvider(budgetId));
      if (budget.hasError || budget.value?.kind != BudgetKind.shared) {
        return null;
      }
      final members = ref.watch(budgetMembersProvider(budgetId));
      final profiles = ref.watch(memberProfilesProvider);
      if (members.hasError || profiles.hasError) return null;
      final memberList = members.value;
      final profileMap = profiles.value;
      if (memberList == null || profileMap == null) return null;
      return ExpenseAuthors(
        budgetId: budgetId,
        members: memberList,
        profiles: profileMap,
        user: ref.watch(sessionProvider.select((s) => s.user)),
      );
    }, name: 'expenseAuthors');

String expenseAuthorName(AppLocalizations l10n, ExpenseAuthorView author) =>
    switch (author) {
      MemberAuthor(:final name) => name,
      RemovedAuthor() => l10n.expenseAuthorRemoved,
    };

ExpenseAuthor expenseRowAuthor(
  AppLocalizations l10n,
  ExpenseAuthorView author,
) {
  final name = expenseAuthorName(l10n, author);
  return ExpenseAuthor(
    letter: avatarLetterOf(name),
    color: switch (author) {
      MemberAuthor(:final color) => color,
      RemovedAuthor() => CategoryColor.values.first,
    },
    name: name,
  );
}

Widget withAuthorColors(ExpenseAuthorView? author, Widget row) =>
    author is RemovedAuthor ? RemovedAuthorColors(child: row) : row;

class RemovedAuthorColors extends StatelessWidget {
  const RemovedAuthorColors({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.colors;
    final neutral = colors.textTertiary;
    final extensions = Map.of(theme.extensions)
      ..[colors.type] = colors.copyWith(
        categories: {
          for (final MapEntry(:key, :value) in colors.categories.entries)
            key: CategoryTokens(solid: neutral, soft: value.soft),
        },
      );
    return Theme(
      data: theme.copyWith(extensions: extensions.values),
      child: child,
    );
  }
}
