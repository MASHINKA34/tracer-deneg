import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/core/recurring_triggers.dart';
import 'package:milionchik/data/recurring_service.dart';
import 'package:shared/shared.dart';

final class _FakeTimer implements Timer {
  _FakeTimer(this.delay, this.callback);

  final Duration delay;
  final void Function() callback;
  bool cancelled = false;
  bool fired = false;

  @override
  bool get isActive => !cancelled && !fired;

  @override
  int get tick => fired ? 1 : 0;

  @override
  void cancel() => cancelled = true;

  void fire() {
    fired = true;
    callback();
  }
}

void main() {
  late DateTime now;
  late List<RecurringRunReason> runs;
  late List<_FakeTimer> timers;
  late List<LogRecord> records;
  late StreamSubscription<LogRecord> sub;
  late RecurringTriggers triggers;

  RecurringRunResult resultFor(RecurringRunReason reason) => RecurringRunResult(
    reason: reason,
    today: LocalDate.fromDateTime(now),
    rules: 0,
    created: 0,
    skippedExisting: 0,
    skippedDeleted: 0,
    failedRules: 0,
    elapsed: Duration.zero,
  );

  RecurringTriggers build({RecurringRun? run}) => RecurringTriggers(
    run:
        run ??
        (reason) async {
          runs.add(reason);
          return resultFor(reason);
        },
    clock: () => Clock(now: () => now),
    timer: (delay, callback) {
      final timer = _FakeTimer(delay, callback);
      timers.add(timer);
      return timer;
    },
  );

  _FakeTimer activeTimer() => timers.singleWhere((t) => t.isActive);

  setUp(() {
    now = DateTime(2026, 10, 22, 18, 40);
    runs = [];
    timers = [];
    records = [];
    Logger.root.level = Level.ALL;
    sub = Logger.root.onRecord.listen(records.add);
    triggers = build();
  });

  tearDown(() async {
    triggers.dispose();
    await sub.cancel();
  });

  test('до полуночи: 18:40 → 5 ч 20 мин, 31.12 23:00 → 1 ч, ровно 00:00 → сутки', () {
    expect(
      untilNextMidnight(DateTime(2026, 10, 22, 18, 40)),
      const Duration(hours: 5, minutes: 20),
    );
    expect(
      untilNextMidnight(DateTime(2026, 12, 31, 23)),
      const Duration(hours: 1),
    );
    expect(untilNextMidnight(DateTime(2026, 2, 28)), const Duration(hours: 24));
  });

  test('старт: запуск «startup» и таймер до 00:00', () {
    triggers.start();

    expect(runs, [RecurringRunReason.startup]);
    expect(triggers.lastDay, LocalDate(2026, 10, 22));
    expect(activeTimer().delay, const Duration(hours: 5, minutes: 20));
  });

  test('полночь при открытом приложении: запуск «midnight» и новый таймер на '
      'сутки', () {
    triggers.start();
    now = DateTime(2026, 10, 23, 0, 0, 0, 5);

    activeTimer().fire();

    expect(runs, [RecurringRunReason.startup, RecurringRunReason.midnight]);
    expect(triggers.lastDay, LocalDate(2026, 10, 23));
    expect(
      activeTimer().delay,
      const Duration(hours: 24) - const Duration(milliseconds: 5),
    );
  });

  test('таймер сработал раньше полуночи: запуска нет, перезапуск не чаще '
      'раза в секунду', () {
    triggers.start();
    now = DateTime(2026, 10, 22, 23, 59, 59, 900);

    activeTimer().fire();

    expect(runs, [RecurringRunReason.startup]);
    expect(activeTimer().delay, RecurringTriggers.minMidnightDelay);
  });

  test('уход в фон гасит таймер; возврат в тот же день — без запуска, таймер '
      'снова стоит', () {
    triggers.start();
    final first = activeTimer();

    triggers.paused();
    expect(first.cancelled, isTrue);
    expect(triggers.midnightScheduled, isFalse);

    now = DateTime(2026, 10, 22, 21);
    triggers.resumed();

    expect(runs, [RecurringRunReason.startup]);
    expect(activeTimer().delay, const Duration(hours: 3));
  });

  test('возврат из фона на следующий день: запуск «day changed»', () {
    triggers.start();
    triggers.paused();
    now = DateTime(2026, 11, 1, 9, 15);

    triggers.resumed();

    expect(runs, [RecurringRunReason.startup, RecurringRunReason.dayChanged]);
    expect(triggers.lastDay, LocalDate(2026, 11, 1));
    expect(activeTimer().delay, const Duration(hours: 14, minutes: 45));

    triggers.resumed();
    expect(runs, hasLength(2));
  });

  test('смена часов (подмена «сегодня»): другой день — «day changed», '
      'тот же — ничего', () {
    triggers.start();
    now = DateTime(2026, 10, 22, 19);
    triggers.clockChanged();
    expect(runs, [RecurringRunReason.startup]);

    now = DateTime(2026, 11, 1, 19);
    triggers.clockChanged();

    expect(runs, [RecurringRunReason.startup, RecurringRunReason.dayChanged]);
    expect(timers.where((t) => t.isActive), hasLength(1));
  });

  test('после dispose таймер погашен и события не запускают генерацию', () {
    triggers.start();
    final timer = activeTimer();

    triggers.dispose();
    now = DateTime(2026, 11, 1, 9);
    triggers.resumed();
    triggers.clockChanged();

    expect(timer.cancelled, isTrue);
    expect(runs, [RecurringRunReason.startup]);
    expect(timers.where((t) => t.isActive), isEmpty);
  });

  test(
    'сбой запуска не роняет триггеры: error в лог, следующий запуск идёт',
    () async {
      var calls = 0;
      triggers = build(
        run: (reason) async {
          calls += 1;
          if (calls == 1) throw StateError('database is closed');
          runs.add(reason);
          return resultFor(reason);
        },
      );

      triggers.start();
      await pumpEventQueue();
      now = DateTime(2026, 10, 23, 0, 0, 1);
      activeTimer().fire();
      await pumpEventQueue();

      expect(runs, [RecurringRunReason.midnight]);
      expect(
        [
          for (final r in records)
            if (r.loggerName == 'recurring' && r.level == Level.SEVERE)
              formatLogRecord(r).split('\n').first,
        ],
        [
          endsWith(
            'ERROR [recurring] run (startup) crashed today=2026-10-22: '
            'StateError: Bad state: database is closed',
          ),
        ],
      );
    },
  );
}
