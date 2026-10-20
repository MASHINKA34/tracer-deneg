import 'package:flutter/material.dart';
import 'package:shared/shared.dart' show CategoryColor;

import '../tokens/tokens.g.dart';

/// Нейтральные цвета и цвета категорий текущей темы (00-spec §6.2).
/// Берутся из темы: `AppColors.of(context)` или `context.colors`.
@immutable
final class AppColors extends ThemeExtension<AppColors> {
  const AppColors({required this.neutral, required this.categories});

  /// Палитра светлой или тёмной темы из токенов.
  factory AppColors.forBrightness(Brightness brightness) =>
      brightness == Brightness.light
      ? const AppColors(neutral: neutralLight, categories: categoryLight)
      : const AppColors(neutral: neutralDark, categories: categoryDark);

  final NeutralTokens neutral;
  final Map<CategoryColor, CategoryTokens> categories;

  Color get bgApp => neutral.bgApp;
  Color get bgSurface => neutral.bgSurface;
  Color get bgSurface2 => neutral.bgSurface2;
  Color get bgSurface3 => neutral.bgSurface3;
  Color get borderDefault => neutral.borderDefault;
  Color get borderStrong => neutral.borderStrong;
  Color get textPrimary => neutral.textPrimary;
  Color get textSecondary => neutral.textSecondary;
  Color get textTertiary => neutral.textTertiary;
  Color get textDisabled => neutral.textDisabled;
  Color get textInverse => neutral.textInverse;
  Color get statusSuccess => neutral.statusSuccess;
  Color get statusDanger => neutral.statusDanger;
  Color get scrim => neutral.scrim;

  /// Цвет категории; `null` — системная «Другое» без цвета.
  CategoryTokens? category(CategoryColor? color) =>
      color == null ? null : categories[color];

  /// Подложка под эмодзи категории: `soft` цвета или `bg/surface-3`
  /// у «Другое» (00-spec §7.4).
  Color categorySoft(CategoryColor? color) =>
      category(color)?.soft ?? neutral.bgSurface3;

  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>() ??
      AppColors.forBrightness(Theme.of(context).brightness);

  @override
  AppColors copyWith({
    NeutralTokens? neutral,
    Map<CategoryColor, CategoryTokens>? categories,
  }) => AppColors(
    neutral: neutral ?? this.neutral,
    categories: categories ?? this.categories,
  );

  @override
  AppColors lerp(covariant AppColors? other, double t) {
    if (other == null || identical(other, this)) return this;
    return AppColors(
      neutral: NeutralTokens.lerp(neutral, other.neutral, t),
      categories: {
        for (final c in CategoryColor.values)
          c: CategoryTokens.lerp(categories[c]!, other.categories[c]!, t),
      },
    );
  }
}
