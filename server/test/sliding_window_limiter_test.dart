import 'package:server/limits/sliding_window.dart';
import 'package:test/test.dart';

import 'support/limits_support.dart';
import 'support/test_support.dart';

void main() {
  late LogCapture logs;
  late FakeClock clock;
  late SlidingWindowLimiter limiter;

  setUp(() {
    logs = LogCapture();
    clock = FakeClock();
    limiter = SlidingWindowLimiter(
      name: 'test',
      limit: 3,
      window: const Duration(minutes: 1),
      now: clock.now,
    );
  });

  test('до лимита пропускает, на лимите — ждать до выхода самой старой '
      'отметки из окна', () {
    expect(limiter.blockedFor('k'), isNull);
    limiter.record('k');
    clock.advance(const Duration(seconds: 10));
    limiter.record('k');
    expect(limiter.blockedFor('k'), isNull);
    limiter.record('k');
    expect(limiter.count('k'), 3);
    expect(limiter.blockedFor('k'), const Duration(seconds: 50));

    clock.advance(const Duration(seconds: 49, milliseconds: 999));
    expect(limiter.blockedFor('k'), const Duration(milliseconds: 1));
    clock.advance(const Duration(milliseconds: 1));
    expect(limiter.blockedFor('k'), isNull);
    expect(limiter.count('k'), 2);
  });

  test('ключи независимы', () {
    for (var i = 0; i < 3; i++) {
      limiter.record('a');
    }
    expect(limiter.blockedFor('a'), isNotNull);
    expect(limiter.blockedFor('b'), isNull);
  });

  test('forget снимает одну отметку, reset — все', () {
    limiter.record('k');
    final second = limiter.record('k');
    limiter.record('k');
    expect(limiter.blockedFor('k'), isNotNull);
    limiter.forget('k', second);
    expect(limiter.count('k'), 2);
    expect(limiter.blockedFor('k'), isNull);
    expect(limiter.reset('k'), 2);
    expect(limiter.count('k'), 0);
    expect(limiter.trackedKeys, 0);
    expect(limiter.reset('k'), 0);
  });

  test('очистка раз в окно убирает устаревшие ключи и пишет debug', () {
    limiter.record('old-1');
    limiter.record('old-2');
    clock.advance(const Duration(seconds: 30));
    limiter.record('fresh');
    expect(limiter.trackedKeys, 3);
    expect(logs.text, isNot(contains('cleanup')));

    clock.advance(const Duration(seconds: 30));
    limiter.blockedFor('other');
    expect(limiter.trackedKeys, 1);
    expect(
      logs.text,
      contains(
        'DEBUG [limits] cleanup limiter=test removed=2 kept=1 '
        'window=60s in ',
      ),
    );
  });

  test('retryAfterSeconds округляет вверх и не меньше секунды', () {
    expect(retryAfterSeconds(Duration.zero), 1);
    expect(retryAfterSeconds(const Duration(milliseconds: 1)), 1);
    expect(retryAfterSeconds(const Duration(milliseconds: 1001)), 2);
    expect(retryAfterSeconds(const Duration(minutes: 15)), 900);
  });
}
