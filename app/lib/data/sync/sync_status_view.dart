import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import 'pull_controller.dart';
import 'sync_engine.dart';

final _log = Logger('sync');

enum SyncShown { done, loading, sending, waiting, error }

final class SyncStatusView {
  const SyncStatusView({required this.shown, this.queue = 0, this.lastSyncAt});

  final SyncShown shown;
  final int queue;
  final DateTime? lastSyncAt;

  @override
  bool operator ==(Object other) =>
      other is SyncStatusView &&
      other.shown == shown &&
      other.queue == queue &&
      other.lastSyncAt == lastSyncAt;

  @override
  int get hashCode => Object.hash(shown, queue, lastSyncAt);

  @override
  String toString() =>
      'SyncStatusView(${shown.name} queue=$queue '
      'lastSyncAt=${lastSyncAt == null ? '-' : encodeInstant(lastSyncAt!)})';
}

SyncShown shownSyncOf(
  SyncEngineState engine,
  PullStatus pull, {
  SyncShown? previous,
}) {
  if (pull.showsIndicator) return SyncShown.loading;
  return switch (engine.phase) {
    SyncPhase.idle => SyncShown.done,
    SyncPhase.waitingNetwork => SyncShown.waiting,
    SyncPhase.error => SyncShown.error,
    SyncPhase.sending
        when engine.queueSize > 0 ||
            previous == SyncShown.sending ||
            previous == SyncShown.waiting ||
            previous == SyncShown.error =>
      SyncShown.sending,
    SyncPhase.sending => SyncShown.done,
  };
}

final syncStatusViewProvider =
    NotifierProvider.autoDispose<SyncStatusController, SyncStatusView>(
      SyncStatusController.new,
      name: 'syncStatusView',
    );

final class SyncStatusController extends Notifier<SyncStatusView> {
  SyncStatusView? _view;

  @override
  SyncStatusView build() {
    final engine = ref.watch(syncEngineProvider);
    _view = null;
    StreamSubscription<SyncEngineState>? subscription;
    final start = Timer(Duration.zero, () {
      if (!ref.mounted) return;
      subscription = engine.states.listen(
        (next) => _show(next, ref.read(pullControllerProvider)),
        onError: (Object e, StackTrace st) => _log.warning(
          'sync status: engine state stream failed → keeping '
          '${_view?.shown.name ?? '-'} on screen: ${describeError(e)}',
          e,
          st,
        ),
      );
      _show(engine.state, ref.read(pullControllerProvider));
    });
    ref.onDispose(() {
      start.cancel();
      final watching = subscription;
      if (watching != null) unawaited(watching.cancel());
      _log.fine(
        'sync status no longer shown → engine state stream released, last '
        '${_view ?? '-'}',
      );
    });
    ref.listen<PullStatus>(
      pullControllerProvider,
      (previous, next) => _show(engine.state, next),
    );
    final view = _viewOf(engine.state, ref.read(pullControllerProvider));
    _view = view;
    _log.fine(
      'sync status shown ${view.shown.name} queue=${view.queue} '
      'phase=${engine.state.phase.name} (status on screen, engine state '
      'stream after this frame)',
    );
    return view;
  }

  SyncStatusView _viewOf(SyncEngineState engine, PullStatus pull) =>
      SyncStatusView(
        shown: shownSyncOf(engine, pull, previous: _view?.shown),
        queue: engine.queueSize,
        lastSyncAt: engine.lastSyncAt,
      );

  void _show(SyncEngineState engine, PullStatus pull) {
    final previous = _view;
    final next = _viewOf(engine, pull);
    if (next == previous) return;
    _view = next;
    if (previous == null ||
        previous.shown != next.shown ||
        previous.queue != next.queue) {
      _log.fine(
        'sync status shown ${previous?.shown.name ?? '-'} → '
        '${next.shown.name} queue=${previous?.queue ?? '-'}→${next.queue} '
        'phase=${engine.phase.name} pull=$pull',
      );
    }
    state = next;
  }
}
