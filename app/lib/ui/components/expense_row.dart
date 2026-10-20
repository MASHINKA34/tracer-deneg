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
/// до трёх строк), автор (свойство
/// «Автор»), сумма `Numeric/M` моноширинными цифрами. Высота 60.
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

  /// Строк у названия и описания: как в Figma — одна с многоточием; при
  /// крупном шрифте — до трёх, чтобы короткие названия не обрезались.
  static int _maxLines(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(1) > 1.15 ? 3 : 1;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final lines = _maxLines(context);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 60),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              CategoryBadge(emoji: emoji, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittingText(
                      title,
                      maxLines: lines,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.labelM.copyWith(color: colors.textPrimary),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      FittingText(
                        subtitle!,
                        maxLines: lines,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (author != null) ...[
                const SizedBox(width: 12),
                AppAvatar(
                  letter: author!.letter,
                  color: author!.color,
                  size: AvatarSize.s24,
                  semanticLabel: author!.name,
                ),
              ],
              const SizedBox(width: 12),
              Text(
                amount,
                style: AppText.numericM.copyWith(color: colors.textPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
