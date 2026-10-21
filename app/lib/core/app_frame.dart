import 'dart:math' as math;
import 'dart:ui' show DisplayFeature;

import 'package:flutter/widgets.dart';

import '../ui/theme/app_theme.dart';

const double maxContentWidth = 480;

double contentWidthFor(double windowWidth) =>
    math.min(windowWidth, maxContentWidth);

double contentLeftFor(double windowWidth, EdgeInsets padding) {
  final width = contentWidthFor(windowWidth);
  final safeWidth = windowWidth - padding.left - padding.right;
  if (safeWidth >= width) return padding.left + (safeWidth - width) / 2;
  return (windowWidth - width) / 2;
}

class AppFrame extends StatelessWidget {
  const AppFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final window = media.size;
    final width = contentWidthFor(window.width);
    final left = contentLeftFor(window.width, media.padding);
    final right = window.width - width - left;

    EdgeInsets inside(EdgeInsets insets) => insets.copyWith(
      left: math.max(0, insets.left - left),
      right: math.max(0, insets.right - right),
    );

    return ColoredBox(
      color: context.colors.bgApp,
      child: Padding(
        padding: EdgeInsets.only(left: left, right: right),
        child: MediaQuery(
          data: media.copyWith(
            size: Size(width, window.height),
            padding: inside(media.padding),
            viewPadding: inside(media.viewPadding),
            viewInsets: inside(media.viewInsets),
            systemGestureInsets: inside(media.systemGestureInsets),
            displayFeatures: [
              for (final feature in media.displayFeatures)
                DisplayFeature(
                  bounds: feature.bounds.shift(Offset(-left, 0)),
                  type: feature.type,
                  state: feature.state,
                ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
