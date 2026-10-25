import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart' show Brightness, ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milionchik/features/widget/home_widget_data.dart';
import 'package:milionchik/l10n/app_localizations.dart';
import 'package:milionchik/ui/tokens/tokens.g.dart';
import 'package:shared/shared.dart';

const _nbsp = ' ';

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    await initializeDateFormatting('ru');
    l10n = lookupAppLocalizations(const Locale('ru'));
  });

  HomeWidgetData october({
    Mood mood = Mood.autumn,
    ThemeMode theme = ThemeMode.system,
    Money? total,
    Money? today,
  }) => HomeWidgetData.month(
    l10n: l10n,
    mood: mood,
    theme: theme,
    emoji: '🍂',
    month: YearMonth(2026, 10),
    total: total ?? Money.rubles(18300),
    today: today ?? Money.rubles(1100),
  );

  test('месяц как в макете 46:5638/46:5651: тексты, цвета обеих тем и '
      'версия формата', () {
    expect(october().toJson(), {
      'v': 1,
      'state': 'month',
      'theme': 'system',
      'mood': 'autumn',
      'colors': {
        'light': {
          'bgSurface': '#FFFFFFFF',
          'textPrimary': '#FF1E1A15',
          'textSecondary': '#FF6B6257',
          'onSoft': '#FF8A3A10',
          'accent': '#FFC2541C',
          'onAccent': '#FFFFFFFF',
        },
        'dark': {
          'bgSurface': '#FF1E1B17',
          'textPrimary': '#FFF4EFE7',
          'textSecondary': '#FFB5AC9F',
          'onSoft': '#FFF6B48A',
          'accent': '#FFF0884A',
          'onAccent': '#FF1F130A',
        },
      },
      'emoji': '🍂',
      'month': 'Октябрь',
      'total': '18${_nbsp}300$_nbsp₽',
      'today': 'Сегодня · 1${_nbsp}100$_nbsp₽',
      'label':
          'Октябрь: за месяц 18${_nbsp}300 рублей, сегодня 1${_nbsp}100 рублей',
      'addLabel': 'Добавить трату',
    });
  });

  test('итоги округлены до рубля, подпись TalkBack - теми же рублями, '
      'ноль сегодня - «0 ₽»', () {
    final data = october(total: Money(1830050), today: Money.zero).toJson();

    expect(data['total'], '18${_nbsp}301$_nbsp₽');
    expect(data['today'], 'Сегодня · 0$_nbsp₽');
    expect(
      data['label'],
      'Октябрь: за месяц 18${_nbsp}301 рубль, сегодня 0 рублей',
    );
  });

  test('тема приложения уходит как есть: light, dark, system', () {
    for (final mode in ThemeMode.values) {
      expect(october(theme: mode).toJson()['theme'], mode.name);
    }
  });

  test('цвета - из токенов настроения и нейтральных, в каждой теме, для всех '
      '15 настроений', () {
    final hex = RegExp(r'^#[0-9A-F]{8}$');
    for (final mood in Mood.values) {
      final colors = october(mood: mood).toJson()['colors']! as Map;
      for (final (name, brightness) in [
        ('light', Brightness.light),
        ('dark', Brightness.dark),
      ]) {
        final palette = colors[name] as Map<String, String>;
        final neutral = brightness == Brightness.light
            ? neutralLight
            : neutralDark;
        final tokens = (brightness == Brightness.light
            ? moodLight
            : moodDark)[mood]!;
        expect(palette.values, everyElement(matches(hex)), reason: '$mood');
        expect(palette, {
          'bgSurface': homeWidgetColor(neutral.bgSurface),
          'textPrimary': homeWidgetColor(neutral.textPrimary),
          'textSecondary': homeWidgetColor(neutral.textSecondary),
          'onSoft': homeWidgetColor(tokens.onSoft),
          'accent': homeWidgetColor(tokens.accent),
          'onAccent': homeWidgetColor(tokens.onAccent),
        }, reason: '$mood $name');
      }
    }
    final winter = october(mood: Mood.winter).toJson()['colors']! as Map;
    expect((winter['light'] as Map)['accent'], '#FF3567D6');
  });

  test('без входа - только тема, настроение и цвета, без сумм и текстов', () {
    final data = HomeWidgetData.signedOut(
      mood: Mood.halloween,
      theme: ThemeMode.dark,
    );

    expect(data.state, HomeWidgetState.signedOut);
    expect(data.toJson().keys, ['v', 'state', 'theme', 'mood', 'colors']);
    expect(data.toJson()['state'], 'signedOut');
    expect(data.toJson()['mood'], 'halloween');
    expect(data.describe(), 'state=signedOut theme=dark mood=halloween');
  });

  test('encode - JSON той же карты; describe для логов без сумм и текстов', () {
    final data = october(total: Money.rubles(987654));

    expect(jsonDecode(data.encode()), data.toJson());
    expect(data.describe(), 'state=month theme=system mood=autumn');
    expect(data.describe(), isNot(contains('987')));
  });

  test('цвет #AARRGGBB с альфой и ведущими нулями', () {
    expect(homeWidgetColor(const Color(0x0D01020A)), '#0D01020A');
    expect(homeWidgetColor(const Color(0xFFFFFFFF)), '#FFFFFFFF');
  });

  group('договор с нативной частью Android', () {
    final widgetDir = 'android/app/src/main/kotlin/ru/milionchik/app/widget';
    late String reader;
    late String manifest;

    setUpAll(() {
      reader = File('$widgetDir/WidgetData.kt').readAsStringSync();
      manifest = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();
    });

    test('ключ хранилища и версия формата совпадают', () {
      expect(reader, contains('WIDGET_DATA_KEY = "$homeWidgetDataKey"'));
      expect(reader, contains('WIDGET_DATA_VERSION = $homeWidgetDataVersion'));
    });

    test('Kotlin читает каждое поле, которое пишет Dart', () {
      final month = october().toJson();
      final light = (month['colors']! as Map)['light'] as Map<String, String>;
      final keys = {
        ...month.keys.where((k) => k != 'colors'),
        ...light.keys,
      }.difference({'v', 'state', 'theme', 'mood'});
      for (final key in keys) {
        expect(reader, contains('"$key"'), reason: key);
      }
      for (final state in HomeWidgetState.values) {
        expect(reader, contains('"${state.name}"'), reason: state.name);
      }
      for (final mode in ThemeMode.values) {
        expect(reader, contains('"${mode.name}"'), reason: mode.name);
      }
    });

    test('провайдер виджета объявлен в манифесте под тем же именем', () {
      final className = homeWidgetAndroidProvider.split('.').last;
      expect(homeWidgetAndroidProvider, 'ru.milionchik.app.widget.$className');
      expect(manifest, contains('android:name=".widget.$className"'));
      expect(File('$widgetDir/$className.kt').existsSync(), isTrue);
    });
  });
}
