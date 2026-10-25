import 'dart:ui';

import 'package:drift/native.dart' show SqliteException;
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/features/holidays/mood_controller.dart';
import 'package:milionchik/features/widget/home_widget_store.dart';
import 'package:milionchik/features/widget/widget_updater.dart';
import 'package:milionchik/l10n/app_localizations.dart';
import 'package:shared/shared.dart';

import '../../data/api/fake_api_adapter.dart' show LogCapture;
import 'widget_update_fixture.dart';

const _secret = 'budget-param-tango-whiskey-xray';

const _monthAmount = Money(98765432);

const _todayAmount = Money(12345678);

void main() {
  late AppLocalizations l10n;
  late LogCapture logs;
  late FakeWidgetStorage storage;

  setUpAll(() async {
    await initializeDateFormatting('ru');
    l10n = lookupAppLocalizations(const Locale('ru'));
  });

  setUp(() {
    logs = LogCapture();
    storage = FakeWidgetStorage();
  });

  tearDown(() => logs.dispose());

  WidgetUpdater updater({WidgetDayTotals? dayTotals}) => WidgetUpdater(
    store: HomeWidgetStore(storage),
    clock: () => Clock(now: () => DateTime(2026, 10, 19, 18, 40)),
    signedOutBecause: () => null,
    selectedBudget: () async => 'budget-personal-anya',
    dayTotals:
        dayTotals ??
        (budgetId, month) async => {
          3: _monthAmount - _todayAmount,
          19: _todayAmount,
        },
    mood: () => moodTodayFor(LocalDate(2026, 10, 19), const HolidaySettings()),
    holidaySettings: () => const HolidaySettings(),
    theme: () => ThemeMode.dark,
    l10n: l10n,
  );

  List<String> amountsIn(String line) => [
    for (final text in [
      _monthAmount.format(),
      _monthAmount.formatTotal(),
      _todayAmount.format(),
      _todayAmount.formatTotal(),
      '${_monthAmount.kopecks}',
      '${_todayAmount.kopecks}',
      '${_monthAmount.roundedRubles}',
      '${_todayAmount.roundedRubles}',
    ])
      if (line.contains(text)) text,
  ];

  test('info: источник, бюджет, месяц и мс без сумм; суммы - только на debug',
      () async {
    await updater().updateNow('expenses changed');

    final info = [
      for (final r in logs.records)
        if (r.loggerName == 'widget' && r.level >= Level.INFO) r.message,
    ];
    expect(info, hasLength(2));
    expect(
      info.last,
      matches(
        RegExp(
          r'^widget updated reason=expenses changed state=month theme=dark '
          r'mood=autumn budget=budget-personal-anya month=2026-10 '
          r'today=2026-10-19 in \d+ms$',
        ),
      ),
    );
    for (final line in info) {
      expect(amountsIn(line), isEmpty, reason: line);
    }
    final debug = logs
        .linesOf('widget', Level.FINE)
        .where((l) => l.contains('DEBUG') && l.contains('widget data budget='))
        .single;
    expect(debug, contains('total=${_monthAmount.format()}'));
    expect(debug, contains('today=${_todayAmount.format()}'));
  });

  test('ошибка базы: error с типом, текстом и стеком, значения параметров '
      'SQL скрыты, прежние данные виджета остаются', () async {
    final widget = updater(
      dayTotals: (budgetId, month) async => throw SqliteException(
        extendedResultCode: 11,
        message: 'database disk image is malformed',
        causingStatement:
            'SELECT spent_on, SUM(amount_kopecks) FROM expenses WHERE '
            'budget_id = ?',
        parametersToStatement: [_secret],
      ),
    );

    await expectLater(
      widget.updateNow('background task sync-periodic'),
      throwsA(isA<SqliteException>()),
    );

    final error = logs.linesOf('widget', Level.SEVERE).single;
    expect(
      error,
      contains(
        'ERROR [widget] widget update reason=background task sync-periodic '
        'failed while reading its data after ',
      ),
    );
    expect(error, contains('the widget keeps its previous data'));
    expect(error, contains('database disk image is malformed'));
    expect(error, contains('stack:'));
    expect(logs.text, isNot(contains(_secret)));
    expect(storage.writes, isEmpty);
  });

  test('плагина виджета нет на платформе: одно предупреждение, дальше без '
      'попыток записи', () async {
    final widget = updater();
    storage.saveError = MissingPluginException(
      'No implementation found for method saveWidgetData on channel '
      'home_widget',
    );

    await expectLater(
      widget.updateNow('startup'),
      throwsA(isA<MissingPluginException>()),
    );
    storage.saveError = null;
    await widget.updateNow('expenses changed');

    expect(storage.writes, isEmpty);
    expect(
      [
        for (final r in logs.records)
          if (r.loggerName == 'widget' && r.level == Level.WARNING) r.message,
      ],
      [
        contains(
          'home widget plugin is not available on this platform '
          '(MissingPluginException',
        ),
      ],
    );
    expect(
      logs.linesOf('widget', Level.FINE).last,
      contains('widget update reason=expenses changed skipped'),
    );
  });
}
