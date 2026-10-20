import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Минимальная область нажатия по правилам доступности (00-spec §3).
const double kMinTapTarget = 48;

/// Расширяет область нажатия маленького элемента до [minWidth] × [minHeight]
/// (по умолчанию 48 × 48): рисунок [child] остаётся своего размера и по
/// центру, а нажатие в пустой полосе вокруг передаётся в его центр — так же
/// делает Material (`MaterialTapTargetSize.padded`). Рябь не выходит за
/// рисунок.
class TapTarget extends SingleChildRenderObjectWidget {
  const TapTarget({
    super.key,
    this.minWidth = kMinTapTarget,
    this.minHeight = kMinTapTarget,
    required Widget super.child,
  });

  final double minWidth;
  final double minHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderTapTarget(Size(minWidth, minHeight));

  @override
  void updateRenderObject(BuildContext context, RenderTapTarget renderObject) {
    renderObject.minSize = Size(minWidth, minHeight);
  }
}

/// Render-объект [TapTarget].
class RenderTapTarget extends RenderShiftedBox {
  RenderTapTarget(this._minSize) : super(null);

  Size _minSize;
  set minSize(Size value) {
    if (value == _minSize) return;
    _minSize = value;
    markNeedsLayout();
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      math.max(child?.getMinIntrinsicWidth(height) ?? 0, _minSize.width);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      math.max(child?.getMaxIntrinsicWidth(height) ?? 0, _minSize.width);

  @override
  double computeMinIntrinsicHeight(double width) =>
      math.max(child?.getMinIntrinsicHeight(width) ?? 0, _minSize.height);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      math.max(child?.getMaxIntrinsicHeight(width) ?? 0, _minSize.height);

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final childSize = child?.getDryLayout(constraints.loosen()) ?? Size.zero;
    return constraints.constrain(
      Size(
        math.max(childSize.width, _minSize.width),
        math.max(childSize.height, _minSize.height),
      ),
    );
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.constrain(_minSize);
      return;
    }
    child.layout(constraints.loosen(), parentUsesSize: true);
    size = constraints.constrain(
      Size(
        math.max(child.size.width, _minSize.width),
        math.max(child.size.height, _minSize.height),
      ),
    );
    final parentData = child.parentData! as BoxParentData;
    parentData.offset = Alignment.center.alongOffset(
      size - child.size as Offset,
    );
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (super.hitTest(result, position: position)) return true;
    final child = this.child;
    if (child == null || !size.contains(position)) return false;
    // Нажатие мимо рисунка, но внутри области — в центр рисунка.
    final center = child.size.center(Offset.zero);
    return result.addWithRawTransform(
      transform: MatrixUtils.forceToPoint(center),
      position: center,
      hitTest: (result, position) => child.hitTest(result, position: center),
    );
  }
}
