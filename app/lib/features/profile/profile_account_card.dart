import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared/shared.dart' show CategoryColor;

import '../../core/clock.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/components/avatar.dart';
import '../../ui/components/fitting_text.dart';
import '../../ui/icons/app_icon.dart';
import '../../ui/theme/app_text.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/tokens/tokens.g.dart';
import '../month/month_header.dart' show avatarLetterOf;

const Duration profileSyncTick = Duration(seconds: 30);

String syncedAgo(AppLocalizations l10n, DateTime at, DateTime now) {
  final passed = now.difference(at);
  if (passed < const Duration(minutes: 1)) return l10n.profileAgoNow;
  if (passed < const Duration(hours: 1)) {
    return l10n.profileAgoMinutes(passed.inMinutes);
  }
  if (passed < const Duration(days: 1)) {
    return l10n.profileAgoHours(passed.inHours);
  }
  final local = at.toLocal();
  final pattern = local.year == now.year ? 'd MMMM' : 'd MMMM y';
  return DateFormat(pattern, 'ru').format(local);
}

class ProfileAccountCard extends ConsumerStatefulWidget {
  const ProfileAccountCard({
    super.key,
    required this.name,
    required this.login,
    required this.color,
    required this.lastSyncAt,
  });

  final String name;
  final String login;
  final CategoryColor color;
  final DateTime? lastSyncAt;

  @override
  ConsumerState<ProfileAccountCard> createState() => _ProfileAccountCardState();
}

class _ProfileAccountCardState extends ConsumerState<ProfileAccountCard> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(profileSyncTick, (_) {
      if (mounted && widget.lastSyncAt != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final at = widget.lastSyncAt;
    final synced = at != null;
    final statusColor = synced ? colors.statusSuccess : colors.textTertiary;
    final status = synced
        ? l10n.profileSynced(
            syncedAgo(l10n, at, ref.watch(clockProvider).now()),
          )
        : l10n.profileNotSynced;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: BorderRadius.circular(RadiusTokens.xl),
        boxShadow: ShadowTokens.card,
      ),
      child: Row(
        children: [
          AppAvatar(
            letter: avatarLetterOf(widget.name),
            size: AvatarSize.s64,
            color: widget.color,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittingText(
                  widget.name,
                  style: AppText.titleM.copyWith(color: colors.textPrimary),
                ),
                const SizedBox(height: 2),
                FittingText(
                  l10n.profileLogin(widget.login),
                  style: AppText.bodyS.copyWith(color: colors.textTertiary),
                ),
                const SizedBox(height: 2),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppIcon(
                        synced ? AppIcons.cloudCheck : AppIcons.cloudOff,
                        size: 16,
                        color: statusColor,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: FittingText(
                          status,
                          style: AppText.caption.copyWith(color: statusColor),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
