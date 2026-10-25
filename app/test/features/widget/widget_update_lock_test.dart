import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/core/isolate_lock.dart';
import 'package:milionchik/features/holidays/mood_controller.dart';
import 'package:milionchik/features/widget/home_widget_store.dart';
import 'package:milionchik/features/widget/widget_updater.dart';
import 'package:milionchik/l10n/app_localizations.dart';
import 'package:shared/shared.dart';

import '../../data/api/fake_api_adapter.dart' show LogCapture;
import 'widget_update_fixture.dart';

void main() {
  late AppLocalizations l10n;
  late LogCapture logs;

  setUpAll(() async {
    await initializeDateFormatting('ru');
    l10n = lookupAppLocalizations(const Locale('ru'));
  });

  setUp(() => logs = LogCapture());

  tearDown(() => logs.dispose());

  WidgetUpdater updater(
    FakeWidgetStorage storage,
    List<String> reads,
    String name, {
    required Money today,
  }) => WidgetUpdater(
    store: HomeWidgetStore(storage),
    clock: () => Clock(now: () => DateTime(2026, 10, 19, 18, 40)),
    signedOutBecause: () => null,
    selectedBudget: () async => 'budget-personal-anya',
    dayTotals: (budgetId, month) async {
      reads.add(name);
      return {19: today};
    },
    mood: () => moodTodayFor(LocalDate(2026, 10, 19), const HolidaySettings()),
    holidaySettings: () => const HolidaySettings(),
    theme: () => ThemeMode.system,
    lock: IsolateLock(homeWidgetLockName),
    l10n: l10n,
  );

  test('приложение и фоновая задача пишут виджет по очереди под одним '
      'замком: второй читает данные только после записи первого', () async {
    final storage = FakeWidgetStorage();
    final reads = <String>[];
    final background = updater(
      storage,
      reads,
      'background',
      today: const Money.rubles(640),
    );
    final app = updater(storage, reads, 'app', today: const Money.rubles(955));
    final gate = storage.gate = Completer<void>();

    final first = background.updateNow('background task sync-periodic');
    await pumpEventQueue();
    final second = app.updateNow('expenses changed');
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(reads, ['background']);
    expect(storage.writes, isEmpty);

    storage.gate = null;
    gate.complete();
    await Future.wait([first, second]);

    expect(reads, ['background', 'app']);
    expect(storage.maxActive, 1);
    expect([for (final w in storage.writes) w.today], [
      l10n.widgetToday(const Money.rubles(640).formatTotal()),
      l10n.widgetToday(const Money.rubles(955).formatTotal()),
    ]);
    expect(
      logs.linesOf('widget', Level.INFO).last,
      matches(
        RegExp(
          r'widget updated reason=expenses changed state=month .* after '
          r'waiting \d+ms for home widget update \(background task '
          r'sync-periodic\) in \d+ms$',
        ),
      ),
    );
  });
}
