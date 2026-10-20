import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../icons/app_icon.dart';
import '../theme/app_text.dart';
import '../theme/app_theme.dart';

/// Состояние синхронизации (Figma SyncStatus `41:4127`).
enum SyncState { done, waiting, syncing, error }

/// Статус синхронизации: «таблетка» `bg/surface` с рамкой, иконка 18 и
/// текст `Label/S`. Готово — `status/success`; ждёт сети — серая с числом
/// изменений в очереди; синхронизация — `accent-strong`, иконка вращается
/// (оборот за 1 с; при «Убрать анимацию» стоит); ошибка — `status/danger`.
class SyncStatus extends StatefulWidget {
  const SyncStatus({
    super.key,
    required this.state,
    this.pending = 0,
    this.onTap,
  });

  final SyncState state;

  /// Сколько изменений ждут отправки (для «Ждёт сети · N»).
  final int pending;
  final VoidCallback? onTap;

  @override
  State<SyncStatus> createState() => _SyncStatusState();
}

class _SyncStatusState extends State<SyncStatus>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateSpin();
  }

  @override
  void didUpdateWidget(SyncStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateSpin();
  }

  void _updateSpin() {
    final spin =
        widget.state == SyncState.syncing &&
        !MediaQuery.disableAnimationsOf(context);
    if (spin && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!spin && _spin.isAnimating) {
      _spin
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mood = context.mood;
    final l10n = AppLocalizations.of(context);
    final (
      AppIcons icon,
      Color iconColor,
      Color textColor,
      String text,
    ) = switch (widget.state) {
      SyncState.done => (
        AppIcons.cloudCheck,
        colors.statusSuccess,
        colors.statusSuccess,
        l10n.syncDone,
      ),
      SyncState.waiting => (
        AppIcons.cloudOff,
        colors.textTertiary,
        colors.textSecondary,
        l10n.syncWaiting(widget.pending),
      ),
      SyncState.syncing => (
        AppIcons.refresh,
        mood.accentStrong,
        mood.accentStrong,
        l10n.syncSending,
      ),
      SyncState.error => (
        AppIcons.alertCircle,
        colors.statusDanger,
        colors.statusDanger,
        l10n.syncError,
      ),
    };

    Widget iconWidget = AppIcon(icon, size: 18, color: iconColor);
    if (widget.state == SyncState.syncing) {
      iconWidget = RotationTransition(turns: _spin, child: iconWidget);
    }
    const shape = StadiumBorder();
    return Semantics(
      liveRegion: true,
      button: widget.onTap != null,
      label: text,
      excludeSemantics: true,
      onTap: widget.onTap,
      child: Material(
        color: colors.bgSurface,
        shape: shape.copyWith(side: BorderSide(color: colors.borderDefault)),
        child: InkWell(
          customBorder: shape,
          onTap: widget.onTap,
          child: Padding(
            // 10 × 6 по Figma + рамка 1, которая там входит в размер.
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                iconWidget,
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    text,
                    style: AppText.labelS.copyWith(color: textColor),
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
