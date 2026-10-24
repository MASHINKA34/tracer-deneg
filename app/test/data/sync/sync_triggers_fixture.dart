import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

final class VirtualTimer implements Timer {
  VirtualTimer(this._time, this.delay, this.due, this._callback);

  final VirtualTime _time;
  final Duration delay;
  final Duration due;
  final void Function() _callback;
  bool _active = true;

  @override
  bool get isActive => _active;

  @override
  int get tick => _active ? 0 : 1;

  @override
  void cancel() => _active = false;

  void _fire() {
    _active = false;
    _time.fired.add(delay);
    _callback();
  }
}

final class VirtualTime {
  VirtualTime({Future<void> Function()? settle})
    : _settle = settle ?? (() => pumpEventQueue());

  final Future<void> Function() _settle;
  final List<VirtualTimer> _timers = [];
  final List<Duration> fired = [];
  Duration now = Duration.zero;

  Timer start(Duration delay, void Function() callback) {
    final timer = VirtualTimer(this, delay, now + delay, callback);
    _timers.add(timer);
    return timer;
  }

  List<VirtualTimer> get active => [
    for (final t in _timers)
      if (t.isActive) t,
  ];

  Future<void> elapse(Duration by, {Future<void> Function()? settle}) async {
    final step = settle ?? _settle;
    final until = now + by;
    while (true) {
      final due = [
        for (final t in active)
          if (t.due <= until) t,
      ]..sort((a, b) => a.due.compareTo(b.due));
      if (due.isEmpty) break;
      final next = due.first;
      now = next.due;
      next._fire();
      await step();
    }
    now = until;
    await step();
  }
}
