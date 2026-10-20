import 'package:flutter/widgets.dart';
import 'package:shared/shared.dart' show CategoryColor;

import '../theme/app_text.dart';
import '../theme/app_theme.dart';

/// Размеры аватара (Figma Avatar `3:185`).
enum AvatarSize {
  s24(24),
  s32(32),
  s40(40),
  s64(64);

  const AvatarSize(this.dimension);

  final double dimension;

  TextStyle get _textStyle => switch (this) {
    AvatarSize.s24 => AppText.micro,
    AvatarSize.s32 => AppText.labelS,
    AvatarSize.s40 => AppText.labelM,
    AvatarSize.s64 => AppText.titleL,
  };
}

/// Круглый аватар с буквой имени на цвете пользователя (один из 10 цветов
/// категорий, `solid`). Буква — `text/inverse`.
class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    required this.letter,
    this.size = AvatarSize.s40,
    this.color = CategoryColor.blue,
    this.semanticLabel,
  });

  /// Первая буква имени.
  final String letter;
  final AvatarSize size;
  final CategoryColor color;

  /// Подпись для TalkBack (имя); без неё аватар — украшение.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final avatar = Container(
      width: size.dimension,
      height: size.dimension,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.category(color)!.solid,
        shape: BoxShape.circle,
      ),
      // Буква не растёт со шрифтом системы: она в фиксированном круге.
      child: Text(
        letter,
        style: size._textStyle.copyWith(color: colors.textInverse),
        maxLines: 1,
        textScaler: TextScaler.noScaling,
      ),
    );
    return semanticLabel == null
        ? ExcludeSemantics(child: avatar)
        : Semantics(
            label: semanticLabel,
            excludeSemantics: true,
            child: avatar,
          );
  }
}
