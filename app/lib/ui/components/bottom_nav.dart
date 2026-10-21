import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

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
    final nav = Container(
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
                  child: _FabAnchor(
                    child: AppFab(onPressed: onAdd, stickerEmoji: fabSticker),
                  ),
                ),
              ],
            ),
          ),
          tab(AppNavTab.recurring, AppIcons.repeat, l10n.navRecurring),
          tab(AppNavTab.profile, AppIcons.user, l10n.navProfile),
        ],
      ),
    );
    return _FabHitArea(child: nav);
  }
}

class _FabHitArea extends SingleChildRenderObjectWidget {
  const _FabHitArea({required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderFabHitArea();
}

class _RenderFabHitArea extends RenderProxyBox {
  _RenderFabAnchor? fab;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final fab = this.fab;
    if (fab != null && fab.attached && fab.hasSize) {
      final transform = fab.getTransformTo(this);
      final local = MatrixUtils.transformPoint(
        Matrix4.inverted(transform),
        position,
      );
      if (fab.size.contains(local) &&
          result.addWithPaintTransform(
            transform: transform,
            position: position,
            hitTest: (result, position) =>
                fab.hitTest(result, position: position),
          )) {
        result.add(BoxHitTestEntry(this, position));
        return true;
      }
    }
    return super.hitTest(result, position: position);
  }
}

class _FabAnchor extends SingleChildRenderObjectWidget {
  const _FabAnchor({required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderFabAnchor();
}

class _RenderFabAnchor extends RenderProxyBox {
  _RenderFabHitArea? _area;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    var node = parent;
    while (node != null && node is! _RenderFabHitArea) {
      node = node.parent;
    }
    _area = node as _RenderFabHitArea?;
    _area?.fab = this;
  }

  @override
  void detach() {
    if (_area?.fab == this) _area?.fab = null;
    _area = null;
    super.detach();
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
