import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:logging/logging.dart';

import '../../l10n/app_localizations.dart';
import '../icons/app_icon.dart';
import '../theme/app_text.dart';
import '../theme/app_theme.dart';
import 'fab.dart';

final _log = Logger('nav.labels');

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
class AppBottomNav extends StatefulWidget {
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

  static const double labelGap = 4;

  static const double _sidePadding = 6;

  static const double _fabSlot = 64;

  static double labelScale({
    required double width,
    required TextScaler textScaler,
    required List<String> labels,
  }) => _measureLabels(width, textScaler, labels).scale;

  static ({double scale, String widest, double widestWidth, double tab})
  _measureLabels(double width, TextScaler textScaler, List<String> labels) {
    final tab = (width - 2 * _sidePadding - _fabSlot) / labels.length;
    final widths = [
      for (final label in labels)
        (TextPainter(
          text: TextSpan(text: label, style: AppText.labelS),
          textScaler: textScaler,
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout()).width,
    ];
    var widest = 0;
    for (var i = 1; i < widths.length; i++) {
      if (widths[i] > widths[widest]) widest = i;
    }
    var scale = 1.0;
    for (final w in widths) {
      if (w > 0) scale = math.min(scale, tab / w);
    }
    final half = labels.length ~/ 2;
    for (var i = 0; i + 1 < labels.length; i++) {
      if (i + 1 == half) continue;
      final pair = (widths[i] + widths[i + 1]) / 2;
      if (pair > 0) scale = math.min(scale, (tab - labelGap) / pair);
    }
    return (
      scale: math.max(0, scale),
      widest: labels[widest],
      widestWidth: widths[widest],
      tab: tab,
    );
  }

  @override
  State<AppBottomNav> createState() => _AppBottomNavState();
}

class _AppBottomNavState extends State<AppBottomNav> {
  double? _loggedScale;

  double _labelScale(BuildContext context, double width, List<String> labels) {
    final scaler = MediaQuery.textScalerOf(context);
    final m = AppBottomNav._measureLabels(width, scaler, labels);
    if (_loggedScale != m.scale) {
      _loggedScale = m.scale;
      final where =
          'widest «${m.widest}» ${m.widestWidth.toStringAsFixed(1)}dp, '
          'tab ${m.tab.toStringAsFixed(1)}dp, gap ${AppBottomNav.labelGap}dp, '
          'textScale=${(scaler.scale(12) / 12).toStringAsFixed(2)} '
          'width=${width.toStringAsFixed(0)}dp';
      _log.fine(
        m.scale < 1
            ? 'nav labels scaled together '
                  'x${m.scale.toStringAsFixed(3)} to fit: $where'
            : 'nav labels at full size: $where',
      );
    }
    return m.scale;
  }

  @override
  Widget build(BuildContext context) => _FabHitArea(
    child: Semantics(
      container: true,
      explicitChildNodes: true,
      child: LayoutBuilder(
        builder: (context, constraints) => _bar(context, constraints.maxWidth),
      ),
    ),
  );

  Widget _bar(BuildContext context, double width) {
    final active = widget.active;
    final colors = context.colors;
    final l10n = AppLocalizations.of(context);
    final bottom = math.max(18.0, MediaQuery.viewPaddingOf(context).bottom);
    final scale = _labelScale(context, width, [
      l10n.navMonth,
      l10n.navStats,
      l10n.navRecurring,
      l10n.navProfile,
    ]);

    Widget tab(AppNavTab tab, AppIcons icon, String label) => Expanded(
      child: _NavTab(
        icon: icon,
        label: label,
        labelScale: scale,
        active: tab == active,
        order: tab.index < AppNavTab.recurring.index
            ? tab.index
            : tab.index + 1,
        onTap: () => widget.onTabSelected(tab),
      ),
    );

    // Container добавляет линию сверху (1) к отступу 8 — как в Figma, где
    // обводка входит в размер.
    return Container(
      decoration: BoxDecoration(
        color: colors.bgSurface,
        border: Border(top: BorderSide(color: colors.borderDefault)),
      ),
      padding: EdgeInsets.fromLTRB(
        AppBottomNav._sidePadding,
        8,
        AppBottomNav._sidePadding,
        bottom,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          tab(AppNavTab.month, AppIcons.calendar, l10n.navMonth),
          tab(AppNavTab.stats, AppIcons.pieChart, l10n.navStats),
          // Слот 64 × 54, «+» выступает над меню на 26 (как в Figma).
          SizedBox(
            width: AppBottomNav._fabSlot,
            height: 54,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 2,
                  top: -26,
                  child: _FabAnchor(
                    child: Semantics(
                      sortKey: OrdinalSortKey(
                        AppNavTab.recurring.index.toDouble(),
                      ),
                      child: AppFab(
                        onPressed: widget.onAdd,
                        stickerEmoji: widget.fabSticker,
                      ),
                    ),
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
    required this.labelScale,
    required this.active,
    required this.order,
    required this.onTap,
  });

  final AppIcons icon;
  final String label;
  final double labelScale;
  final bool active;
  final int order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mood = context.mood;
    final base = active
        ? AppText.labelS.copyWith(color: colors.textPrimary)
        : AppText.micro.copyWith(color: colors.textTertiary);
    final style = base.copyWith(
      fontSize:
          MediaQuery.textScalerOf(context).scale(base.fontSize!) * labelScale,
    );
    return Semantics(
      sortKey: OrdinalSortKey(order.toDouble()),
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
                child: Text(
                  label,
                  maxLines: 1,
                  textScaler: TextScaler.noScaling,
                  style: style,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
