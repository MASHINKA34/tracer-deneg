import 'package:flutter/material.dart';
import 'package:shared/shared.dart' show CategoryColor;

import '../../l10n/app_localizations.dart';
import '../icons/app_icon.dart';
import '../theme/app_text.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';
import 'avatar.dart';

/// Вариант плашки праздника (Figma HolidayBanner `26:3600`, свойство «Тип»).
enum HolidayBannerType {
  /// До «дня»: белая плашка, эмодзи на `accent/soft`.
  countdown,

  /// В «день» и после: заливка `accent`, текст `on-accent`.
  greeting,

  /// День рождения участника: белая плашка с аватаром.
  member,
}

/// Плашка над карточкой месяца: эмодзи или аватар, заголовок и подпись
/// (переносятся), крестик «спрятать» (00-spec §7.6.4–7.6.5).
class HolidayBanner extends StatelessWidget {
  const HolidayBanner.countdown({
    super.key,
    required String this.emoji,
    required this.title,
    required this.subtitle,
    required this.onClose,
  }) : type = HolidayBannerType.countdown,
       avatarLetter = null,
       avatarColor = null;

  const HolidayBanner.greeting({
    super.key,
    required String this.emoji,
    required this.title,
    required this.subtitle,
    required this.onClose,
  }) : type = HolidayBannerType.greeting,
       avatarLetter = null,
       avatarColor = null;

  const HolidayBanner.member({
    super.key,
    required String this.avatarLetter,
    required CategoryColor this.avatarColor,
    required this.title,
    required this.subtitle,
    required this.onClose,
  }) : type = HolidayBannerType.member,
       emoji = null;

  final HolidayBannerType type;
  final String? emoji;
  final String? avatarLetter;
  final CategoryColor? avatarColor;
  final String title;
  final String subtitle;

  /// Крестик; `null` — без крестика.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mood = context.mood;
    final greeting = type == HolidayBannerType.greeting;
    final titleColor = greeting ? mood.onAccent : colors.textPrimary;
    final subtitleColor = greeting ? mood.onAccent : colors.textSecondary;
    final closeColor = greeting ? mood.onAccent : colors.textTertiary;
    final bordered = !greeting;

    final Widget leading = type == HolidayBannerType.member
        ? AppAvatar(letter: avatarLetter!, color: avatarColor!)
        : Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: greeting ? colors.bgSurface : mood.soft,
              borderRadius: BorderRadius.circular(RadiusTokens.sm),
            ),
            child: ExcludeSemantics(
              child: Text(
                emoji!,
                style: AppText.titleM.copyWith(color: colors.textPrimary),
                textScaler: TextScaler.noScaling,
              ),
            ),
          );

    final banner = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: greeting ? mood.accent : colors.bgSurface,
        borderRadius: BorderRadius.circular(RadiusTokens.lg),
        border: bordered ? Border.all(color: colors.borderDefault) : null,
      ),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: AppText.labelM.copyWith(color: titleColor)),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppText.caption.copyWith(color: subtitleColor),
                ),
              ],
            ),
          ),
          if (onClose != null) ...[
            const SizedBox(width: 12),
            AppIcon(AppIcons.x, size: 18, color: closeColor),
          ],
        ],
      ),
    );

    if (onClose == null) return banner;
    // Крестик 18 нарисован в строке; область нажатия 48 — поверх, по его
    // центру, чтобы не сдвигать текст.
    final borderWidth = bordered ? 1.0 : 0.0;
    return Stack(
      children: [
        banner,
        Positioned(
          top: 0,
          bottom: 0,
          right: 12 + borderWidth + 9 - 24,
          child: Center(
            child: Semantics(
              button: true,
              label: AppLocalizations.of(context).a11yClose,
              child: InkResponse(
                radius: 20,
                onTap: onClose,
                child: const SizedBox.square(dimension: 48),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
