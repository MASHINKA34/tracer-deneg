import 'package:flutter/material.dart';
import 'package:shared/shared.dart' show Mood;

import '../tokens/tokens.g.dart';
import 'app_colors.dart';
import 'app_text.dart';
import 'mood_colors.dart';

/// Тема приложения: Material 3, но все цвета — наши (00-spec §6.2).
///
/// `AppTheme.build(brightness, mood)` собирает `ThemeData` с расширениями
/// [AppColors] и [MoodColors]. Смена темы или настроения в `MaterialApp`
/// плавная: `ThemeData.lerp` за [AppTheme.transition] интерполирует и
/// расширения.
abstract final class AppTheme {
  /// Длительность плавной смены темы и настроения.
  static const Duration transition = Duration(milliseconds: 200);

  /// Тень цвета `#1E1A15` — у теней токенов тот же цвет.
  static const Color _shadow = Color(0xFF1E1A15);

  static ThemeData build(Brightness brightness, Mood mood) {
    final colors = AppColors.forBrightness(brightness);
    final moodColors = MoodColors.forMood(mood, brightness);
    final n = colors.neutral;
    final m = moodColors.tokens;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: m.accent,
      onPrimary: m.onAccent,
      primaryContainer: m.soft,
      onPrimaryContainer: m.onSoft,
      secondary: m.accentStrong,
      onSecondary: m.onAccent,
      secondaryContainer: m.soft,
      onSecondaryContainer: m.onSoft,
      tertiary: m.accentStrong,
      onTertiary: m.onAccent,
      error: n.statusDanger,
      onError: n.textInverse,
      surface: n.bgSurface,
      onSurface: n.textPrimary,
      onSurfaceVariant: n.textSecondary,
      surfaceDim: n.bgSurface2,
      surfaceBright: n.bgSurface,
      surfaceContainerLowest: n.bgSurface,
      surfaceContainerLow: n.bgSurface,
      surfaceContainer: n.bgSurface2,
      surfaceContainerHigh: n.bgSurface2,
      surfaceContainerHighest: n.bgSurface3,
      outline: n.borderStrong,
      outlineVariant: n.borderDefault,
      shadow: _shadow,
      scrim: n.scrim,
      inverseSurface: n.textPrimary,
      onInverseSurface: n.textInverse,
      inversePrimary: m.soft,
      surfaceTint: Colors.transparent,
    );

    TextStyle text(TextStyle style, Color color) =>
        style.copyWith(color: color);
    final textTheme = TextTheme(
      displayLarge: text(AppText.displayXl, n.textPrimary),
      displayMedium: text(AppText.displayL, n.textPrimary),
      displaySmall: text(AppText.displayM, n.textPrimary),
      headlineLarge: text(AppText.displayM, n.textPrimary),
      headlineMedium: text(AppText.displayS, n.textPrimary),
      headlineSmall: text(AppText.titleL, n.textPrimary),
      titleLarge: text(AppText.titleL, n.textPrimary),
      titleMedium: text(AppText.titleM, n.textPrimary),
      titleSmall: text(AppText.titleS, n.textPrimary),
      bodyLarge: text(AppText.bodyL, n.textPrimary),
      bodyMedium: text(AppText.bodyM, n.textPrimary),
      bodySmall: text(AppText.bodyS, n.textSecondary),
      labelLarge: text(AppText.labelL, n.textPrimary),
      labelMedium: text(AppText.labelM, n.textPrimary),
      labelSmall: text(AppText.labelS, n.textSecondary),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: TextStyleTokens.bodyM.family,
      textTheme: textTheme,
      scaffoldBackgroundColor: n.bgApp,
      canvasColor: n.bgSurface,
      cardColor: n.bgSurface,
      dividerColor: n.borderDefault,
      disabledColor: n.textDisabled,
      hintColor: n.textTertiary,
      shadowColor: _shadow,
      // Рябь и нажатие — в цвет настроения.
      splashFactory: InkRipple.splashFactory,
      splashColor: m.accent.withValues(alpha: 0.12),
      highlightColor: m.accent.withValues(alpha: 0.08),
      focusColor: m.accent.withValues(alpha: 0.12),
      hoverColor: m.accent.withValues(alpha: 0.04),
      iconTheme: IconThemeData(color: n.textPrimary, size: 24),
      dividerTheme: DividerThemeData(
        color: n.borderDefault,
        thickness: 1,
        space: 1,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: m.accent,
        selectionColor: m.accent.withValues(alpha: 0.3),
        selectionHandleColor: m.accent,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: m.accent,
        linearTrackColor: n.bgSurface3,
        circularTrackColor: n.bgSurface3,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(n.borderStrong),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: n.bgSurface,
        modalBackgroundColor: n.bgSurface,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: n.scrim,
        dragHandleColor: n.borderStrong,
        dragHandleSize: const Size(36, 4),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(RadiusTokens.xl),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: n.bgSurface,
        surfaceTintColor: Colors.transparent,
        barrierColor: n.scrim,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(RadiusTokens.xl)),
        ),
        titleTextStyle: text(AppText.titleM, n.textPrimary),
        contentTextStyle: text(AppText.bodyM, n.textSecondary),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: n.textPrimary,
        contentTextStyle: text(AppText.bodyM, n.textInverse),
        actionTextColor: m.soft,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(RadiusTokens.md)),
        ),
      ),
      extensions: [colors, moodColors],
    );
  }
}

/// Короткий доступ к цветам темы.
extension AppThemeContext on BuildContext {
  /// Нейтральные цвета и категории.
  AppColors get colors => AppColors.of(this);

  /// Палитра настроения.
  MoodColors get mood => MoodColors.of(this);
}
