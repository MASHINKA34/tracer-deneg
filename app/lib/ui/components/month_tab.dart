import 'package:flutter/material.dart';

import '../theme/app_text.dart';
import '../theme/app_theme.dart';

/// Состояние вкладки месяца (Figma MonthTab `5:177`).
enum MonthTabState { normal, selected, future }

/// Вкладка месяца в выборе месяца: столбик (высота ∝ итог месяца /
/// максимум года) и буква в кружке 26. Выбран — столбик и кружок `accent`;
/// обычный — столбик `heat-3`; будущий — серая черта 4 и буква
/// `text/disabled`, нажать нельзя. Ширина 26 (область нажатия расширяется
/// на промежутки между вкладками — ширина 48 при 12 вкладках не
/// помещается, решение этапа 03).
class MonthTab extends StatelessWidget {
  const MonthTab({
    super.key,
    required this.letter,
    required this.state,
    this.fraction = 0,
    this.onTap,
    this.semanticLabel,
  });

  /// Первая буква месяца: «О».
  final String letter;
  final MonthTabState state;

  /// Высота столбика 0…1 от области 72.
  final double fraction;
  final VoidCallback? onTap;

  /// Полное название месяца для TalkBack.
  final String? semanticLabel;

  static const double _barArea = 72;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mood = context.mood;
    final future = state == MonthTabState.future;
    final selected = state == MonthTabState.selected;

    final bar = future
        ? Container(
            width: 14,
            height: 4,
            decoration: BoxDecoration(
              color: colors.bgSurface3,
              borderRadius: BorderRadius.circular(6),
            ),
          )
        : Container(
            width: 14,
            height: (_barArea * fraction.clamp(0, 1)).toDouble(),
            decoration: BoxDecoration(
              color: selected ? mood.accent : mood.heat3,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(6),
                bottom: Radius.circular(2),
              ),
            ),
          );

    return Semantics(
      button: !future,
      enabled: !future,
      selected: selected,
      label: semanticLabel ?? letter,
      excludeSemantics: true,
      onTap: future ? null : onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: future ? null : onTap,
        child: SizedBox(
          width: 26,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: _barArea,
                child: Align(alignment: Alignment.bottomCenter, child: bar),
              ),
              const SizedBox(height: 8),
              Container(
                width: 26,
                constraints: const BoxConstraints(minHeight: 26),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? mood.accent : null,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  letter,
                  style: AppText.labelS.copyWith(
                    color: selected
                        ? mood.onAccent
                        : future
                        ? colors.textDisabled
                        : colors.textSecondary,
                  ),
                  textScaler: TextScaler.noScaling,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
