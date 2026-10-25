import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/features/holidays/mood_controller.dart';
import 'package:milionchik/features/widget/home_widget_data.dart';
import 'package:milionchik/features/widget/home_widget_store.dart';
import 'package:milionchik/features/widget/widget_updater.dart';
import 'package:milionchik/l10n/app_localizations.dart';
import 'package:shared/shared.dart';

import '../../data/api/fake_api_adapter.dart' show LogCapture;
import '../../data/sync/sync_triggers_fixture.dart';
import 'widget_update_fixture.dart';

const _second = Duration(seconds: 1);

void main() {
  late AppLocalizations l10n;
  late VirtualTime time;
  late FakeWidgetStorage storage;
  late LogCapture logs;
  late Map<int, Money> totals;
  late int reads;

  setUpAll(() async {
    await initializeDateFormatting('ru');
    l10n = lookupAppLocalizations(const Locale('ru'));
  });

  setUp(() {
    time = VirtualTime();
    storage = FakeWidgetStorage(now: () => time.now);
    logs = LogCapture();
    totals = {19: const Money.rubles(640), 3: const Money.rubles(1500)};
    reads = 0;
  });

  tearDown(() => logs.dispose());

  WidgetUpdater updater() => WidgetUpdater(
    store: HomeWidgetStore(storage),
    clock: () => Clock(now: () => DateTime(2026, 10, 19, 18, 40)),
    signedOutBecause: () => null,
    selectedBudget: () async => 'budget-personal-anya',
    dayTotals: (budgetId, month) async {
      reads++;
      return {...totals};
    },
    mood: () => moodTodayFor(LocalDate(2026, 10, 19), const HolidaySettings()),
    holidaySettings: () => const HolidaySettings(),
    theme: () => ThemeMode.system,
    timer: time.start,
    l10n: l10n,
  );

  test('одна трата: запись ровно через 1 с, не раньше', () async {
    final widget = updater();

    widget.request(WidgetUpdateSource.expenses);
    await time.elapse(const Duration(milliseconds: 999));
    expect(storage.writes, isEmpty);
    expect(reads, 0);

    await time.elapse(const Duration(milliseconds: 1));
    expect([for (final w in storage.writes) w.at], [_second]);
    expect(storage.last.state, 'month');
    expect(storage.last.total, const Money.rubles(2140).formatTotal());
    expect(widgetReasons(logs.records), ['expenses changed']);
    expect(storage.redraws, [homeWidgetAndroidProvider]);
  });

  test('пять трат с паузой 200 мс: одна запись через 1 с после последней',
      () async {
    final widget = updater();

    for (var i = 0; i < 5; i++) {
      widget.request(WidgetUpdateSource.expenses);
      await time.elapse(const Duration(milliseconds: 200));
    }
    expect(storage.writes, isEmpty);
    await time.elapse(const Duration(seconds: 5));

    expect([for (final w in storage.writes) w.at], [
      const Duration(milliseconds: 1800),
    ]);
    expect(reads, 1);
  });

  test('изменения каждые 500 мс без перерыва: запись не позже 3 с от первого '
      'ожидающего, а не через 1 с после последнего', () async {
    final widget = updater();

    for (var i = 0; i < 12; i++) {
      widget.request(
        i.isEven ? WidgetUpdateSource.expenses : WidgetUpdateSource.sync,
      );
      totals = {19: Money.rubles(640 + i)};
      await time.elapse(const Duration(milliseconds: 500));
    }
    await time.elapse(const Duration(seconds: 5));

    expect([for (final w in storage.writes) w.at], [
      const Duration(seconds: 3),
      const Duration(seconds: 6),
    ]);
    expect(widgetReasons(logs.records), [
      'expenses changed+sync done',
      'expenses changed+sync done',
    ]);
  });

  test('данные не изменились - не пишем; смена системной темы - перерисовка '
      'с теми же данными', () async {
    final widget = updater();

    widget.request(WidgetUpdateSource.expenses);
    await time.elapse(_second);
    widget.request(WidgetUpdateSource.budget);
    await time.elapse(_second);
    widget.request(WidgetUpdateSource.mood);
    await time.elapse(_second);

    expect(storage.writes, hasLength(1));
    expect(reads, 3);
    expect(
      logs.linesOf('widget', Level.FINE).where((l) => l.contains('unchanged')),
      hasLength(2),
    );

    widget.request(WidgetUpdateSource.systemTheme);
    await time.elapse(_second);

    expect(storage.writes, hasLength(2));
    expect(storage.writes[1].text, storage.writes[0].text);
    expect(storage.redraws, hasLength(2));
  });

  test('фоновая задача: updateNow пишет сразу и забирает ждущие изменения, '
      'таймер склейки отменён', () async {
    final widget = updater();

    widget.request(WidgetUpdateSource.expenses);
    await time.elapse(const Duration(milliseconds: 300));
    await widget.updateNow('background task sync-periodic');

    expect([for (final w in storage.writes) w.at], [
      const Duration(milliseconds: 300),
    ]);
    expect(widgetReasons(logs.records), [
      'background task sync-periodic+expenses changed',
    ]);
    expect(widget.hasPending, isFalse);

    await time.elapse(const Duration(seconds: 5));
    expect(storage.writes, hasLength(1));
  });

  test('изменение во время записи - ещё одна запись после неё, записи не '
      'идут одновременно', () async {
    final widget = updater();
    final gate = storage.gate = Completer<void>();

    widget.request(WidgetUpdateSource.expenses);
    await time.elapse(_second);
    totals = {19: const Money.rubles(700)};
    widget.request(WidgetUpdateSource.expenses);
    await time.elapse(_second);
    expect(storage.writes, isEmpty);

    storage.gate = null;
    gate.complete();
    await time.elapse(Duration.zero);
    await widget.idle;

    expect(storage.writes, hasLength(2));
    expect(storage.maxActive, 1);
    expect(storage.last.total, const Money.rubles(700).formatTotal());
  });

  test('после dispose запросы не пишут', () async {
    final widget = updater();

    widget.request(WidgetUpdateSource.expenses);
    widget.dispose('test');
    widget.request(WidgetUpdateSource.theme);
    await time.elapse(const Duration(seconds: 5));

    expect(storage.writes, isEmpty);
    expect(time.active, isEmpty);
  });
}
