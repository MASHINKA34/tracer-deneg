import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/features/widget/home_widget_data.dart';
import 'package:milionchik/features/widget/home_widget_store.dart';
import 'package:milionchik/l10n/app_localizations.dart';
import 'package:shared/shared.dart';

import '../../data/api/fake_api_adapter.dart' show LogCapture;

final class _FakeStorage implements HomeWidgetStorage {
  final List<String> calls = [];
  final Map<String, String> saved = {};
  Object? saveError;
  bool? saveResult = true;
  Object? redrawError;

  @override
  Future<bool?> save(String key, String value) async {
    calls.add('save $key');
    final error = saveError;
    if (error != null) throw error;
    if (saveResult == true) saved[key] = value;
    return saveResult;
  }

  @override
  Future<bool?> redraw(String qualifiedAndroidName) async {
    calls.add('redraw $qualifiedAndroidName');
    final error = redrawError;
    if (error != null) throw error;
    return true;
  }
}

void main() {
  late AppLocalizations l10n;
  late LogCapture logs;
  late _FakeStorage storage;

  setUpAll(() async {
    await initializeDateFormatting('ru');
    l10n = lookupAppLocalizations(const Locale('ru'));
  });

  setUp(() {
    logs = LogCapture();
    storage = _FakeStorage();
  });

  tearDown(() => logs.dispose());

  HomeWidgetData month() => HomeWidgetData.month(
    l10n: l10n,
    mood: Mood.autumn,
    theme: ThemeMode.dark,
    emoji: '🍂',
    month: YearMonth(2026, 10),
    total: Money.rubles(987654),
    today: Money.rubles(876543),
  );

  List<String> widgetLines(Level level) => [
    for (final r in logs.records)
      if (r.loggerName == 'widget' && r.level == level) r.message,
  ];

  test(
    'пишет JSON одним ключом и потом просит перерисовать провайдер',
    () async {
      final data = month();

      await HomeWidgetStore(storage).show(data, reason: 'expense saved');

      expect(storage.calls, [
        'save $homeWidgetDataKey',
        'redraw $homeWidgetAndroidProvider',
      ]);
      expect(jsonDecode(storage.saved[homeWidgetDataKey]!), data.toJson());
    },
  );

  test('info - причина, состояние, тема, настроение и размер без сумм; '
      'суммы - только на debug', () async {
    await HomeWidgetStore(storage).show(month(), reason: 'expense saved');

    final info = widgetLines(Level.INFO);
    expect(info, hasLength(1));
    expect(
      info.single,
      matches(
        RegExp(
          r'^home widget data saved reason=expense saved state=month '
          r'theme=dark mood=autumn bytes=\d+ in \d+ms → redraw requested$',
        ),
      ),
    );
    final text = logs.records
        .where((r) => r.level >= Level.INFO)
        .map((r) => r.message)
        .join('\n');
    expect(text, isNot(contains('987')));
    expect(text, isNot(contains('876')));
    expect(widgetLines(Level.FINE).single, contains('987'));
  });

  test('хранилище упало - severe с ключом и причиной, ошибка выше, '
      'перерисовку не просим', () async {
    storage.saveError = PlatformException(code: '-10', message: 'disk full');

    await expectLater(
      HomeWidgetStore(storage).show(month(), reason: 'sync'),
      throwsA(isA<PlatformException>()),
    );

    expect(storage.calls, ['save $homeWidgetDataKey']);
    final severe = logs.records.singleWhere((r) => r.level == Level.SEVERE);
    expect(severe.message, contains('home widget data not saved reason=sync'));
    expect(severe.message, contains('key=$homeWidgetDataKey'));
    expect(severe.message, contains('disk full'));
    expect(severe.stackTrace, isNotNull);
    expect(severe.message, isNot(contains('987')));
  });

  test(
    'commit вернул false - HomeWidgetDataNotSaved, перерисовку не просим',
    () async {
      storage.saveResult = false;

      await expectLater(
        HomeWidgetStore(storage).show(month(), reason: 'sync'),
        throwsA(isA<HomeWidgetDataNotSaved>()),
      );

      expect(storage.calls, ['save $homeWidgetDataKey']);
      expect(
        logs.records.singleWhere((r) => r.level == Level.SEVERE).message,
        contains('saved=false → the widget keeps the previous data'),
      );
    },
  );

  test('перерисовка упала - данные уже записаны, severe с провайдером, '
      'ошибка выше', () async {
    storage.redrawError = PlatformException(code: '-3', message: 'no class');

    await expectLater(
      HomeWidgetStore(storage).show(month(), reason: 'midnight'),
      throwsA(isA<PlatformException>()),
    );

    expect(storage.saved, contains(homeWidgetDataKey));
    final severe = logs.records.singleWhere((r) => r.level == Level.SEVERE);
    expect(severe.message, contains('redraw request failed reason=midnight'));
    expect(severe.message, contains('provider=$homeWidgetAndroidProvider'));
    expect(severe.message, contains('no class'));
    expect(widgetLines(Level.INFO), isEmpty);
  });
}
