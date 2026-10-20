import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../icons/app_icon.dart';
import '../theme/app_text.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';

/// Клавиша клавиатуры суммы (Figma KeypadKey `5:161`): «Цифра» — символ
/// `Title/L` на `bg/surface`, «Стереть» — иконка backspace 26 без подложки.
/// Высота 58, ширина — сколько даст сетка, скругление 16.
class KeypadKey extends StatelessWidget {
  /// Цифра или запятая.
  const KeypadKey.symbol(String this.symbol, {super.key, required this.onTap})
    : onLongPress = null;

  /// «Стереть»; [onLongPress] — стереть всё.
  const KeypadKey.backspace({super.key, required this.onTap, this.onLongPress})
    : symbol = null;

  final String? symbol;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radius = BorderRadius.circular(RadiusTokens.md);
    final isBackspace = symbol == null;
    return Semantics(
      button: true,
      label: isBackspace ? AppLocalizations.of(context).a11yBackspace : symbol,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: isBackspace ? Colors.transparent : colors.bgSurface,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          onLongPress: onLongPress,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 58),
            child: Center(
              heightFactor: 1,
              child: isBackspace
                  ? AppIcon(
                      AppIcons.backspace,
                      size: 26,
                      color: colors.textPrimary,
                    )
                  : Text(
                      symbol!,
                      style: AppText.titleL.copyWith(color: colors.textPrimary),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
