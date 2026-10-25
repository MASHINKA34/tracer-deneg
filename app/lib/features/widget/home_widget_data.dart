import 'dart:convert';

import 'package:flutter/material.dart' show Brightness, Color, ThemeMode;
import 'package:shared/shared.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/tokens/tokens.g.dart';
import '../month/day_sheet.dart' show spokenAmount;
import '../month/month_picker_sheet.dart' show monthName;

const String homeWidgetDataKey = 'milionchik.widget';

const int homeWidgetDataVersion = 1;

const String homeWidgetAndroidProvider =
    'ru.milionchik.app.widget.MonthWidgetProvider';

enum HomeWidgetState { month, signedOut }

String homeWidgetColor(Color color) =>
    '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

final class HomeWidgetPalette {
  const HomeWidgetPalette({
    required this.bgSurface,
    required this.textPrimary,
    required this.textSecondary,
    required this.onSoft,
    required this.accent,
    required this.onAccent,
  });

  factory HomeWidgetPalette.of(Mood mood, Brightness brightness) {
    final light = brightness == Brightness.light;
    final neutral = light ? neutralLight : neutralDark;
    final colors = (light ? moodLight : moodDark)[mood]!;
    return HomeWidgetPalette(
      bgSurface: neutral.bgSurface,
      textPrimary: neutral.textPrimary,
      textSecondary: neutral.textSecondary,
      onSoft: colors.onSoft,
      accent: colors.accent,
      onAccent: colors.onAccent,
    );
  }

  final Color bgSurface;
  final Color textPrimary;
  final Color textSecondary;
  final Color onSoft;
  final Color accent;
  final Color onAccent;

  Map<String, String> toJson() => {
    'bgSurface': homeWidgetColor(bgSurface),
    'textPrimary': homeWidgetColor(textPrimary),
    'textSecondary': homeWidgetColor(textSecondary),
    'onSoft': homeWidgetColor(onSoft),
    'accent': homeWidgetColor(accent),
    'onAccent': homeWidgetColor(onAccent),
  };
}

sealed class HomeWidgetData {
  const HomeWidgetData({required this.mood, required this.theme});

  factory HomeWidgetData.month({
    required AppLocalizations l10n,
    required Mood mood,
    required ThemeMode theme,
    required String emoji,
    required YearMonth month,
    required Money total,
    required Money today,
  }) {
    final name = _capitalized(monthName(month));
    final totalText = total.formatTotal();
    final todayText = today.formatTotal();
    return HomeWidgetMonthData._(
      mood: mood,
      theme: theme,
      emoji: emoji,
      month: name,
      total: totalText,
      today: l10n.widgetToday(todayText),
      label: l10n.widgetLabel(
        name,
        spokenAmount(l10n, Money.rubles(total.roundedRubles)),
        spokenAmount(l10n, Money.rubles(today.roundedRubles)),
      ),
      addLabel: l10n.a11yAddExpense,
    );
  }

  const factory HomeWidgetData.signedOut({
    required Mood mood,
    required ThemeMode theme,
  }) = HomeWidgetSignedOutData;

  final Mood mood;
  final ThemeMode theme;

  HomeWidgetState get state;

  HomeWidgetPalette get light => HomeWidgetPalette.of(mood, Brightness.light);

  HomeWidgetPalette get dark => HomeWidgetPalette.of(mood, Brightness.dark);

  Map<String, Object> toJson() => {
    'v': homeWidgetDataVersion,
    'state': state.name,
    'theme': theme.name,
    'mood': mood.name,
    'colors': {'light': light.toJson(), 'dark': dark.toJson()},
    ..._content(),
  };

  Map<String, Object> _content();

  String encode() => jsonEncode(toJson());

  String describe() =>
      'state=${state.name} theme=${theme.name} mood=${mood.name}';
}

final class HomeWidgetMonthData extends HomeWidgetData {
  const HomeWidgetMonthData._({
    required super.mood,
    required super.theme,
    required this.emoji,
    required this.month,
    required this.total,
    required this.today,
    required this.label,
    required this.addLabel,
  });

  final String emoji;
  final String month;
  final String total;
  final String today;
  final String label;
  final String addLabel;

  @override
  HomeWidgetState get state => HomeWidgetState.month;

  @override
  Map<String, Object> _content() => {
    'emoji': emoji,
    'month': month,
    'total': total,
    'today': today,
    'label': label,
    'addLabel': addLabel,
  };
}

final class HomeWidgetSignedOutData extends HomeWidgetData {
  const HomeWidgetSignedOutData({required super.mood, required super.theme});

  @override
  HomeWidgetState get state => HomeWidgetState.signedOut;

  @override
  Map<String, Object> _content() => const {};
}

String _capitalized(String text) =>
    text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';
