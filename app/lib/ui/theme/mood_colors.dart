import 'package:flutter/material.dart';
import 'package:shared/shared.dart' show Mood;

import '../tokens/tokens.g.dart';

/// Палитра «настроения» (сезон или праздник) в текущей теме (00-spec §6.2).
///
/// - [accent] — заливки: кнопки Primary, «+», «сегодня», выбранные чип,
///   радио, чекбокс, столбики, каретка; поверх — [onAccent].
/// - [accentStrong] — акцент как цвет текста, иконок и обводок на фоне
///   `bg/*` или [soft]: итог месяца, «сб/вс», ссылки, кнопки Text, рамка
///   активного поля. Отличается от [accent] только у 1 сентября.
/// - [soft] — фон карточки месяца и мягких плашек, текст на нём — [onSoft].
/// - [heat1]…[heat3] — подсветка дней (уже с альфой).
/// - [decor1]…[decor4] — узор по краям карточки месяца.
@immutable
final class MoodColors extends ThemeExtension<MoodColors> {
  const MoodColors({
    required this.mood,
    required this.brightness,
    required this.tokens,
  });

  /// Палитра [mood] в теме [brightness] из токенов.
  factory MoodColors.forMood(Mood mood, Brightness brightness) => MoodColors(
    mood: mood,
    brightness: brightness,
    tokens: (brightness == Brightness.light ? moodLight : moodDark)[mood]!,
  );

  /// Какое настроение (для декора и логов). При плавной смене — то,
  /// к которому ближе текущий кадр.
  final Mood mood;
  final Brightness brightness;
  final MoodTokens tokens;

  Color get accent => tokens.accent;
  Color get accentStrong => tokens.accentStrong;
  Color get onAccent => tokens.onAccent;
  Color get soft => tokens.soft;
  Color get onSoft => tokens.onSoft;
  Color get heat1 => tokens.heat1;
  Color get heat2 => tokens.heat2;
  Color get heat3 => tokens.heat3;
  Color get decor1 => tokens.decor1;
  Color get decor2 => tokens.decor2;
  Color get decor3 => tokens.decor3;
  Color get decor4 => tokens.decor4;

  static MoodColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<MoodColors>() ??
        MoodColors.forMood(Mood.autumn, theme.brightness);
  }

  @override
  MoodColors copyWith({
    Mood? mood,
    Brightness? brightness,
    MoodTokens? tokens,
  }) => MoodColors(
    mood: mood ?? this.mood,
    brightness: brightness ?? this.brightness,
    tokens: tokens ?? this.tokens,
  );

  @override
  MoodColors lerp(covariant MoodColors? other, double t) {
    if (other == null || identical(other, this)) return this;
    return MoodColors(
      mood: t < 0.5 ? mood : other.mood,
      brightness: t < 0.5 ? brightness : other.brightness,
      tokens: MoodTokens.lerp(tokens, other.tokens, t),
    );
  }

  @override
  String toString() => 'MoodColors(${mood.name}, ${brightness.name})';
}
