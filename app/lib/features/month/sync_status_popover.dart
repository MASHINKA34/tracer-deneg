import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../core/clock.dart';
import '../../data/sync/sync_engine.dart';
import '../../data/sync/sync_status_view.dart';
import '../../data/sync/sync_triggers.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/components/button.dart';
import '../../ui/components/sync_status.dart';
import '../../ui/theme/app_text.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/tokens/tokens.g.dart';
import '../profile/profile_account_card.dart' show profileSyncTick, syncedAgo;

final _log = Logger('sync');

const double syncPopoverWidth = 250;

const double syncPopoverOverlap = 6;

const double syncPopoverSide = 12;

const Duration syncPopoverFade = Duration(milliseconds: 150);

SyncState syncStateOf(SyncShown shown) => switch (shown) {
  SyncShown.done => SyncState.done,
  SyncShown.waiting => SyncState.waiting,
  SyncShown.loading || SyncShown.sending => SyncState.syncing,
  SyncShown.error => SyncState.error,
};

String syncPopoverMessage(AppLocalizations l10n, SyncStatusView view) {
  final queue = view.queue;
  return switch (view.shown) {
    SyncShown.done when queue > 0 => l10n.syncPopoverDonePending(queue),
    SyncShown.done => l10n.syncPopoverDone,
    SyncShown.loading => l10n.syncPopoverLoading,
    SyncShown.sending when queue > 0 => l10n.syncPopoverSending(queue),
    SyncShown.sending => l10n.syncPopoverChecking,
    SyncShown.waiting when queue > 0 => l10n.syncPopoverWaiting(queue),
    SyncShown.waiting => l10n.syncPopoverWaitingEmpty,
    SyncShown.error when queue > 0 => l10n.syncPopoverError(queue),
    SyncShown.error => l10n.syncPopoverErrorEmpty,
  };
}

String syncPopoverLastSync(
  AppLocalizations l10n,
  DateTime? lastSyncAt,
  DateTime now,
) => lastSyncAt == null
    ? l10n.syncPopoverNeverSynced
    : l10n.syncPopoverLastSync(syncedAgo(l10n, lastSyncAt, now));

Future<void> showSyncStatusPopover(
  BuildContext context, {
  required Rect header,
}) {
  final sw = Stopwatch()..start();
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: syncPopoverFade,
    pageBuilder: (context, animation, secondaryAnimation) =>
        _SyncPopoverLayer(header: header),
    transitionBuilder: (context, animation, secondaryAnimation, child) =>
        FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
  ).whenComplete(
    () => _log.fine(
      'sync status popover closed after ${sw.elapsedMilliseconds}ms',
    ),
  );
}

class _SyncPopoverLayer extends StatelessWidget {
  const _SyncPopoverLayer({required this.header});

  final Rect header;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final top = header.bottom - syncPopoverOverlap;
    final right =
        math.max(0.0, media.size.width - header.right) + syncPopoverSide;
    final maxHeight = math.max(
      0.0,
      media.size.height - top - media.padding.bottom - syncPopoverSide,
    );
    final maxWidth = math.max(0.0, media.size.width - 2 * syncPopoverSide);
    final wide = media.textScaler.scale(1) > 1;
    return Stack(
      children: [
        Positioned(
          top: top,
          right: right,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: wide ? maxWidth : math.min(syncPopoverWidth, maxWidth),
              maxHeight: maxHeight,
            ),
            child: const LiveSyncStatusPopover(),
          ),
        ),
      ],
    );
  }
}

class LiveSyncStatusPopover extends ConsumerStatefulWidget {
  const LiveSyncStatusPopover({super.key});

  @override
  ConsumerState<LiveSyncStatusPopover> createState() =>
      _LiveSyncStatusPopoverState();
}

class _LiveSyncStatusPopoverState extends ConsumerState<LiveSyncStatusPopover> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _log.fine('sync status popover opened ${ref.read(syncStatusViewProvider)}');
    _tick = Timer.periodic(profileSyncTick, (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _retry() {
    final view = ref.read(syncStatusViewProvider);
    final engine = ref.read(syncEngineProvider);
    _log.info(
      'sync status retry tap shown=${view.shown.name} queue=${view.queue} '
      'failures=${engine.state.failures} → sync reason=manual',
    );
    final sw = Stopwatch()..start();
    unawaited(
      ref
          .read(syncTriggersProvider)
          .retryTapped()
          .then<void>(
            (result) => _log.fine(
              'sync status retry finished in ${sw.elapsedMilliseconds}ms: '
              '$result',
            ),
            onError: (Object e, StackTrace st) => _log.severe(
              'sync status retry crashed after ${sw.elapsedMilliseconds}ms: '
              '${describeError(e)}',
              e,
              st,
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(syncStatusViewProvider);
    return SyncStatusPopover(
      view: view,
      now: ref.watch(clockProvider).now(),
      onRetry: _retry,
    );
  }
}

class SyncStatusPopover extends StatelessWidget {
  const SyncStatusPopover({
    super.key,
    required this.view,
    required this.now,
    this.onRetry,
  });

  final SyncStatusView view;
  final DateTime now;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = AppLocalizations.of(context);
    final caption = AppText.caption;
    final wide = MediaQuery.textScalerOf(context).scale(1) > 1;
    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: wide ? double.infinity : syncPopoverWidth,
        decoration: BoxDecoration(
          color: colors.bgSurface,
          borderRadius: BorderRadius.circular(RadiusTokens.md),
          boxShadow: ShadowTokens.raised,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SyncStatus(state: syncStateOf(view.shown), pending: view.queue),
              const SizedBox(height: 8),
              Text(
                syncPopoverMessage(l10n, view),
                style: caption.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: 8),
              Text(
                syncPopoverLastSync(l10n, view.lastSyncAt, now),
                style: caption.copyWith(color: colors.textTertiary),
              ),
              if (view.shown == SyncShown.error) ...[
                const SizedBox(height: 8),
                AppButton(
                  label: l10n.syncPopoverRetry,
                  onPressed: onRetry,
                  type: AppButtonType.soft,
                  size: AppButtonSize.m,
                  expand: true,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
