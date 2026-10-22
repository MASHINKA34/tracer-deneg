import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../data/recurring_service.dart';
import 'clock.dart';

final _log = Logger('recurring');

typedef RecurringRun = Future<RecurringRunResult> Function(
  RecurringRunReason reason,
);

typedef TriggerTimer = Timer Function(Duration delay, void Function() callback);

Duration untilNextMidnight(DateTime now) =>
    DateTime(now.year, now.month, now.day + 1).difference(now);

final class RecurringTriggers {
  RecurringTriggers({
    required this._run,
    required this._clock,
    this._timer = Timer.new,
  });

  static const Duration minMidnightDelay = Duration(seconds: 1);

  final RecurringRun _run;
  final Clock Function() _clock;
  final TriggerTimer _timer;
  LocalDate? _lastDay;
  Timer? _midnight;
  bool _disposed = false;

  LocalDate? get lastDay => _lastDay;

  bool get midnightScheduled => _midnight?.isActive ?? false;

  void start() {
    final today = _clock().today();
    _log.fine('triggers started today=$today: generating on startup');
    _fire(RecurringRunReason.startup, today);
    _scheduleMidnight();
  }

  void resumed() {
    if (_disposed) return;
    _checkDay('app resumed');
    _scheduleMidnight();
  }

  void paused() {
    if (_disposed) return;
    _cancelMidnight();
    _log.fine(
      'app paused: midnight timer cancelled, day is checked on resume '
      '(last run day $_lastDay)',
    );
  }

  void clockChanged() {
    if (_disposed) return;
    _checkDay('clock changed');
    _scheduleMidnight();
  }

  void dispose() {
    _disposed = true;
    _cancelMidnight();
    _log.fine('triggers stopped (last run day $_lastDay)');
  }

  void _checkDay(String event) {
    final today = _clock().today();
    final last = _lastDay;
    if (today == last) {
      _log.fine('$event, still $today: no run');
      return;
    }
    _log.fine('$event: day changed ${last ?? '-'} → $today');
    _fire(RecurringRunReason.dayChanged, today);
  }

  void _fire(RecurringRunReason reason, LocalDate today) {
    _lastDay = today;
    final Future<RecurringRunResult> running;
    try {
      running = _run(reason);
    } catch (e, st) {
      _log.severe(
        'run (${reason.label}) not started today=$today: ${describeError(e)}',
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
            'run (${reason.label}) crashed today=$today: ${describeError(e)}',
            e,
            st,
          );
        },
      ),
    );
  }

  void _scheduleMidnight() {
    if (_disposed) return;
    _cancelMidnight();
    final now = _clock().now();
    var delay = untilNextMidnight(now);
    if (delay < minMidnightDelay) delay = minMidnightDelay;
    _midnight = _timer(delay, _onMidnight);
    _log.fine(
      'midnight timer set in ${delay.inHours}h${delay.inMinutes % 60}m'
      '${delay.inSeconds % 60}s now=$now',
    );
  }

  void _cancelMidnight() {
    _midnight?.cancel();
    _midnight = null;
  }

  void _onMidnight() {
    _midnight = null;
    if (_disposed) return;
    final today = _clock().today();
    if (today == _lastDay) {
      _log.fine('midnight timer fired, still $today: rescheduling');
    } else {
      _log.fine('midnight: day changed ${_lastDay ?? '-'} → $today');
      _fire(RecurringRunReason.midnight, today);
    }
    _scheduleMidnight();
  }
}

class RecurringTriggersScope extends ConsumerStatefulWidget {
  const RecurringTriggersScope({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<RecurringTriggersScope> createState() =>
      _RecurringTriggersScopeState();
}

class _RecurringTriggersScopeState
    extends ConsumerState<RecurringTriggersScope> {
  late final RecurringTriggers _triggers = RecurringTriggers(
    run: (reason) => ref.read(recurringServiceProvider).run(reason),
    clock: () => ref.read(clockProvider),
  );
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: _triggers.resumed,
      onPause: _triggers.paused,
    );
    ref.listenManual(
      clockProvider,
      (_, _) => scheduleMicrotask(_triggers.clockChanged),
    );
    _triggers.start();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _triggers.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
