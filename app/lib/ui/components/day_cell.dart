import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared/shared.dart' show DayKind, HeatLevel;

import '../theme/app_text.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';

/// Тип ячейки календаря (Figma DayCell `4:32`, свойство «Тип»).
enum DayCellType {
  /// До 1-го числа и после последнего — пусто.
  empty,

  /// Будущий день: число серым, без суммы.
  future,

  /// 0 ₽: без заливки, «—».
  zero,

  /// Мало — `heat-1`.
  low,

  /// Средне — `heat-2`.
  medium,

  /// Много — `heat-3`.
  high,

  /// Сегодня — заливка `accent`, текст `on-accent`.
  today;

  /// Тип по положению дня и уровню трат (00-spec §7.3).
  static DayCellType of(DayKind kind, HeatLevel heat) => switch (kind) {
    DayKind.future => DayCellType.future,
    DayKind.today => DayCellType.today,
    DayKind.past => switch (heat) {
      HeatLevel.zero => DayCellType.zero,
      HeatLevel.low => DayCellType.low,
      HeatLevel.medium => DayCellType.medium,
      HeatLevel.high => DayCellType.high,
    },
  };

  bool get _showsAmount =>
      this != DayCellType.empty && this != DayCellType.future;
}

/// Ячейка календаря: число и сумма дня, подсветка по тратам, отметка
/// праздника в правом верхнем углу (свойство «Праздник»), рамка
/// выбранного дня (как на макете шторки дня `9:439`).
///
/// Крупный шрифт (00-spec §3): высота — не меньше 46 и растёт, если не
/// помещается число дня; сумма уменьшается с 10 до 8 sp (с учётом
/// системного масштаба), а если и так не помещается — скрывается (цвет
/// ячейки остаётся).
class DayCell extends StatelessWidget {
  const DayCell({
    super.key,
    required this.type,
    this.day,
    this.amount,
    this.holidayEmoji,
    this.selected = false,
    this.onTap,
    this.semanticLabel,
  });

  final DayCellType type;

  /// Число месяца; у [DayCellType.empty] — `null`.
  final int? day;

  /// Сумма в формате ячейки («1 280», «12,4к»); у «Ноль» — «—».
  final String? amount;

  /// Эмодзи праздника в углу (`null` — нет отметки).
  final String? holidayEmoji;
  final bool selected;
  final VoidCallback? onTap;

  /// Подпись TalkBack: «19 октября, потрачено 1 100 рублей, сегодня».
  final String? semanticLabel;

  /// Высота ячейки по Figma.
  static const double baseHeight = 46;

  /// Кегль суммы по Figma и минимальный (sp, до системного масштаба).
  static const double amountSize = 10;
  static const double minAmountSize = 8;

  /// Минимальный отступ текста от края ячейки сверху и снизу.
  static const double _minVerticalPadding = 4;

  /// Высота строки числа дня при масштабе [scaler].
  static double _dayLineHeight(TextScaler scaler) {
    final style = TextStyleTokens.cellDay;
    return scaler.scale(style.size) * style.lineHeight / style.size;
  }

  /// Высота ячейки при масштабе шрифта [scaler]: 46 или больше, если не
  /// помещается число дня. Одинакова у всех ячеек — сетка задаёт её строке.
  static double heightFor(TextScaler scaler) =>
      math.max(baseHeight, _dayLineHeight(scaler) + 2 * _minVerticalPadding);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mood = context.mood;
    final scaler = MediaQuery.textScalerOf(context);
    final height = heightFor(scaler);
    final radius = BorderRadius.circular(RadiusTokens.sm);

    final Color? fill = switch (type) {
      DayCellType.low => mood.heat1,
      DayCellType.medium => mood.heat2,
      DayCellType.high => mood.heat3,
      DayCellType.today => mood.accent,
      _ => null,
    };
    final dayColor = switch (type) {
      DayCellType.future => colors.textTertiary,
      DayCellType.today => mood.onAccent,
      _ => colors.textPrimary,
    };
    final amountColor = switch (type) {
      DayCellType.zero => colors.textTertiary,
      DayCellType.today => mood.onAccent,
      _ => mood.onSoft,
    };

    Widget content = const SizedBox.shrink();
    if (type != DayCellType.empty && day != null) {
      final dayStyle = AppText.cellDay.copyWith(color: dayColor);
      content = LayoutBuilder(
        builder: (context, constraints) {
          final dayLine = _dayLineHeight(scaler);
          final amountFont = type._showsAmount && amount != null
              ? _fitAmount(
                  amount!,
                  scaler: scaler,
                  maxWidth: constraints.maxWidth - 4,
                  maxLineHeight: height - dayLine - 2 - 2 * _minVerticalPadding,
                )
              : null;
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$day',
                style: dayStyle,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.visible,
              ),
              if (amountFont != null) ...[
                const SizedBox(height: 2),
                Text(
                  amount!,
                  maxLines: 1,
                  softWrap: false,
                  textScaler: TextScaler.noScaling,
                  style: AppText.cellAmount.copyWith(
                    color: amountColor,
                    fontSize: amountFont,
                  ),
                ),
              ],
            ],
          );
        },
      );
    }

    Widget cell = Container(
      height: height,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: radius,
        border: selected
            ? Border.all(color: mood.accentStrong, width: 2)
            : null,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: content),
          if (holidayEmoji != null)
            Positioned(
              top: selected ? -2 : 0,
              right: selected ? -1 : 1,
              child: ExcludeSemantics(
                child: Text(
                  holidayEmoji!,
                  style: AppText.micro.copyWith(color: colors.textPrimary),
                  textScaler: TextScaler.noScaling,
                ),
              ),
            ),
        ],
      ),
    );

    if (onTap != null) {
      cell = Material(
        type: MaterialType.transparency,
        child: InkWell(borderRadius: radius, onTap: onTap, child: cell),
      );
    }
    if (type == DayCellType.empty) return ExcludeSemantics(child: cell);
    final actionable = onTap != null && type != DayCellType.future;
    return Semantics(
      button: actionable,
      selected: selected,
      label: semanticLabel,
      onTap: actionable ? onTap : null,
      excludeSemantics: true,
      child: cell,
    );
  }

  /// Кегль суммы (уже с масштабом) от 10 до 8 sp, при котором [text]
  /// помещается в [maxWidth] × [maxLineHeight]; `null` — не помещается.
  static double? _fitAmount(
    String text, {
    required TextScaler scaler,
    required double maxWidth,
    required double maxLineHeight,
  }) {
    final style = TextStyleTokens.cellAmount;
    for (var size = amountSize; size >= minAmountSize; size -= 0.5) {
      final fontSize = scaler.scale(size);
      final lineHeight = fontSize * style.lineHeight / style.size;
      if (lineHeight > maxLineHeight + 0.01) continue;
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: AppText.cellAmount.copyWith(fontSize: fontSize),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      if (width <= maxWidth + 0.01) return fontSize;
    }
    return null;
  }
}
