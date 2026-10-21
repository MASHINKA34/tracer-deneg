import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/features/month/month_controller.dart';
import 'package:shared/shared.dart';

void main() {
  late List<LogRecord> records;
  late StreamSubscription<LogRecord> sub;

  setUp(() {
    records = [];
    Logger.root.level = Level.ALL;
    sub = Logger.root.onRecord.listen(records.add);
  });
  tearDown(() => sub.cancel());

  ProviderContainer container(DateTime now) => ProviderContainer.test(
    overrides: [clockProvider.overrideWithValue(Clock(now: () => now))],
  );

  Iterable<String> monthDebug() => records
      .where((r) => r.loggerName == 'month' && r.level == Level.FINE)
      .map((r) => r.message);

  test('по умолчанию — текущий месяц по часам приложения', () {
    final c = container(DateTime(2026, 10, 19, 23, 59));

    expect(c.read(monthControllerProvider), YearMonth(2026, 10));
    expect(
      monthDebug(),
      contains('selected month=2026-10 (current) today=2026-10-19'),
    );
  });

  test('‹ — предыдущий месяц через границу года, › возвращает до текущего, '
      'дальше текущего нельзя', () {
    final c = container(DateTime(2026, 1, 31, 20));
    final controller = c.read(monthControllerProvider.notifier);

    controller.previous(MonthStepSource.arrow);
    expect(c.read(monthControllerProvider), YearMonth(2025, 12));
    controller.previous(MonthStepSource.swipe);
    expect(c.read(monthControllerProvider), YearMonth(2025, 11));

    expect(controller.next(MonthStepSource.arrow), isTrue);
    expect(controller.next(MonthStepSource.swipe), isTrue);
    expect(c.read(monthControllerProvider), YearMonth(2026, 1));

    expect(controller.next(MonthStepSource.arrow), isFalse);
    expect(controller.next(MonthStepSource.swipe), isFalse);
    expect(c.read(monthControllerProvider), YearMonth(2026, 1));

    expect(
      monthDebug(),
      containsAllInOrder([
        'month 2026-01 → 2025-12 by=arrow',
        'month 2025-12 → 2025-11 by=swipe',
        'month 2025-11 → 2025-12 by=arrow',
        'month 2025-12 → 2026-01 by=swipe',
        'month next by=arrow ignored: 2026-01 is the current month, '
            '2026-02 is in the future today=2026-01-31',
        'month next by=swipe ignored: 2026-01 is the current month, '
            '2026-02 is in the future today=2026-01-31',
      ]),
    );
  });

  test('выбранный месяц живёт, пока жив контейнер, без слушателей', () async {
    final c = container(DateTime(2026, 10, 19));
    c.read(monthControllerProvider.notifier).previous(MonthStepSource.arrow);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(c.read(monthControllerProvider), YearMonth(2026, 9));
  });
}
