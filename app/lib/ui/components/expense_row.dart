import 'package:flutter/material.dart';
import 'package:shared/shared.dart' show CategoryColor;

import '../theme/app_text.dart';
import '../theme/app_theme.dart';
import 'avatar.dart';
import 'category_badge.dart';
import 'fitting_text.dart';

/// Кто добавил трату (в общем бюджете) — аватар 24 у суммы.
final class ExpenseAuthor {
  const ExpenseAuthor({required this.letter, required this.color, this.name});

  final String letter;
  final CategoryColor color;

  /// Имя для TalkBack.
  final String? name;
}

/// Строка траты (Figma ExpenseRow `4:44`): значок категории, название и
/// описание (в одну строку с многоточием, как в Figma; при крупном шрифте —
/// до трёх строк), автор (свойство «Автор»), сумма `Numeric/M`. Высота 60.
///
/// Если рядом с суммой слово названия или описания не помещается (узкий
/// экран, крупный шрифт), сумма с автором уходит под описание, слева, —
/// чтобы текст не уменьшался. Решается по замеру каждой строки.
class ExpenseRow extends StatelessWidget {
  const ExpenseRow({
    super.key,
    required this.emoji,
    required this.color,
    required this.title,
    required this.amount,
    this.subtitle,
    this.author,
    this.onTap,
    this.subtitleColor,
  });

  final String emoji;

  /// Цвет категории; `null` — «Другое».
  final CategoryColor? color;
  final String title;

  /// Описание: «Пятёрочка · 14:20».
  final String? subtitle;

  /// Готовая строка суммы: «640 ₽».
  final String amount;
  final ExpenseAuthor? author;
  final VoidCallback? onTap;

  final Color? subtitleColor;

  /// Строк у названия и описания: как в Figma — одна с многоточием; при
  /// крупном шрифте — до трёх, чтобы короткие названия не обрезались.
  static int _maxLines(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(1) > 1.15 ? 3 : 1;

  /// Отступ между значком, текстом, автором и суммой.
  static const double _gap = 12;

  /// Аватар автора у суммы.
  static const double _avatarSize = 24;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final lines = _maxLines(context);
    final titleStyle = AppText.labelM.copyWith(color: colors.textPrimary);
    final subtitleStyle = AppText.caption.copyWith(
      color: subtitleColor ?? colors.textTertiary,
    );
    final amountStyle = AppText.numericM.copyWith(color: colors.textPrimary);

    final texts = [
      FittingText(
        title,
        maxLines: lines,
        overflow: TextOverflow.ellipsis,
        style: titleStyle,
      ),
      if (subtitle != null) ...[
        const SizedBox(height: 2),
        FittingText(
          subtitle!,
          maxLines: lines,
          overflow: TextOverflow.ellipsis,
          style: subtitleStyle,
        ),
      ],
    ];
    final avatar = author == null
        ? null
        : AppAvatar(
            letter: author!.letter,
            color: author!.color,
            size: AvatarSize.s24,
            semanticLabel: author!.name,
          );

    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 60),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (!_amountBelow(
                context,
                constraints,
                titleStyle,
                subtitleStyle,
                amountStyle,
              )) {
                return Row(
                  children: [
                    CategoryBadge(emoji: emoji, color: color),
                    const SizedBox(width: _gap),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: texts,
                      ),
                    ),
                    if (avatar != null) ...[
                      const SizedBox(width: _gap),
                      avatar,
                    ],
                    const SizedBox(width: _gap),
                    Text(amount, style: amountStyle),
                  ],
                );
              }
              return Row(
                children: [
                  CategoryBadge(emoji: emoji, color: color),
                  const SizedBox(width: _gap),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ...texts,
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (avatar != null) ...[
                              avatar,
                              const SizedBox(width: _gap),
                            ],
                            // Сумма — одно целое: не переносим, а в крайнем
                            // случае уменьшаем, как итог карточки месяца.
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  amount,
                                  maxLines: 1,
                                  style: amountStyle,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Сумма уходит под описание, если рядом с ней (и с автором) самое
  /// длинное слово названия или описания не помещается — иначе
  /// [FittingText] уменьшил бы его кегль.
  bool _amountBelow(
    BuildContext context,
    BoxConstraints constraints,
    TextStyle titleStyle,
    TextStyle subtitleStyle,
    TextStyle amountStyle,
  ) {
    if (!constraints.hasBoundedWidth) return false;
    final painter = TextPainter(
      text: TextSpan(text: amount, style: amountStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final amountWidth = painter.width;
    painter.dispose();
    final textWidth =
        constraints.maxWidth -
        CategoryBadge.size -
        _gap -
        (author == null ? 0 : _avatarSize + _gap) -
        _gap -
        amountWidth;
    var widest = FittingText.widestWord(context, title, titleStyle);
    if (subtitle != null) {
      final w = FittingText.widestWord(context, subtitle!, subtitleStyle);
      if (w > widest) widest = w;
    }
    return widest > textWidth;
  }
}
