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

  ProviderContainer container() => ProviderContainer.test(
    overrides: [
      clockProvider.overrideWithValue(
        Clock(now: () => DateTime(2026, 10, 19, 18, 40)),
      ),
    ],
  );

  Iterable<String> monthLines(Level level) => records
      .where((r) => r.loggerName == 'month' && r.level == level)
      .map((r) => r.message);

  test('выбор из шторки: прошлый месяц любого года открывается, тот же — '
      'без смены, будущий — отказ с warn, месяц не меняется', () {
    final c = container();
    final controller = c.read(monthControllerProvider.notifier);

    expect(controller.open(YearMonth(2026, 9)), isTrue);
    expect(c.read(monthControllerProvider), YearMonth(2026, 9));
    expect(controller.open(YearMonth(2024, 2)), isTrue);
    expect(c.read(monthControllerProvider), YearMonth(2024, 2));
    expect(controller.open(YearMonth(2024, 2)), isTrue);
    expect(controller.open(YearMonth(2026, 10)), isTrue);
    expect(c.read(monthControllerProvider), YearMonth(2026, 10));

    expect(controller.open(YearMonth(2026, 11)), isFalse);
    expect(controller.open(YearMonth(2027, 1)), isFalse);
    expect(c.read(monthControllerProvider), YearMonth(2026, 10));

    expect(
      monthLines(Level.FINE),
      containsAllInOrder([
        'month 2026-10 → 2026-09 by=picker',
        'month 2026-09 → 2024-02 by=picker',
        'month open 2024-02 by=picker: already shown',
        'month 2024-02 → 2026-10 by=picker',
      ]),
    );
    expect(monthLines(Level.WARNING), [
      'month open 2026-11 by=picker ignored: future month today=2026-10-19, '
          'staying on 2026-10',
      'month open 2027-01 by=picker ignored: future month today=2026-10-19, '
          'staying on 2026-10',
    ]);
  });
}
