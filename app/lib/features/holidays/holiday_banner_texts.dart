import 'dart:ui' show Brightness;

import 'package:intl/intl.dart';
import 'package:shared/shared.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/components/holiday_banner.dart' show HolidayBannerType;

final class HolidayBannerText {
  const HolidayBannerText({
    required this.type,
    required this.emoji,
    required this.title,
    required this.subtitle,
  });

  final HolidayBannerType type;
  final String emoji;
  final String title;
  final String subtitle;

  @override
  bool operator ==(Object other) =>
      other is HolidayBannerText &&
      other.type == type &&
      other.emoji == emoji &&
      other.title == title &&
      other.subtitle == subtitle;

  @override
  int get hashCode => Object.hash(type, emoji, title, subtitle);
}

String forgivenessSundayText(LocalDate day) =>
    DateFormat('d MMMM', 'ru').format(DateTime(day.year, day.month, day.day));

HolidayBannerText holidayBannerText(
  AppLocalizations l10n,
  HolidayPhase phase, {
  required Brightness brightness,
  String? name,
}) {
  final countdown = phase.stage == HolidayStage.before;
  final days = phase.daysUntilDay;
  final dark = brightness == Brightness.dark;
  final named = name != null && name.trim().isNotEmpty ? name : null;
  final (title, subtitle) = switch (phase.key) {
    HolidayKey.newyear =>
      countdown
          ? (
              l10n.holidayBannerNewyearCountdownTitle(days),
              l10n.holidayBannerNewyearCountdownSubtitle,
            )
          : (
              l10n.holidayBannerNewyearGreetingTitle,
              l10n.holidayBannerNewyearGreetingSubtitle,
            ),
    HolidayKey.valentine =>
      countdown
          ? (
              l10n.holidayBannerValentineCountdownTitle(days),
              l10n.holidayBannerValentineCountdownSubtitle,
            )
          : (
              l10n.holidayBannerValentineGreetingTitle,
              l10n.holidayBannerValentineGreetingSubtitle,
            ),
    HolidayKey.defender =>
      countdown
          ? (
              l10n.holidayBannerDefenderCountdownTitle(days),
              l10n.holidayBannerDefenderCountdownSubtitle,
            )
          : (
              l10n.holidayBannerDefenderGreetingTitle,
              l10n.holidayBannerDefenderGreetingSubtitle,
            ),
    HolidayKey.maslenitsa =>
      countdown
          ? (
              l10n.holidayBannerMaslenitsaCountdownTitle(days),
              l10n.holidayBannerMaslenitsaCountdownSubtitle(
                forgivenessSundayText(phase.occurrence.day),
              ),
            )
          : (
              l10n.holidayBannerMaslenitsaGreetingTitle,
              l10n.holidayBannerMaslenitsaGreetingSubtitle,
            ),
    HolidayKey.women =>
      countdown
          ? (
              l10n.holidayBannerWomenCountdownTitle(days),
              l10n.holidayBannerWomenCountdownSubtitle,
            )
          : (
              l10n.holidayBannerWomenGreetingTitle,
              l10n.holidayBannerWomenGreetingSubtitle,
            ),
    HolidayKey.labour =>
      phase.stage == HolidayStage.after
          ? (
              l10n.holidayBannerLabourWeekTitle(phase.daysUntilEnd),
              l10n.holidayBannerLabourWeekSubtitle,
            )
          : (
              l10n.holidayBannerLabourDayTitle,
              l10n.holidayBannerLabourDaySubtitle,
            ),
    HolidayKey.victory => (
      countdown
          ? l10n.holidayBannerVictoryCountdownTitle
          : l10n.holidayBannerVictoryGreetingTitle,
      l10n.holidayBannerVictorySubtitle,
    ),
    HolidayKey.children =>
      countdown
          ? (
              l10n.holidayBannerChildrenCountdownTitle(days),
              l10n.holidayBannerChildrenCountdownSubtitle,
            )
          : (
              l10n.holidayBannerChildrenGreetingTitle,
              l10n.holidayBannerChildrenGreetingSubtitle,
            ),
    HolidayKey.knowledge =>
      countdown
          ? (
              l10n.holidayBannerKnowledgeCountdownTitle(days),
              l10n.holidayBannerKnowledgeCountdownSubtitle,
            )
          : (
              l10n.holidayBannerKnowledgeGreetingTitle,
              l10n.holidayBannerKnowledgeGreetingSubtitle,
            ),
    HolidayKey.halloween =>
      countdown
          ? (
              l10n.holidayBannerHalloweenCountdownTitle(days),
              dark
                  ? l10n.holidayBannerHalloweenCountdownSubtitleDark
                  : l10n.holidayBannerHalloweenCountdownSubtitleLight,
            )
          : (
              l10n.holidayBannerHalloweenGreetingTitle,
              dark
                  ? l10n.holidayBannerHalloweenGreetingSubtitleDark
                  : l10n.holidayBannerHalloweenGreetingSubtitleLight,
            ),
    HolidayKey.birthday =>
      countdown
          ? (
              l10n.holidayBannerBirthdayCountdownTitle(days),
              named == null
                  ? l10n.holidayBannerBirthdayCountdownSubtitleNoName
                  : l10n.holidayBannerBirthdayCountdownSubtitle(named),
            )
          : (
              named == null
                  ? l10n.holidayBannerBirthdayGreetingTitleNoName
                  : l10n.holidayBannerBirthdayGreetingTitle(named),
              l10n.holidayBannerBirthdayGreetingSubtitle,
            ),
  };
  return HolidayBannerText(
    type: countdown ? HolidayBannerType.countdown : HolidayBannerType.greeting,
    emoji: phase.key.emoji,
    title: title,
    subtitle: subtitle,
  );
}
