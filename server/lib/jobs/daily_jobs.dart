import 'dart:async';

import 'package:logging/logging.dart';
import 'package:shared/logging.dart';

final _log = Logger('jobs');

const Duration dailyJobsInterval = Duration(days: 1);
const Duration dailyJobsStopTimeout = Duration(seconds: 10);

class DailyJob {
  const DailyJob(this.name, this.run);

  final String name;
  final Future<String> Function() run;
}

final class DailyJobsRun {
  const DailyJobsRun({
    required this.number,
    required this.ok,
    required this.failed,
  });

  final int number;
  final List<String> ok;
  final List<String> failed;
}

class DailyJobs {
  DailyJobs(
    List<DailyJob> jobs, {
    this.interval = dailyJobsInterval,
    this._now = DateTime.now,
  }) : jobs = List.unmodifiable(jobs);

  final List<DailyJob> jobs;
  final Duration interval;
  final DateTime Function() _now;

  Timer? _timer;
  Future<DailyJobsRun>? _running;
  bool _stopped = false;
  int _runs = 0;
  DateTime? _nextRunAt;

  bool get isRunning => _running != null;

  void start() {
    if (_timer != null || _stopped) {
      _log.warning(
        'daily jobs start ignored: ${_stopped ? 'already stopped' : 'already started'}',
      );
      return;
    }
    _log.info(
      'daily jobs scheduled jobs=${_names()} '
      'interval=${_describe(interval)} firstRun=now',
    );
    _timer = Timer.periodic(interval, (_) => _trigger('timer'));
    _trigger('startup');
  }

  Future<DailyJobsRun> runNow(String reason) {
    final running = _running;
    if (running != null) {
      _log.info(
        'daily jobs run requested reason=$reason while run is in progress '
        '→ waiting for it',
      );
      return running;
    }
    final run = _runAll(reason);
    _running = run;
    return run.whenComplete(() => _running = null);
  }

  Future<void> stop(String reason) async {
    final sw = Stopwatch()..start();
    _stopped = true;
    _timer?.cancel();
    _timer = null;
    final running = _running;
    _log.info('stopping daily jobs ($reason) running=${running != null}');
    if (running != null) {
      try {
        await running.timeout(dailyJobsStopTimeout);
      } on TimeoutException {
        _log.warning(
          'daily jobs still running after '
          '${dailyJobsStopTimeout.inSeconds}s, not waiting any longer',
        );
      }
    }
    _log.info('daily jobs stopped in ${sw.elapsedMilliseconds}ms');
  }

  void _trigger(String reason) {
    if (_stopped) return;
    _nextRunAt = _now().add(interval);
    if (_running != null) {
      _log.warning(
        'daily jobs run skipped reason=$reason: previous run is still in '
        'progress',
      );
      return;
    }
    unawaited(runNow(reason));
  }

  Future<DailyJobsRun> _runAll(String reason) async {
    final number = ++_runs;
    final total = Stopwatch()..start();
    _log.info(
      'daily jobs run #$number started reason=$reason '
      'at=${formatLogTime(_now())} jobs=${_names()}',
    );
    final ok = <String>[];
    final failed = <String>[];
    for (final job in jobs) {
      final sw = Stopwatch()..start();
      _log.info('job ${job.name} started (run #$number)');
      try {
        final result = await job.run();
        ok.add(job.name);
        _log.info(
          'job ${job.name} done $result in ${sw.elapsedMilliseconds}ms',
        );
      } catch (e, st) {
        failed.add(job.name);
        _log.severe(
          'job ${job.name} failed in ${sw.elapsedMilliseconds}ms: '
          '${describeError(e)} → continuing with the next job',
          e,
          st,
        );
      }
    }
    final next = _nextRunAt;
    _log.log(
      failed.isEmpty ? Level.INFO : Level.WARNING,
      'daily jobs run #$number finished ok=${ok.length} '
      'failed=${failed.length}${failed.isEmpty ? '' : ' (${failed.join(',')})'} '
      'in ${total.elapsedMilliseconds}ms '
      'nextRun=${next == null || _stopped ? 'none' : formatLogTime(next)}',
    );
    return DailyJobsRun(
      number: number,
      ok: List.unmodifiable(ok),
      failed: List.unmodifiable(failed),
    );
  }

  String _names() =>
      jobs.isEmpty ? 'none' : jobs.map((job) => job.name).join(',');
}

String _describe(Duration duration) {
  if (duration.inMicroseconds % Duration.microsecondsPerDay == 0) {
    return '${duration.inDays}d';
  }
  if (duration.inMicroseconds % Duration.microsecondsPerHour == 0) {
    return '${duration.inHours}h';
  }
  if (duration.inMicroseconds % Duration.microsecondsPerSecond == 0) {
    return '${duration.inSeconds}s';
  }
  return '${duration.inMilliseconds}ms';
}
