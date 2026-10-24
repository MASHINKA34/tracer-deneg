import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart' show TableUpdate;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../data/session/session_providers.dart';
import '../data/session/session_state.dart';
import '../data/sync/background_sync.dart';
import '../data/sync/sync_triggers.dart';
import '../data/sync/sync_websocket.dart';
import 'network_status.dart';

final _log = Logger('sync');

bool inForeground(AppLifecycleState? state) => switch (state) {
  null || AppLifecycleState.resumed || AppLifecycleState.inactive => true,
  AppLifecycleState.hidden ||
  AppLifecycleState.paused ||
  AppLifecycleState.detached => false,
};

class SyncTriggersScope extends ConsumerStatefulWidget {
  const SyncTriggersScope({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SyncTriggersScope> createState() => _SyncTriggersScopeState();
}

class _SyncTriggersScopeState extends ConsumerState<SyncTriggersScope> {
  late final SyncTriggers _triggers = ref.read(syncTriggersProvider);
  late final SyncWebSocket _socket = ref.read(syncWebSocketProvider);
  late final BackgroundSync? _background = ref.read(backgroundSyncProvider);
  late final AppLifecycleListener _lifecycle;
  StreamSubscription<List<ConnectivityResult>>? _network;
  StreamSubscription<Set<TableUpdate>>? _outbox;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _resumed, onPause: _paused);
    ref.listenManual<SessionState>(sessionProvider, (previous, next) {
      final active = next is SessionActive;
      final change = '${previous?.name ?? '-'}→${next.name}';
      _triggers.sessionChanged(active: active, change: change);
      _socket.sessionChanged(active: active, change: change);
      _background?.sessionChanged(active: active, change: change);
    });
    try {
      _outbox = ref.read(outboxWritesProvider).listen(
        (_) {
          _triggers.outboxWritten();
          _background?.outboxWritten();
        },
        onError: (Object e, StackTrace st) =>
            _streamFailed('outbox writes', e, st),
      );
    } catch (e, st) {
      _streamFailed('outbox writes', e, st);
    }
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _log.fine(
      'sync triggers scope mounted lifecycle=${lifecycle?.name ?? '-'} '
      'outboxWatch=${_outbox != null} → network status check, then watch',
    );
    final signedIn = ref.read(sessionProvider) is SessionActive;
    final foreground = inForeground(lifecycle);
    _background?.start(signedIn: signedIn, foreground: foreground);
    _triggers.start(signedIn: signedIn, foreground: foreground);
    _socket.start(signedIn: signedIn, foreground: foreground);
    unawaited(_watchNetwork());
  }

  void _resumed() {
    _triggers.resumed();
    _socket.resumed();
    _background?.resumed();
  }

  void _paused() {
    _triggers.paused();
    _socket.paused();
    _background?.paused();
  }

  void _networkChanged(List<ConnectivityResult> results) {
    _triggers.networkChanged(results);
    _socket.networkChanged(results);
  }

  Future<void> _watchNetwork() async {
    final sw = Stopwatch()..start();
    final List<ConnectivityResult> initial;
    try {
      initial = await ref.read(networkCheckProvider)();
    } catch (e, st) {
      _streamFailed('network status check', e, st);
      return;
    }
    if (!mounted) {
      _log.fine(
        'sync triggers: network status checked in ${sw.elapsedMilliseconds}ms '
        'after the scope was unmounted → not watching',
      );
      return;
    }
    _log.fine(
      'sync triggers: network status checked in ${sw.elapsedMilliseconds}ms '
      'online=${isOnline(initial)} → watching changes',
    );
    _networkChanged(initial);
    try {
      _network = ref
          .read(networkChangesProvider)
          .listen(
            _networkChanged,
            onError: (Object e, StackTrace st) =>
                _streamFailed('network status', e, st),
          );
    } catch (e, st) {
      _streamFailed('network status', e, st);
    }
  }

  void _streamFailed(String what, Object error, StackTrace stack) {
    _log.warning(
      'sync triggers: $what unavailable → no syncs from it, the other '
      'triggers keep working: ${describeError(error)}',
      error,
      stack,
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    final outbox = _outbox;
    final network = _network;
    if (outbox != null) unawaited(outbox.cancel());
    if (network != null) unawaited(network.cancel());
    _triggers.stop('triggers scope unmounted');
    _socket.stop('triggers scope unmounted');
    _background?.stop('triggers scope unmounted');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
