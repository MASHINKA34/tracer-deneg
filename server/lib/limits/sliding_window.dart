import 'package:logging/logging.dart';

final _log = Logger('limits');

class SlidingWindowLimiter {
  SlidingWindowLimiter({
    required this.name,
    required this.limit,
    required this.window,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final String name;
  final int limit;
  final Duration window;
  final DateTime Function() _now;
  final Map<String, List<DateTime>> _hits = {};
  DateTime? _lastCleanup;

  int get trackedKeys => _hits.length;

  Duration? blockedFor(String key) {
    final now = _now();
    _cleanupIfDue(now);
    final hits = _live(key, now);
    if (hits == null || hits.length < limit) return null;
    return hits[hits.length - limit].add(window).difference(now);
  }

  int count(String key) => _live(key, _now())?.length ?? 0;

  DateTime record(String key) {
    final now = _now();
    _cleanupIfDue(now);
    (_hits[key] ??= []).add(now);
    return now;
  }

  void forget(String key, DateTime at) {
    final hits = _hits[key];
    if (hits == null) return;
    hits.remove(at);
    if (hits.isEmpty) _hits.remove(key);
  }

  int reset(String key) => _hits.remove(key)?.length ?? 0;

  List<DateTime>? _live(String key, DateTime now) {
    final hits = _hits[key];
    if (hits == null) return null;
    final expired = now.subtract(window);
    hits.removeWhere((at) => !at.isAfter(expired));
    if (hits.isNotEmpty) return hits;
    _hits.remove(key);
    return null;
  }

  void _cleanupIfDue(DateTime now) {
    final last = _lastCleanup;
    if (last != null && now.difference(last) < window) return;
    _lastCleanup = now;
    if (last == null) return;
    final sw = Stopwatch()..start();
    final before = _hits.length;
    final expired = now.subtract(window);
    _hits.removeWhere((_, hits) {
      hits.removeWhere((at) => !at.isAfter(expired));
      return hits.isEmpty;
    });
    _log.fine(
      'cleanup limiter=$name removed=${before - _hits.length} '
      'kept=${_hits.length} window=${window.inSeconds}s '
      'in ${sw.elapsedMilliseconds}ms',
    );
  }
}

int retryAfterSeconds(Duration wait) {
  final seconds = (wait.inMilliseconds + 999) ~/ 1000;
  return seconds < 1 ? 1 : seconds;
}
