import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../data/providers.dart';
import '../../data/session/session_providers.dart';
import '../../l10n/app_localizations.dart';
import 'holiday_banner_controller.dart';
import 'mood_controller.dart';

final _log = Logger('holidays');

final class MemberBirthday {
  const MemberBirthday({required this.upcoming, required this.color});

  final UpcomingBirthday upcoming;

  final CategoryColor color;

  String get userId => upcoming.member.userId;

  String get name => upcoming.member.displayName;

  LocalDate get date => upcoming.date;

  String get bannerId => memberBirthdayBannerId(userId, date);

  @override
  bool operator ==(Object other) =>
      other is MemberBirthday &&
      other.upcoming == upcoming &&
      other.color == color;

  @override
  int get hashCode => Object.hash(upcoming, color);

  @override
  String toString() => 'MemberBirthday($userId ${color.name})';
}

final class MemberBirthdayBanners {
  const MemberBirthdayBanners({
    required this.budgetId,
    required this.budgetName,
    required this.birthdays,
  });

  final String budgetId;

  final String budgetName;

  final List<MemberBirthday> birthdays;

  @override
  bool operator ==(Object other) =>
      other is MemberBirthdayBanners &&
      other.budgetId == budgetId &&
      other.budgetName == budgetName &&
      _sameList(other.birthdays, birthdays);

  @override
  int get hashCode =>
      Object.hash(budgetId, budgetName, Object.hashAll(birthdays));

  @override
  String toString() =>
      'MemberBirthdayBanners($budgetId ${birthdays.map((b) => b.userId)})';
}

bool _sameList(List<MemberBirthday> a, List<MemberBirthday> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool memberBirthdaysOn(HolidaySettings settings) =>
    settings.enabled && !settings.disabled.contains(HolidayKey.birthday);

final memberBirthdaysProvider = Provider.autoDispose
    .family<List<MemberBirthday>, String>((ref, budgetId) {
      final today = ref.watch(
        moodControllerProvider.select(
          (m) => (date: m.date, on: memberBirthdaysOn(m.settings)),
        ),
      );
      if (!today.on) return const [];
      final budget = ref.watch(budgetProvider(budgetId)).value;
      if (budget == null || budget.kind != BudgetKind.shared) return const [];
      final members = ref.watch(budgetMembersProvider(budgetId)).value;
      final profiles = ref.watch(memberProfilesProvider).value;
      if (members == null || profiles == null) return const [];
      final self = ref.watch(sessionProvider.select((s) => s.userId));
      final colors = {for (final m in members) m.userId: m.avatarColor};
      return [
        for (final upcoming in upcomingBirthdays(
          [for (final m in members) ?profiles[m.userId]],
          today.date,
          excludeUserId: self,
        ))
          MemberBirthday(
            upcoming: upcoming,
            color: colors[upcoming.member.userId]!,
          ),
      ];
    }, name: 'memberBirthdays');

final memberBirthdayBannersProvider =
    Provider.autoDispose<MemberBirthdayBanners?>((ref) {
      final budgetId = ref.watch(selectedBudgetIdProvider).value;
      if (budgetId == null) return null;
      final budget = ref.watch(budgetProvider(budgetId)).value;
      if (budget == null || budget.kind != BudgetKind.shared) return null;
      final birthdays = ref.watch(memberBirthdaysProvider(budgetId));
      if (birthdays.isEmpty) return null;
      final hidden = ref.watch(hiddenHolidayBannersProvider);
      final shown = <MemberBirthday>[];
      for (final birthday in birthdays) {
        if (hidden.contains(birthday.bannerId)) {
          _log.fine(
            'member birthday banner userId=${birthday.userId} '
            'budgetId=$budgetId not shown: closed earlier on this phone',
          );
        } else {
          shown.add(birthday);
        }
      }
      if (shown.isEmpty) return null;
      return MemberBirthdayBanners(
        budgetId: budgetId,
        budgetName: budget.name,
        birthdays: List.unmodifiable(shown),
      );
    }, name: 'memberBirthdayBanners');

String memberBirthdayDate(LocalDate date) => DateFormat(
  'd MMMM',
  'ru',
).format(DateTime(date.year, date.month, date.day));

String memberBirthdayBannerTitle(
  AppLocalizations l10n,
  MemberBirthday birthday,
) => birthday.upcoming.isToday
    ? l10n.memberBirthdayBannerTodayTitle(birthday.name)
    : l10n.memberBirthdayBannerTitle(
        birthday.name,
        birthday.upcoming.daysUntil,
      );

String memberBirthdayBannerSubtitle(
  AppLocalizations l10n,
  MemberBirthday birthday,
  String budgetName,
) => l10n.memberBirthdayBannerSubtitle(
  memberBirthdayDate(birthday.date),
  budgetName,
);
