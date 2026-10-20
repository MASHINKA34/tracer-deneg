import 'package:flutter/material.dart';

import '../icons/app_icon.dart';
import '../theme/app_theme.dart';
import 'tap_target.dart';

/// Чекбокс (Figma Checkbox `41:4099`): 24 × 24, скругление 7. Отмечен —
/// заливка `accent` и галочка `on-accent` 18; нет — `bg/surface` и рамка
/// `border/strong` 2. Область нажатия 48.
class AppCheckbox extends StatelessWidget {
  const AppCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
  });

  final bool value;

  /// `null` — недоступен.
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mood = context.mood;
    final radius = BorderRadius.circular(7);
    return Semantics(
      checked: value,
      enabled: onChanged != null,
      label: semanticLabel,
      child: TapTarget(
        child: Material(
          color: value ? mood.accent : colors.bgSurface,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: value
                ? BorderSide.none
                : BorderSide(color: colors.borderStrong, width: 2),
          ),
          child: InkWell(
            borderRadius: radius,
            onTap: onChanged == null ? null : () => onChanged!(!value),
            child: SizedBox.square(
              dimension: 24,
              child: value
                  ? Center(
                      child: AppIcon(
                        AppIcons.check,
                        size: 18,
                        color: mood.onAccent,
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
