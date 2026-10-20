import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../icons/app_icon.dart';
import '../theme/app_text.dart';
import '../theme/app_theme.dart';
import 'fab.dart';

/// Вкладки нижнего меню.
enum AppNavTab { month, stats, recurring, profile }

/// Нижнее меню (Figma BottomNav `5:154`): Месяц · Статистика · [+] ·
/// Регулярные · Профиль. Фон `bg/surface` до низа экрана, сверху линия
/// `border/default`. Активная вкладка — «таблетка» `accent/soft` под
/// иконкой и подпись `Label/S`; остальные — `Micro` `text/tertiary`.
///
/// Снизу отступ max(18, системная панель): без панели — как в Figma, с
/// панелью — кнопки сразу над ней (решение этапа 03).
/// Подпись, которая не помещается по ширине (экран 320, крупный шрифт),
/// уменьшается, а не обрезается.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.active,
    required this.onTabSelected,
    required this.onAdd,
    this.fabSticker,
  });

  final AppNavTab active;
  final ValueChanged<AppNavTab> onTabSelected;
  final VoidCallback? onAdd;

  /// Эмодзи наклейки на «+» (праздник).
  final String? fabSticker;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = AppLocalizations.of(context);
    final bottom = math.max(18.0, MediaQuery.viewPaddingOf(context).bottom);

    Widget tab(AppNavTab tab, AppIcons icon, String label) => Expanded(
      child: _NavTab(
        icon: icon,
        label: label,
        active: tab == active,
        onTap: () => onTabSelected(tab),
      ),
    );

    // Container добавляет линию сверху (1) к отступу 8 — как в Figma, где
    // обводка входит в размер.
    return Container(
      decoration: BoxDecoration(
        color: colors.bgSurface,
        border: Border(top: BorderSide(color: colors.borderDefault)),
      ),
      padding: EdgeInsets.fromLTRB(6, 8, 6, bottom),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          tab(AppNavTab.month, AppIcons.calendar, l10n.navMonth),
          tab(AppNavTab.stats, AppIcons.pieChart, l10n.navStats),
          // Слот 64 × 54, «+» выступает над меню на 26 (как в Figma).
          SizedBox(
            width: 64,
            height: 54,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 2,
                  top: -26,
                  child: AppFab(onPressed: onAdd, stickerEmoji: fabSticker),
                ),
              ],
            ),
          ),
          tab(AppNavTab.recurring, AppIcons.repeat, l10n.navRecurring),
          tab(AppNavTab.profile, AppIcons.user, l10n.navProfile),
        ],
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  const _NavTab({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final AppIcons icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mood = context.mood;
    final style = active
        ? AppText.labelS.copyWith(color: colors.textPrimary)
        : AppText.micro.copyWith(color: colors.textTertiary);
    return Semantics(
      button: true,
      selected: active,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: InkResponse(
        onTap: onTap,
        containedInkWell: true,
        highlightShape: BoxShape.rectangle,
        borderRadius: BorderRadius.circular(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active ? mood.soft : null,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: AppIcon(
                  icon,
                  size: 22,
                  color: active ? mood.onSoft : colors.textTertiary,
                ),
              ),
              const SizedBox(height: 4),
              // Не помещается во вкладку (экран 320, крупный шрифт) —
              // уменьшается, а не обрезается и не налезает на соседей.
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label, maxLines: 1, style: style),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
