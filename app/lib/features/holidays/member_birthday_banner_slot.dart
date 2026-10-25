import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/components/holiday_banner.dart';
import '../month/month_header.dart' show avatarLetterOf;
import 'holiday_banner_controller.dart';
import 'member_birthdays.dart';

final _log = Logger('holidays');

class MemberBirthdayBannerSlot extends ConsumerStatefulWidget {
  const MemberBirthdayBannerSlot({
    super.key,
    required this.birthday,
    required this.budgetId,
    required this.budgetName,
  });

  final MemberBirthday birthday;
  final String budgetId;
  final String budgetName;

  @override
  ConsumerState<MemberBirthdayBannerSlot> createState() =>
      _MemberBirthdayBannerSlotState();
}

class _MemberBirthdayBannerSlotState
    extends ConsumerState<MemberBirthdayBannerSlot> {
  @override
  void initState() {
    super.initState();
    _logShown();
  }

  @override
  void didUpdateWidget(covariant MemberBirthdayBannerSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.birthday.userId != widget.birthday.userId ||
        oldWidget.budgetId != widget.budgetId) {
      _logShown();
    }
  }

  void _logShown() {
    _log.fine(
      'member birthday banner shown userId=${widget.birthday.userId} '
      'budgetId=${widget.budgetId}',
    );
  }

  void _close() {
    final birthday = widget.birthday;
    _log.fine(
      'member birthday banner close tap userId=${birthday.userId} '
      'budgetId=${widget.budgetId}',
    );
    ref
        .read(hiddenHolidayBannersProvider.notifier)
        .hideMemberBirthday(birthday.userId, birthday.date);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final birthday = widget.birthday;
    return HolidayBanner.member(
      avatarLetter: avatarLetterOf(birthday.name),
      avatarColor: birthday.color,
      title: memberBirthdayBannerTitle(l10n, birthday),
      subtitle: memberBirthdayBannerSubtitle(l10n, birthday, widget.budgetName),
      onClose: _close,
    );
  }
}
