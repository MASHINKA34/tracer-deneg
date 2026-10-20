import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'tap_target.dart';

/// Переключатель (Figma Toggle `26:3636`): дорожка 52 × 32, кружок 24.
/// Вкл — `accent` и кружок `on-accent`; выкл — `bg/surface-3` и кружок
/// `bg/surface`. Кружок переезжает за 150 мс (без анимации при «Убрать
/// анимацию»).
class AppToggle extends StatelessWidget {
  const AppToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
  });

  final bool value;

  /// `null` — недоступен.
  final ValueChanged<bool>? onChanged;

  /// Что переключает (если рядом нет текста, который это говорит).
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mood = context.mood;
    final noAnimation = MediaQuery.disableAnimationsOf(context);
    const duration = Duration(milliseconds: 150);

    return Semantics(
      toggled: value,
      enabled: onChanged != null,
      label: semanticLabel,
      child: TapTarget(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onChanged == null ? null : () => onChanged!(!value),
          child: AnimatedContainer(
            duration: noAnimation ? Duration.zero : duration,
            width: 52,
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: value ? mood.accent : colors.bgSurface3,
              borderRadius: BorderRadius.circular(999),
            ),
            child: AnimatedAlign(
              duration: noAnimation ? Duration.zero : duration,
              curve: Curves.easeOut,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: value ? mood.onAccent : colors.bgSurface,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
