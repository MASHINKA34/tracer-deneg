import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'tap_target.dart';

/// Радио-кнопка (Figma Radio `41:4103`): круг 24 `bg/surface` с рамкой 2.
/// Выбрана — рамка `accent-strong` и точка `accent` 12; нет — рамка
/// `border/strong`. Область нажатия 48.
class AppRadio extends StatelessWidget {
  const AppRadio({
    super.key,
    required this.selected,
    required this.onTap,
    this.semanticLabel,
  });

  final bool selected;

  /// `null` — недоступна.
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mood = context.mood;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      enabled: onTap != null,
      label: semanticLabel,
      child: TapTarget(
        child: Material(
          color: colors.bgSurface,
          shape: CircleBorder(
            side: BorderSide(
              color: selected ? mood.accentStrong : colors.borderStrong,
              width: 2,
            ),
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox.square(
              dimension: 24,
              child: selected
                  ? Center(
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: mood.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
