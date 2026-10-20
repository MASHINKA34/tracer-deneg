import 'package:flutter/material.dart';

import '../theme/app_text.dart';
import '../theme/app_theme.dart';
import 'fitting_text.dart';

/// Вариант переключателя [AppSegmented].
final class SegmentOption<T> {
  const SegmentOption(this.value, this.label);

  final T value;
  final String label;
}

/// Переключатель «Месяц / Год» (Figma Segmented `41:4094`): подложка
/// `bg/surface-2` 44 с отступом 4, выбранный вариант — «таблетка» `bg/surface`
/// 36. Растягивается на ширину, варианты поровну. Область нажатия каждого
/// варианта — на всю высоту 48 (подложка по центру, сверху и снизу по 2).
class AppSegmented<T> extends StatelessWidget {
  const AppSegmented({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final List<SegmentOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Stack(
      children: [
        Positioned.fill(
          top: 2,
          bottom: 2,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.bgSurface2,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              for (final (i, option) in options.indexed) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(
                  child: _Segment(
                    option: option,
                    selected: option.value == selected,
                    onTap: () => onChanged(option.value),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Segment<T> extends StatelessWidget {
  const _Segment({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final SegmentOption<T> option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    const shape = StadiumBorder();
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        // Нажатие над и под «таблеткой» (внутри 48) — тоже этот вариант.
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Material(
            color: selected ? colors.bgSurface : Colors.transparent,
            shape: shape,
            child: InkWell(
              customBorder: shape,
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 36),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 9,
                  ),
                  child: Center(
                    heightFactor: 1,
                    child: FittingText(
                      option.label,
                      textAlign: TextAlign.center,
                      style: AppText.labelM.copyWith(
                        color: selected
                            ? colors.textPrimary
                            : colors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
