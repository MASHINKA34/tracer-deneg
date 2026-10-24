import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../data/providers.dart';
import '../../data/session/session_providers.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/components/holiday_banner.dart';
import 'holiday_banner_controller.dart';
import 'holiday_banner_texts.dart';

final _log = Logger('holidays');

class HolidayBannerSlot extends ConsumerStatefulWidget {
  const HolidayBannerSlot({super.key, required this.phase});

  final HolidayPhase phase;

  @override
  ConsumerState<HolidayBannerSlot> createState() => _HolidayBannerSlotState();
}

class _HolidayBannerSlotState extends ConsumerState<HolidayBannerSlot> {
  @override
  void initState() {
    super.initState();
    _logShown(null);
  }

  @override
  void didUpdateWidget(covariant HolidayBannerSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phase != widget.phase) _logShown(oldWidget.phase);
  }

  void _logShown(HolidayPhase? previous) {
    final phase = widget.phase;
    final birthday = phase.key == HolidayKey.birthday;
    _log.fine(
      'holiday banner shown holiday=${phase.key.name} '
      'stage=${phase.stage.name}'
      '${birthday ? '' : ' daysUntilDay=${phase.daysUntilDay}'} '
      'id=${phase.occurrence.id} type=${_type(phase).name}'
      '${previous == null ? '' : ' (was ${previous.key.name} ${previous.stage.name})'}',
    );
  }

  HolidayBannerType _type(HolidayPhase phase) =>
      phase.stage == HolidayStage.before
      ? HolidayBannerType.countdown
      : HolidayBannerType.greeting;

  String? _name() {
    final user = ref.watch(sessionProvider).user;
    if (user == null) return null;
    final self = ref.watch(memberProfilesProvider).value?[user.userId];
    return self?.displayName ?? user.displayName;
  }

  void _close() {
    final phase = widget.phase;
    _log.fine('holiday banner close tap id=${phase.occurrence.id}');
    ref.read(hiddenHolidayBannersProvider.notifier).hide(phase);
  }

  @override
  Widget build(BuildContext context) {
    final phase = widget.phase;
    final text = holidayBannerText(
      AppLocalizations.of(context),
      phase,
      brightness: Theme.of(context).brightness,
      name: phase.key == HolidayKey.birthday ? _name() : null,
    );
    return switch (text.type) {
      HolidayBannerType.countdown => HolidayBanner.countdown(
        emoji: text.emoji,
        title: text.title,
        subtitle: text.subtitle,
        onClose: _close,
      ),
      _ => HolidayBanner.greeting(
        emoji: text.emoji,
        title: text.title,
        subtitle: text.subtitle,
        onClose: _close,
      ),
    };
  }
}
