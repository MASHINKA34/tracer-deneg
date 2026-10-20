import 'package:flutter/painting.dart';

import '../tokens/tokens.g.dart';

/// 19 текстовых стилей из Figma (`textStyles` в токенах, 00-spec §6.2).
///
/// Цвет не задан — его ставит компонент. Межстрочный интервал — как в
/// токенах (`height = lineHeight / size`), строка распределяется поровну
/// сверху и снизу, как в Figma. Трекинг — в процентах кегля.
/// `displayMonth` пишется прописными: см. [TextStyleToken.uppercase].
/// Цифры — пропорциональные, как в макетах Figma (решение пользователя на
/// этапе 03). Моноширинные (`tnum`, оба шрифта его поддерживают — проверено
/// по таблицам GSUB) — через `.tabular` там, где сумма меняется на глазах
/// (ввод суммы).
abstract final class AppText {
  static final TextStyle displayXl = fromToken(TextStyleTokens.displayXl);
  static final TextStyle displayL = fromToken(TextStyleTokens.displayL);
  static final TextStyle displayM = fromToken(TextStyleTokens.displayM);
  static final TextStyle displayS = fromToken(TextStyleTokens.displayS);
  static final TextStyle displayMonth = fromToken(TextStyleTokens.displayMonth);
  static final TextStyle titleL = fromToken(TextStyleTokens.titleL);
  static final TextStyle titleM = fromToken(TextStyleTokens.titleM);
  static final TextStyle titleS = fromToken(TextStyleTokens.titleS);
  static final TextStyle bodyL = fromToken(TextStyleTokens.bodyL);
  static final TextStyle bodyM = fromToken(TextStyleTokens.bodyM);
  static final TextStyle bodyS = fromToken(TextStyleTokens.bodyS);
  static final TextStyle labelL = fromToken(TextStyleTokens.labelL);
  static final TextStyle labelM = fromToken(TextStyleTokens.labelM);
  static final TextStyle labelS = fromToken(TextStyleTokens.labelS);
  static final TextStyle caption = fromToken(TextStyleTokens.caption);
  static final TextStyle micro = fromToken(TextStyleTokens.micro);
  static final TextStyle numericM = fromToken(TextStyleTokens.numericM);
  static final TextStyle cellDay = fromToken(TextStyleTokens.cellDay);
  static final TextStyle cellAmount = fromToken(TextStyleTokens.cellAmount);

  /// `TextStyle` из токена Figma.
  static TextStyle fromToken(TextStyleToken token) => TextStyle(
    fontFamily: token.family,
    fontWeight: FontWeight.values.firstWhere(
      (w) => w.value == token.weight,
      orElse: () => FontWeight.normal,
    ),
    fontSize: token.size,
    height: token.lineHeight / token.size,
    letterSpacing: token.size * token.letterSpacingPct / 100,
    leadingDistribution: TextLeadingDistribution.even,
  );
}

/// Моноширинные цифры (`tnum`) — для сумм, которые меняются на глазах.
extension TabularFigures on TextStyle {
  TextStyle get tabular =>
      copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
}
