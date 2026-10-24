import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../core/network_status.dart';
import 'sync_engine.dart';

final _log = Logger('sync');

const Duration periodicSyncInterval = Duration(seconds: 60);

typedef SyncRequest = Future<SyncCycleResult> Function(SyncReason reason);

typedef SyncTriggerTimer = Timer Function(
  Duration delay,
  void Function() callback,
);

bool _noRetry() => false;

final class SyncTriggers {
  SyncTriggers({
    required this._sync,
    bool Function()? retryScheduled,
    SyncTriggerTimer? timer,
  }) : _retryScheduled = retryScheduled ?? _noRetry,
       _timer = timer ?? Timer.new;

  final SyncRequest _sync;
  final bool Function() _retryScheduled;
  final SyncTriggerTimer _timer;

  bool _started = false;
  bool _disposed = false;
  bool _signedIn = false;
  bool _foreground = true;
  bool? _online;
  Timer? _periodic;

  bool get started => _started;

  bool get foreground => _foreground;

  bool? get online => _online;

  bool get periodicScheduled => _periodic != null;

  void start({required bool signedIn, required bool foreground}) {
    if (_disposed) return;
    _started = true;
    _signedIn = signedIn;
    _foreground = foreground;
    _log.info(
      'sync triggers on: startup, resume, network, periodic every '
      '${periodicSyncInterval.inSeconds}s in foreground, pull down, '
      'websocket; session=${signedIn ? 'active' : 'none'} '
      'foreground=$foreground',
    );
    if (!signedIn) {
      _log.fine(
        'sync triggers: no active session at start → no startup sync, '
        'waiting for sign-in',
      );
      return;
    }
    if (foreground) _armPeriodic('app started');
    _fire(SyncReason.startup, 'app started with a session');
  }

  void stop(String why) {
    if (!_started) return;
    _started = false;
    final periodic = _cancelPeriodic();
    _log.fine(
      'sync triggers off: $why → periodic timer '
      '${periodic ? 'cancelled' : 'not running'}',
    );
  }

  void dispose() {
    if (_disposed) return;
    stop('disposed');
    _disposed = true;
  }

  void sessionChanged({required bool active, required String change}) {
    if (_disposed) return;
    final was = _signedIn;
    _signedIn = active;
    if (!_started) return;
    if (was == active) {
      _log.fine('sync triggers: session $change, still active=$active');
      return;
    }
    if (!active) {
      final periodic = _cancelPeriodic();
      _log.fine(
        'sync triggers: session $change → no syncs until sign-in, periodic '
        'timer ${periodic ? 'stopped' : 'not running'}',
      );
      return;
    }
    if (_foreground) _armPeriodic('signed in');
    _fire(SyncReason.startup, 'signed in (session $change)');
  }

  void resumed() {
    if (_disposed || !_started) return;
    if (_foreground) {
      _log.fine(
        'sync triggers: app resumed from inactive, not from background → '
        'no sync',
      );
      return;
    }
    _foreground = true;
    if (!_signedIn) {
      _log.fine(
        'sync triggers: app back from background, no active session → no '
        'sync, no periodic timer',
      );
      return;
    }
    _armPeriodic('app back from background');
    _fire(SyncReason.resume, 'app back from background');
  }

  void paused() {
    if (_disposed || !_started) return;
    _foreground = false;
    final periodic = _cancelPeriodic();
    _log.fine(
      'sync triggers: app in background → periodic timer '
      '${periodic ? 'stopped' : 'not running'}, resume syncs again',
    );
  }

  void networkChanged(List<ConnectivityResult> results) {
    if (_disposed || !_started) return;
    final online = isOnline(results);
    final was = _online;
    _online = online;
    final types = results.map((r) => r.name).join(',');
    if (was == null) {
      _log.fine(
        'sync triggers: network online=$online types=$types (first event) '
        '→ no sync, the startup sync covers it',
      );
      return;
    }
    if (online == was) {
      _log.fine(
        'sync triggers: network changed types=$types, still online=$online '
        '→ no sync',
      );
      return;
    }
    if (!online) {
      _log.info(
        'network lost types=$types → sync waits for network, changes stay '
        'in the queue',
      );
      return;
    }
    if (!_signedIn) {
      _log.info('network appeared types=$types → no sync: no active session');
      return;
    }
    if (!_foreground) {
      _log.info(
        'network appeared types=$types while the app is in background → no '
        'sync now, resume runs one',
      );
      return;
    }
    _log.info('network appeared types=$types → sync reason=network');
    _fire(SyncReason.network, 'network appeared types=$types');
  }

  Future<SyncCycleResult> pulledDown() =>
      _request(SyncReason.manual, 'pulled down on the main screen');

  Future<SyncCycleResult> websocketChanged() =>
      _request(SyncReason.websocket, 'server sent changed over the websocket');

  void _armPeriodic(String why) {
    _periodic?.cancel();
    _periodic = _timer(periodicSyncInterval, _periodicTick);
    _log.fine(
      'sync triggers: periodic timer set to ${periodicSyncInterval.inSeconds}s '
      '($why)',
    );
  }

  void _periodicTick() {
    _periodic = null;
    if (_disposed || !_started || !_signedIn || !_foreground) return;
    _periodic = _timer(periodicSyncInterval, _periodicTick);
    if (_retryScheduled()) {
      _log.fine(
        'sync triggers: periodic tick while the engine waits for its retry '
        'timer after a failure → no extra cycle, the retry runs it',
      );
      return;
    }
    _fire(
      SyncReason.periodic,
      'every ${periodicSyncInterval.inSeconds}s while the app is open',
    );
  }

  bool _cancelPeriodic() {
    final timer = _periodic;
    if (timer == null) return false;
    timer.cancel();
    _periodic = null;
    return true;
  }

  Future<SyncCycleResult> _request(SyncReason reason, String why) {
    _log.fine('sync trigger reason=${reason.name}: $why');
    return _sync(reason);
  }

  void _fire(SyncReason reason, String why) {
    final Future<SyncCycleResult> running;
    try {
      running = _request(reason, why);
    } catch (e, st) {
      _log.severe(
        'sync trigger reason=${reason.name} did not start a cycle ($why): '
        '${describeError(e)}',
        e,
        st,
      );
      return;
    }
    unawaited(
      running.then<void>(
        (_) {},
        onError: (Object e, StackTrace st) {
          _log.severe(
            'sync cycle reason=${reason.name} started by a trigger crashed '
            '($why): ${describeError(e)}',
            e,
            st,
          );
        },
      ),
    );
  }
}

final syncTriggersProvider = Provider<SyncTriggers>((ref) {
  final engine = ref.watch(syncEngineProvider);
  final triggers = SyncTriggers(
    sync: engine.sync,
    retryScheduled: () => engine.retryScheduled,
  );
  ref.onDispose(triggers.dispose);
  return triggers;
}, name: 'syncTriggers');
