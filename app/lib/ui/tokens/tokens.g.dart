// GENERATED CODE - DO NOT MODIFY BY HAND.
// Источник: tool/design-tokens.json (переменные Figma kaggd9sqW9jdeRA6MOMZ80).
// Перегенерировать из папки app: dart run tool/gen_tokens.dart

import 'package:flutter/painting.dart';
import 'package:shared/shared.dart' show CategoryColor, Mood;

/// Нейтральные цвета одной темы (`neutral/*`).
final class NeutralTokens {
  const NeutralTokens({
    required this.bgApp,
    required this.bgSurface,
    required this.bgSurface2,
    required this.bgSurface3,
    required this.borderDefault,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textDisabled,
    required this.textInverse,
    required this.statusSuccess,
    required this.statusDanger,
    required this.scrim,
  });

  /// `bg/app`
  final Color bgApp;

  /// `bg/surface`
  final Color bgSurface;

  /// `bg/surface-2`
  final Color bgSurface2;

  /// `bg/surface-3`
  final Color bgSurface3;

  /// `border/default`
  final Color borderDefault;

  /// `border/strong`
  final Color borderStrong;

  /// `text/primary`
  final Color textPrimary;

  /// `text/secondary`
  final Color textSecondary;

  /// `text/tertiary`
  final Color textTertiary;

  /// `text/disabled`
  final Color textDisabled;

  /// `text/inverse`
  final Color textInverse;

  /// `status/success`
  final Color statusSuccess;

  /// `status/danger`
  final Color statusDanger;

  /// `scrim`
  final Color scrim;

  /// Плавный переход между палитрами (смена темы и настроения).
  static NeutralTokens lerp(NeutralTokens a, NeutralTokens b, double t) =>
      NeutralTokens(
        bgApp: Color.lerp(a.bgApp, b.bgApp, t)!,
        bgSurface: Color.lerp(a.bgSurface, b.bgSurface, t)!,
        bgSurface2: Color.lerp(a.bgSurface2, b.bgSurface2, t)!,
        bgSurface3: Color.lerp(a.bgSurface3, b.bgSurface3, t)!,
        borderDefault: Color.lerp(a.borderDefault, b.borderDefault, t)!,
        borderStrong: Color.lerp(a.borderStrong, b.borderStrong, t)!,
        textPrimary: Color.lerp(a.textPrimary, b.textPrimary, t)!,
        textSecondary: Color.lerp(a.textSecondary, b.textSecondary, t)!,
        textTertiary: Color.lerp(a.textTertiary, b.textTertiary, t)!,
        textDisabled: Color.lerp(a.textDisabled, b.textDisabled, t)!,
        textInverse: Color.lerp(a.textInverse, b.textInverse, t)!,
        statusSuccess: Color.lerp(a.statusSuccess, b.statusSuccess, t)!,
        statusDanger: Color.lerp(a.statusDanger, b.statusDanger, t)!,
        scrim: Color.lerp(a.scrim, b.scrim, t)!,
      );
}

/// `neutral/*`, светлая тема.
const neutralLight = NeutralTokens(
  bgApp: Color(0xFFF6F2EB),
  bgSurface: Color(0xFFFFFFFF),
  bgSurface2: Color(0xFFF0EAE1),
  bgSurface3: Color(0xFFE7DFD3),
  borderDefault: Color(0xFFE9E2D7),
  borderStrong: Color(0xFFD2C7B7),
  textPrimary: Color(0xFF1E1A15),
  textSecondary: Color(0xFF6B6257),
  textTertiary: Color(0xFFA0968A),
  textDisabled: Color(0xFFC4BBAE),
  textInverse: Color(0xFFFFFFFF),
  statusSuccess: Color(0xFF2E8B57),
  statusDanger: Color(0xFFD0453A),
  scrim: Color(0x731E1A15),
);

/// `neutral/*`, тёмная тема.
const neutralDark = NeutralTokens(
  bgApp: Color(0xFF14120F),
  bgSurface: Color(0xFF1E1B17),
  bgSurface2: Color(0xFF29251F),
  bgSurface3: Color(0xFF343029),
  borderDefault: Color(0xFF322D26),
  borderStrong: Color(0xFF4A443B),
  textPrimary: Color(0xFFF4EFE7),
  textSecondary: Color(0xFFB5AC9F),
  textTertiary: Color(0xFF7F776B),
  textDisabled: Color(0xFF5A534A),
  textInverse: Color(0xFF1E1A15),
  statusSuccess: Color(0xFF5CC48A),
  statusDanger: Color(0xFFF07167),
  scrim: Color(0x9E000000),
);

/// Цвет категории: `solid` — столбики и диаграммы, `soft` — подложка под эмодзи (уже с альфой).
final class CategoryTokens {
  const CategoryTokens({required this.solid, required this.soft});

  /// `solid`
  final Color solid;

  /// `soft`
  final Color soft;

  /// Плавный переход между палитрами (смена темы и настроения).
  static CategoryTokens lerp(CategoryTokens a, CategoryTokens b, double t) =>
      CategoryTokens(
        solid: Color.lerp(a.solid, b.solid, t)!,
        soft: Color.lerp(a.soft, b.soft, t)!,
      );
}

/// `category/*`, светлая тема.
const Map<CategoryColor, CategoryTokens> categoryLight = {
  CategoryColor.green: CategoryTokens(
    solid: Color(0xFF3BA55C),
    soft: Color(0x2E3BA55C),
  ),
  CategoryColor.orange: CategoryTokens(
    solid: Color(0xFFF08C2E),
    soft: Color(0x2EF08C2E),
  ),
  CategoryColor.yellow: CategoryTokens(
    solid: Color(0xFFE3B321),
    soft: Color(0x2EE3B321),
  ),
  CategoryColor.blue: CategoryTokens(
    solid: Color(0xFF3D7FE0),
    soft: Color(0x2E3D7FE0),
  ),
  CategoryColor.red: CategoryTokens(
    solid: Color(0xFFE0524A),
    soft: Color(0x2EE0524A),
  ),
  CategoryColor.purple: CategoryTokens(
    solid: Color(0xFF8B5CF6),
    soft: Color(0x2E8B5CF6),
  ),
  CategoryColor.pink: CategoryTokens(
    solid: Color(0xFFE5579A),
    soft: Color(0x2EE5579A),
  ),
  CategoryColor.teal: CategoryTokens(
    solid: Color(0xFF1FA6A0),
    soft: Color(0x2E1FA6A0),
  ),
  CategoryColor.indigo: CategoryTokens(
    solid: Color(0xFF5B63E0),
    soft: Color(0x2E5B63E0),
  ),
  CategoryColor.rose: CategoryTokens(
    solid: Color(0xFFE86A7A),
    soft: Color(0x2EE86A7A),
  ),
};

/// `category/*`, тёмная тема.
const Map<CategoryColor, CategoryTokens> categoryDark = {
  CategoryColor.green: CategoryTokens(
    solid: Color(0xFF5CC47C),
    soft: Color(0x385CC47C),
  ),
  CategoryColor.orange: CategoryTokens(
    solid: Color(0xFFF5A65B),
    soft: Color(0x38F5A65B),
  ),
  CategoryColor.yellow: CategoryTokens(
    solid: Color(0xFFEDC64F),
    soft: Color(0x38EDC64F),
  ),
  CategoryColor.blue: CategoryTokens(
    solid: Color(0xFF6FA0EE),
    soft: Color(0x386FA0EE),
  ),
  CategoryColor.red: CategoryTokens(
    solid: Color(0xFFF07A72),
    soft: Color(0x38F07A72),
  ),
  CategoryColor.purple: CategoryTokens(
    solid: Color(0xFFA88BF8),
    soft: Color(0x38A88BF8),
  ),
  CategoryColor.pink: CategoryTokens(
    solid: Color(0xFFF07FB4),
    soft: Color(0x38F07FB4),
  ),
  CategoryColor.teal: CategoryTokens(
    solid: Color(0xFF4CC4BE),
    soft: Color(0x384CC4BE),
  ),
  CategoryColor.indigo: CategoryTokens(
    solid: Color(0xFF8389EE),
    soft: Color(0x388389EE),
  ),
  CategoryColor.rose: CategoryTokens(
    solid: Color(0xFFF2919D),
    soft: Color(0x38F2919D),
  ),
};

/// Палитра «настроения» (сезон или праздник), одна тема: `accent` — кнопки, «+», сегодня; `soft` — фон карточки месяца; `heat*` — подсветка дней (с альфой); `decor*` — узор по краям карточки.
final class MoodTokens {
  const MoodTokens({
    required this.accent,
    required this.onAccent,
    required this.soft,
    required this.onSoft,
    required this.heat1,
    required this.heat2,
    required this.heat3,
    required this.decor1,
    required this.decor2,
    required this.decor3,
    required this.decor4,
    required this.accentStrong,
  });

  /// `accent`
  final Color accent;

  /// `on-accent`
  final Color onAccent;

  /// `soft`
  final Color soft;

  /// `on-soft`
  final Color onSoft;

  /// `heat-1`
  final Color heat1;

  /// `heat-2`
  final Color heat2;

  /// `heat-3`
  final Color heat3;

  /// `decor-1`
  final Color decor1;

  /// `decor-2`
  final Color decor2;

  /// `decor-3`
  final Color decor3;

  /// `decor-4`
  final Color decor4;

  /// `accent-strong`
  final Color accentStrong;

  /// Плавный переход между палитрами (смена темы и настроения).
  static MoodTokens lerp(MoodTokens a, MoodTokens b, double t) => MoodTokens(
    accent: Color.lerp(a.accent, b.accent, t)!,
    onAccent: Color.lerp(a.onAccent, b.onAccent, t)!,
    soft: Color.lerp(a.soft, b.soft, t)!,
    onSoft: Color.lerp(a.onSoft, b.onSoft, t)!,
    heat1: Color.lerp(a.heat1, b.heat1, t)!,
    heat2: Color.lerp(a.heat2, b.heat2, t)!,
    heat3: Color.lerp(a.heat3, b.heat3, t)!,
    decor1: Color.lerp(a.decor1, b.decor1, t)!,
    decor2: Color.lerp(a.decor2, b.decor2, t)!,
    decor3: Color.lerp(a.decor3, b.decor3, t)!,
    decor4: Color.lerp(a.decor4, b.decor4, t)!,
    accentStrong: Color.lerp(a.accentStrong, b.accentStrong, t)!,
  );
}

/// `mood/*`, светлая тема.
const Map<Mood, MoodTokens> moodLight = {
  Mood.winter: MoodTokens(
    accent: Color(0xFF3567D6),
    onAccent: Color(0xFFFFFFFF),
    soft: Color(0xFFE3EBFB),
    onSoft: Color(0xFF1F4296),
    heat1: Color(0x1A3567D6),
    heat2: Color(0x383567D6),
    heat3: Color(0x613567D6),
    decor1: Color(0xFF8DB4F2),
    decor2: Color(0xFFBCD3F7),
    decor3: Color(0xFF5E8DE6),
    decor4: Color(0xFFBCD3F7),
    accentStrong: Color(0xFF3567D6),
  ),
  Mood.spring: MoodTokens(
    accent: Color(0xFF2A7F51),
    onAccent: Color(0xFFFFFFFF),
    soft: Color(0xFFDEF1E5),
    onSoft: Color(0xFF1B5A38),
    heat1: Color(0x1A2A7F51),
    heat2: Color(0x382A7F51),
    heat3: Color(0x612A7F51),
    decor1: Color(0xFFF2A7C3),
    decor2: Color(0xFF7CC59A),
    decor3: Color(0xFFF6D36B),
    decor4: Color(0xFF7CC59A),
    accentStrong: Color(0xFF2A7F51),
  ),
  Mood.summer: MoodTokens(
    accent: Color(0xFF0B7A7A),
    onAccent: Color(0xFFFFFFFF),
    soft: Color(0xFFD7F0EE),
    onSoft: Color(0xFF075656),
    heat1: Color(0x1A0B7A7A),
    heat2: Color(0x380B7A7A),
    heat3: Color(0x610B7A7A),
    decor1: Color(0xFFF7C948),
    decor2: Color(0xFFF28C6B),
    decor3: Color(0xFF49B9B1),
    decor4: Color(0xFFF28C6B),
    accentStrong: Color(0xFF0B7A7A),
  ),
  Mood.autumn: MoodTokens(
    accent: Color(0xFFC2541C),
    onAccent: Color(0xFFFFFFFF),
    soft: Color(0xFFFBE7D8),
    onSoft: Color(0xFF8A3A10),
    heat1: Color(0x1AC2541C),
    heat2: Color(0x38C2541C),
    heat3: Color(0x61C2541C),
    decor1: Color(0xFFE0782F),
    decor2: Color(0xFFD4A72C),
    decor3: Color(0xFFA63D2A),
    decor4: Color(0xFFD4A72C),
    accentStrong: Color(0xFFC2541C),
  ),
  Mood.newyear: MoodTokens(
    accent: Color(0xFF2F5FB3),
    onAccent: Color(0xFFFFFFFF),
    soft: Color(0xFFE4EDFA),
    onSoft: Color(0xFF1D3F7A),
    heat1: Color(0x1A2F5FB3),
    heat2: Color(0x382F5FB3),
    heat3: Color(0x612F5FB3),
    decor1: Color(0xFF2E7D9A),
    decor2: Color(0xFF8CC0F2),
    decor3: Color(0xFF3B6FD1),
    decor4: Color(0xFFB4C2D8),
    accentStrong: Color(0xFF2F5FB3),
  ),
  Mood.valentine: MoodTokens(
    accent: Color(0xFFC2185B),
    onAccent: Color(0xFFFFFFFF),
    soft: Color(0xFFFCE4EE),
    onSoft: Color(0xFF880E4F),
    heat1: Color(0x1AC2185B),
    heat2: Color(0x38C2185B),
    heat3: Color(0x61C2185B),
    decor1: Color(0xFFE91E63),
    decor2: Color(0xFFFF8FB1),
    decor3: Color(0xFFD32F2F),
    decor4: Color(0xFFFFF3E0),
    accentStrong: Color(0xFFC2185B),
  ),
  Mood.defender: MoodTokens(
    accent: Color(0xFF556B2F),
    onAccent: Color(0xFFFFFFFF),
    soft: Color(0xFFE8EEDD),
    onSoft: Color(0xFF3B4A1F),
    heat1: Color(0x1A556B2F),
    heat2: Color(0x38556B2F),
    heat3: Color(0x61556B2F),
    decor1: Color(0xFF6B8E23),
    decor2: Color(0xFFC0392B),
    decor3: Color(0xFF2F4F8F),
    decor4: Color(0xFFD4A72C),
    accentStrong: Color(0xFF556B2F),
  ),
  Mood.maslenitsa: MoodTokens(
    accent: Color(0xFFA0661A),
    onAccent: Color(0xFFFFFFFF),
    soft: Color(0xFFFBEFD9),
    onSoft: Color(0xFF6E4510),
    heat1: Color(0x1AA0661A),
    heat2: Color(0x38A0661A),
    heat3: Color(0x61A0661A),
    decor1: Color(0xFFD2452F),
    decor2: Color(0xFFC98A2B),
    decor3: Color(0xFF8A5A2B),
    decor4: Color(0xFFF2C14E),
    accentStrong: Color(0xFFA0661A),
  ),
  Mood.women: MoodTokens(
    accent: Color(0xFFC93A52),
    onAccent: Color(0xFFFFFFFF),
    soft: Color(0xFFFCE6EA),
    onSoft: Color(0xFF9A2438),
    heat1: Color(0x1AC93A52),
    heat2: Color(0x38C93A52),
    heat3: Color(0x61C93A52),
    decor1: Color(0xFFE8506F),
    decor2: Color(0xFF5DA65A),
    decor3: Color(0xFFB3355A),
    decor4: Color(0xFFF4D03F),
    accentStrong: Color(0xFFC93A52),
  ),
  Mood.labour: MoodTokens(
    accent: Color(0xFFA0522D),
    onAccent: Color(0xFFFFFFFF),
    soft: Color(0xFFF7E6DA),
    onSoft: Color(0xFF6E3418),
    heat1: Color(0x1AA0522D),
    heat2: Color(0x38A0522D),
    heat3: Color(0x61A0522D),
    decor1: Color(0xFFD9534F),
    decor2: Color(0xFF7C8791),
    decor3: Color(0xFF9C6B3C),
    decor4: Color(0xFFE2B07A),
    accentStrong: Color(0xFFA0522D),
  ),
  Mood.victory: MoodTokens(
    accent: Color(0xFFA61E1E),
    onAccent: Color(0xFFFFFFFF),
    soft: Color(0xFFF9E1DE),
    onSoft: Color(0xFF7A1414),
    heat1: Color(0x1AA61E1E),
    heat2: Color(0x38A61E1E),
    heat3: Color(0x61A61E1E),
    decor1: Color(0xFFC62828),
    decor2: Color(0xFF3E7D3A),
    decor3: Color(0xFFD84315),
    decor4: Color(0xFFE0A82E),
    accentStrong: Color(0xFFA61E1E),
  ),
  Mood.children: MoodTokens(
    accent: Color(0xFF1A70BD),
    onAccent: Color(0xFFFFFFFF),
    soft: Color(0xFFE0EFFC),
    onSoft: Color(0xFF135A9A),
    heat1: Color(0x1A1A70BD),
    heat2: Color(0x381A70BD),
    heat3: Color(0x611A70BD),
    decor1: Color(0xFFEF5350),
    decor2: Color(0xFF43A047),
    decor3: Color(0xFF8E5CD9),
    decor4: Color(0xFFFBC02D),
    accentStrong: Color(0xFF1A70BD),
  ),
  Mood.knowledge: MoodTokens(
    accent: Color(0xFFF2B83A),
    onAccent: Color(0xFF3A2A05),
    soft: Color(0xFFFFF4D9),
    onSoft: Color(0xFF7A5205),
    heat1: Color(0x29F2B83A),
    heat2: Color(0x52F2B83A),
    heat3: Color(0x8CF2B83A),
    decor1: Color(0xFFEE8A3C),
    decor2: Color(0xFFE2A82B),
    decor3: Color(0xFFD08A52),
    decor4: Color(0xFFF0C04A),
    accentStrong: Color(0xFF8C5A06),
  ),
  Mood.halloween: MoodTokens(
    accent: Color(0xFF6B35A3),
    onAccent: Color(0xFFFFFFFF),
    soft: Color(0xFFF1E6FA),
    onSoft: Color(0xFF4A1F78),
    heat1: Color(0x1A6B35A3),
    heat2: Color(0x386B35A3),
    heat3: Color(0x616B35A3),
    decor1: Color(0xFFF08A24),
    decor2: Color(0xFF5A9A3A),
    decor3: Color(0xFF9B4FD0),
    decor4: Color(0xFFFFFFFF),
    accentStrong: Color(0xFF6B35A3),
  ),
  Mood.birthday: MoodTokens(
    accent: Color(0xFF7E3FD4),
    onAccent: Color(0xFFFFFFFF),
    soft: Color(0xFFEFE6FC),
    onSoft: Color(0xFF5524A0),
    heat1: Color(0x1A7E3FD4),
    heat2: Color(0x387E3FD4),
    heat3: Color(0x617E3FD4),
    decor1: Color(0xFFF06292),
    decor2: Color(0xFF26A69A),
    decor3: Color(0xFF7E57C2),
    decor4: Color(0xFFFBC02D),
    accentStrong: Color(0xFF7E3FD4),
  ),
};

/// `mood/*`, тёмная тема.
const Map<Mood, MoodTokens> moodDark = {
  Mood.winter: MoodTokens(
    accent: Color(0xFF86A9F7),
    onAccent: Color(0xFF0D1830),
    soft: Color(0xFF1C2A44),
    onSoft: Color(0xFFAFC7FA),
    heat1: Color(0x2986A9F7),
    heat2: Color(0x4786A9F7),
    heat3: Color(0x7086A9F7),
    decor1: Color(0xFF6F96DA),
    decor2: Color(0xFFA9C3EE),
    decor3: Color(0xFF4E79C9),
    decor4: Color(0xFFA9C3EE),
    accentStrong: Color(0xFF86A9F7),
  ),
  Mood.spring: MoodTokens(
    accent: Color(0xFF6FC895),
    onAccent: Color(0xFF0C2416),
    soft: Color(0xFF1A3325),
    onSoft: Color(0xFF9EDCB7),
    heat1: Color(0x296FC895),
    heat2: Color(0x476FC895),
    heat3: Color(0x706FC895),
    decor1: Color(0xFFE58FB0),
    decor2: Color(0xFF5FAE81),
    decor3: Color(0xFFE6C35A),
    decor4: Color(0xFF5FAE81),
    accentStrong: Color(0xFF6FC895),
  ),
  Mood.summer: MoodTokens(
    accent: Color(0xFF41C4C0),
    onAccent: Color(0xFF052222),
    soft: Color(0xFF133433),
    onSoft: Color(0xFF8ADFDB),
    heat1: Color(0x2941C4C0),
    heat2: Color(0x4741C4C0),
    heat3: Color(0x7041C4C0),
    decor1: Color(0xFFE9BC3F),
    decor2: Color(0xFFE47E5E),
    decor3: Color(0xFF3AA7A0),
    decor4: Color(0xFFE47E5E),
    accentStrong: Color(0xFF41C4C0),
  ),
  Mood.autumn: MoodTokens(
    accent: Color(0xFFF0884A),
    onAccent: Color(0xFF1F130A),
    soft: Color(0xFF3A2418),
    onSoft: Color(0xFFF6B48A),
    heat1: Color(0x29F0884A),
    heat2: Color(0x47F0884A),
    heat3: Color(0x70F0884A),
    decor1: Color(0xFFE9874A),
    decor2: Color(0xFFD8B23F),
    decor3: Color(0xFFC85B44),
    decor4: Color(0xFFD8B23F),
    accentStrong: Color(0xFFF0884A),
  ),
  Mood.newyear: MoodTokens(
    accent: Color(0xFF86B0F7),
    onAccent: Color(0xFF0B1A33),
    soft: Color(0xFF1A2740),
    onSoft: Color(0xFFB3CCF8),
    heat1: Color(0x2986B0F7),
    heat2: Color(0x4786B0F7),
    heat3: Color(0x7086B0F7),
    decor1: Color(0xFF4FA3C2),
    decor2: Color(0xFF9CCBF5),
    decor3: Color(0xFF6F95E6),
    decor4: Color(0xFFC9D3E3),
    accentStrong: Color(0xFF86B0F7),
  ),
  Mood.valentine: MoodTokens(
    accent: Color(0xFFF06292),
    onAccent: Color(0xFF2A0614),
    soft: Color(0xFF3A1626),
    onSoft: Color(0xFFF8A5C6),
    heat1: Color(0x29F06292),
    heat2: Color(0x47F06292),
    heat3: Color(0x70F06292),
    decor1: Color(0xFFF06292),
    decor2: Color(0xFFF48FB1),
    decor3: Color(0xFFEF5350),
    decor4: Color(0xFFFFE0B2),
    accentStrong: Color(0xFFF06292),
  ),
  Mood.defender: MoodTokens(
    accent: Color(0xFF9DB86A),
    onAccent: Color(0xFF151C0A),
    soft: Color(0xFF232B18),
    onSoft: Color(0xFFC3D69E),
    heat1: Color(0x299DB86A),
    heat2: Color(0x479DB86A),
    heat3: Color(0x709DB86A),
    decor1: Color(0xFF8FB34A),
    decor2: Color(0xFFE06A5C),
    decor3: Color(0xFF6F8FD0),
    decor4: Color(0xFFE0BC4E),
    accentStrong: Color(0xFF9DB86A),
  ),
  Mood.maslenitsa: MoodTokens(
    accent: Color(0xFFE7A54A),
    onAccent: Color(0xFF2A1A05),
    soft: Color(0xFF382A15),
    onSoft: Color(0xFFF3C98A),
    heat1: Color(0x29E7A54A),
    heat2: Color(0x47E7A54A),
    heat3: Color(0x70E7A54A),
    decor1: Color(0xFFE86A55),
    decor2: Color(0xFFD39B45),
    decor3: Color(0xFFB07D4C),
    decor4: Color(0xFFEBC65E),
    accentStrong: Color(0xFFE7A54A),
  ),
  Mood.women: MoodTokens(
    accent: Color(0xFFF2808F),
    onAccent: Color(0xFF2E0B11),
    soft: Color(0xFF3A1C21),
    onSoft: Color(0xFFF8B1BC),
    heat1: Color(0x29F2808F),
    heat2: Color(0x47F2808F),
    heat3: Color(0x70F2808F),
    decor1: Color(0xFFF38BA5),
    decor2: Color(0xFF6FBD6B),
    decor3: Color(0xFFEC6A80),
    decor4: Color(0xFFEED55E),
    accentStrong: Color(0xFFF2808F),
  ),
  Mood.labour: MoodTokens(
    accent: Color(0xFFE08A5C),
    onAccent: Color(0xFF2A1308),
    soft: Color(0xFF36241A),
    onSoft: Color(0xFFF0B591),
    heat1: Color(0x29E08A5C),
    heat2: Color(0x47E08A5C),
    heat3: Color(0x70E08A5C),
    decor1: Color(0xFFEA7A76),
    decor2: Color(0xFFAAB4BE),
    decor3: Color(0xFFB07D4C),
    decor4: Color(0xFFC99260),
    accentStrong: Color(0xFFE08A5C),
  ),
  Mood.victory: MoodTokens(
    accent: Color(0xFFF06A5E),
    onAccent: Color(0xFF2B0606),
    soft: Color(0xFF3A1918),
    onSoft: Color(0xFFF5A49C),
    heat1: Color(0x29F06A5E),
    heat2: Color(0x47F06A5E),
    heat3: Color(0x70F06A5E),
    decor1: Color(0xFFE85A5A),
    decor2: Color(0xFF5FA35A),
    decor3: Color(0xFFF07A4E),
    decor4: Color(0xFFEBC05A),
    accentStrong: Color(0xFFF06A5E),
  ),
  Mood.children: MoodTokens(
    accent: Color(0xFF6FB3F2),
    onAccent: Color(0xFF06213A),
    soft: Color(0xFF16293D),
    onSoft: Color(0xFFA9D2F7),
    heat1: Color(0x296FB3F2),
    heat2: Color(0x476FB3F2),
    heat3: Color(0x706FB3F2),
    decor1: Color(0xFFF07A77),
    decor2: Color(0xFF66BB6A),
    decor3: Color(0xFFA98BEA),
    decor4: Color(0xFFF2CD52),
    accentStrong: Color(0xFF6FB3F2),
  ),
  Mood.knowledge: MoodTokens(
    accent: Color(0xFFF5C451),
    onAccent: Color(0xFF2A1F04),
    soft: Color(0xFF3A2E14),
    onSoft: Color(0xFFF7D98C),
    heat1: Color(0x29F5C451),
    heat2: Color(0x47F5C451),
    heat3: Color(0x70F5C451),
    decor1: Color(0xFFF0A35E),
    decor2: Color(0xFFE8BC4A),
    decor3: Color(0xFFD99A66),
    decor4: Color(0xFFF2CD52),
    accentStrong: Color(0xFFF5C451),
  ),
  Mood.halloween: MoodTokens(
    accent: Color(0xFFFF8A2A),
    onAccent: Color(0xFF1A0E00),
    soft: Color(0xFF4B2D69),
    onSoft: Color(0xFFFFB774),
    heat1: Color(0x29FF8A2A),
    heat2: Color(0x47FF8A2A),
    heat3: Color(0x70FF8A2A),
    decor1: Color(0xFFCFC6DB),
    decor2: Color(0xFF000000),
    decor3: Color(0xFFFF8A2A),
    decor4: Color(0xFFF2E3A0),
    accentStrong: Color(0xFFFF8A2A),
  ),
  Mood.birthday: MoodTokens(
    accent: Color(0xFFB58CF5),
    onAccent: Color(0xFF1D0C36),
    soft: Color(0xFF2A1E3F),
    onSoft: Color(0xFFD3BBFA),
    heat1: Color(0x29B58CF5),
    heat2: Color(0x47B58CF5),
    heat3: Color(0x70B58CF5),
    decor1: Color(0xFFF48FB1),
    decor2: Color(0xFF4DB6AC),
    decor3: Color(0xFFB590EE),
    decor4: Color(0xFFF2CD52),
    accentStrong: Color(0xFFB58CF5),
  ),
};

/// Радиусы скругления (`radius/*`).
abstract final class RadiusTokens {
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 28;
  static const double full = 999;
}

/// Отступы: сетка 4 (`space`).
abstract final class SpaceTokens {
  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;

  /// Вся шкала по возрастанию.
  static const List<double> scale = [4, 8, 12, 16, 20, 24, 32];
}

/// Текстовый стиль из Figma: семейство, жирность, кегль и межстрочный
/// интервал в пикселях, трекинг в процентах кегля.
final class TextStyleToken {
  const TextStyleToken({
    required this.name,
    required this.family,
    required this.weight,
    required this.size,
    required this.lineHeight,
    required this.letterSpacingPct,
    required this.uppercase,
  });

  /// Имя стиля в Figma (`Display/XL`).
  final String name;
  final String family;

  /// 100…900.
  final int weight;
  final double size;
  final double lineHeight;
  final double letterSpacingPct;

  /// Текст пишется прописными (месяц).
  final bool uppercase;
}

/// Текстовые стили (`textStyles`).
abstract final class TextStyleTokens {
  /// `Display/XL`: Unbounded SemiBold 600, 44/52, трекинг -1 %.
  static const displayXl = TextStyleToken(
    name: 'Display/XL',
    family: 'Unbounded',
    weight: 600,
    size: 44,
    lineHeight: 52,
    letterSpacingPct: -1,
    uppercase: false,
  );

  /// `Display/L`: Unbounded SemiBold 600, 28/34, трекинг -0.5 %.
  static const displayL = TextStyleToken(
    name: 'Display/L',
    family: 'Unbounded',
    weight: 600,
    size: 28,
    lineHeight: 34,
    letterSpacingPct: -0.5,
    uppercase: false,
  );

  /// `Display/M`: Unbounded SemiBold 600, 22/28.
  static const displayM = TextStyleToken(
    name: 'Display/M',
    family: 'Unbounded',
    weight: 600,
    size: 22,
    lineHeight: 28,
    letterSpacingPct: 0,
    uppercase: false,
  );

  /// `Display/S`: Unbounded SemiBold 600, 17/22.
  static const displayS = TextStyleToken(
    name: 'Display/S',
    family: 'Unbounded',
    weight: 600,
    size: 17,
    lineHeight: 22,
    letterSpacingPct: 0,
    uppercase: false,
  );

  /// `Display/Month`: Unbounded SemiBold 600, 19/24, трекинг 4 %, прописными.
  static const displayMonth = TextStyleToken(
    name: 'Display/Month',
    family: 'Unbounded',
    weight: 600,
    size: 19,
    lineHeight: 24,
    letterSpacingPct: 4,
    uppercase: true,
  );

  /// `Title/L`: Manrope ExtraBold 800, 22/28.
  static const titleL = TextStyleToken(
    name: 'Title/L',
    family: 'Manrope',
    weight: 800,
    size: 22,
    lineHeight: 28,
    letterSpacingPct: 0,
    uppercase: false,
  );

  /// `Title/M`: Manrope Bold 700, 18/24.
  static const titleM = TextStyleToken(
    name: 'Title/M',
    family: 'Manrope',
    weight: 700,
    size: 18,
    lineHeight: 24,
    letterSpacingPct: 0,
    uppercase: false,
  );

  /// `Title/S`: Manrope Bold 700, 16/22.
  static const titleS = TextStyleToken(
    name: 'Title/S',
    family: 'Manrope',
    weight: 700,
    size: 16,
    lineHeight: 22,
    letterSpacingPct: 0,
    uppercase: false,
  );

  /// `Body/L`: Manrope Medium 500, 16/22.
  static const bodyL = TextStyleToken(
    name: 'Body/L',
    family: 'Manrope',
    weight: 500,
    size: 16,
    lineHeight: 22,
    letterSpacingPct: 0,
    uppercase: false,
  );

  /// `Body/M`: Manrope Medium 500, 14/20.
  static const bodyM = TextStyleToken(
    name: 'Body/M',
    family: 'Manrope',
    weight: 500,
    size: 14,
    lineHeight: 20,
    letterSpacingPct: 0,
    uppercase: false,
  );

  /// `Body/S`: Manrope Medium 500, 13/18.
  static const bodyS = TextStyleToken(
    name: 'Body/S',
    family: 'Manrope',
    weight: 500,
    size: 13,
    lineHeight: 18,
    letterSpacingPct: 0,
    uppercase: false,
  );

  /// `Label/L`: Manrope Bold 700, 16/20.
  static const labelL = TextStyleToken(
    name: 'Label/L',
    family: 'Manrope',
    weight: 700,
    size: 16,
    lineHeight: 20,
    letterSpacingPct: 0,
    uppercase: false,
  );

  /// `Label/M`: Manrope Bold 700, 14/18.
  static const labelM = TextStyleToken(
    name: 'Label/M',
    family: 'Manrope',
    weight: 700,
    size: 14,
    lineHeight: 18,
    letterSpacingPct: 0,
    uppercase: false,
  );

  /// `Label/S`: Manrope SemiBold 600, 12/16.
  static const labelS = TextStyleToken(
    name: 'Label/S',
    family: 'Manrope',
    weight: 600,
    size: 12,
    lineHeight: 16,
    letterSpacingPct: 0,
    uppercase: false,
  );

  /// `Caption`: Manrope Medium 500, 12/16.
  static const caption = TextStyleToken(
    name: 'Caption',
    family: 'Manrope',
    weight: 500,
    size: 12,
    lineHeight: 16,
    letterSpacingPct: 0,
    uppercase: false,
  );

  /// `Micro`: Manrope SemiBold 600, 11/14.
  static const micro = TextStyleToken(
    name: 'Micro',
    family: 'Manrope',
    weight: 600,
    size: 11,
    lineHeight: 14,
    letterSpacingPct: 0,
    uppercase: false,
  );

  /// `Numeric/M`: Manrope ExtraBold 800, 15/20.
  static const numericM = TextStyleToken(
    name: 'Numeric/M',
    family: 'Manrope',
    weight: 800,
    size: 15,
    lineHeight: 20,
    letterSpacingPct: 0,
    uppercase: false,
  );

  /// `Cell/Day`: Manrope Bold 700, 13/16.
  static const cellDay = TextStyleToken(
    name: 'Cell/Day',
    family: 'Manrope',
    weight: 700,
    size: 13,
    lineHeight: 16,
    letterSpacingPct: 0,
    uppercase: false,
  );

  /// `Cell/Amount`: Manrope SemiBold 600, 10/12.
  static const cellAmount = TextStyleToken(
    name: 'Cell/Amount',
    family: 'Manrope',
    weight: 600,
    size: 10,
    lineHeight: 12,
    letterSpacingPct: 0,
    uppercase: false,
  );

  /// Все стили в порядке выгрузки.
  static const List<TextStyleToken> all = [
    displayXl,
    displayL,
    displayM,
    displayS,
    displayMonth,
    titleL,
    titleM,
    titleS,
    bodyL,
    bodyM,
    bodyS,
    labelL,
    labelM,
    labelS,
    caption,
    micro,
    numericM,
    cellDay,
    cellAmount,
  ];
}

/// Тени (`shadows/*`), одинаковые в обеих темах.
abstract final class ShadowTokens {
  static const List<BoxShadow> card = [
    BoxShadow(
      offset: Offset(0, 1),
      blurRadius: 2,
      spreadRadius: 0,
      color: Color(0x0D1E1A15),
    ),
    BoxShadow(
      offset: Offset(0, 8),
      blurRadius: 24,
      spreadRadius: -4,
      color: Color(0x121E1A15),
    ),
  ];
  static const List<BoxShadow> raised = [
    BoxShadow(
      offset: Offset(0, 2),
      blurRadius: 4,
      spreadRadius: 0,
      color: Color(0x141E1A15),
    ),
    BoxShadow(
      offset: Offset(0, 10),
      blurRadius: 20,
      spreadRadius: -4,
      color: Color(0x2E1E1A15),
    ),
  ];
  static const List<BoxShadow> sheet = [
    BoxShadow(
      offset: Offset(0, -4),
      blurRadius: 32,
      spreadRadius: 0,
      color: Color(0x241E1A15),
    ),
  ];
}
