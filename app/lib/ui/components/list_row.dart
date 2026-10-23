import 'package:flutter/material.dart';

import '../icons/app_icon.dart';
import '../theme/app_text.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';
import 'fitting_text.dart';

/// Строка списка настроек (Figma ListRow `4:53`): иконка в квадрате 36
/// `bg/surface-2`, заголовок `Body/L`, значение `Body/M` `text/tertiary`
/// (свойство «Показать значение»), шеврон (свойство «Шеврон»). Высота 60.
class ListRow extends StatelessWidget {
  const ListRow({
    super.key,
    required this.icon,
    required this.title,
    this.value,
    this.chevron = true,
    this.onTap,
    this.danger = false,
  });

  final AppIcons icon;
  final String title;
  final String? value;
  final bool chevron;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 60),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.bgSurface2,
                  borderRadius: BorderRadius.circular(RadiusTokens.xs),
                ),
                child: AppIcon(
                  icon,
                  size: 20,
                  color: danger ? colors.statusDanger : colors.textSecondary,
                ),
              ),
              const SizedBox(width: 14),
              // Заголовок и значение — в одну строку (значение у правого
              // края), а если не помещаются (крупный шрифт, узкий экран) —
              // значение переносится под заголовок.
              Expanded(
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 14,
                  runSpacing: 2,
                  children: [
                    FittingText(
                      title,
                      style: AppText.bodyL.copyWith(
                        color: danger
                            ? colors.statusDanger
                            : colors.textPrimary,
                      ),
                    ),
                    if (value != null)
                      FittingText(
                        value!,
                        style: AppText.bodyM.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                  ],
                ),
              ),
              if (chevron) ...[
                const SizedBox(width: 14),
                AppIcon(
                  AppIcons.chevronRight,
                  size: 20,
                  color: colors.textTertiary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
