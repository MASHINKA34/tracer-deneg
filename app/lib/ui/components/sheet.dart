import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';

/// Шторка (как на макете шторки дня `9:439`): `bg/surface`, скругление 28
/// сверху, тень sheet, ручка 36 × 4 `border/strong`. Отступы 10 сверху,
/// 16 по бокам, 28 снизу (+ системная панель), между блоками 16.
class AppSheet extends StatelessWidget {
  const AppSheet({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(RadiusTokens.xl),
        ),
        boxShadow: ShadowTokens.sheet,
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 10, 16, 28 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.borderStrong,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            for (final child in children) ...[
              const SizedBox(height: 16),
              child,
            ],
          ],
        ),
      ),
    );
  }
}

/// Открывает [AppSheet] снизу: затемнение `scrim`, закрытие жестом
/// «назад», смахиванием вниз и тапом мимо.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required List<Widget> Function(BuildContext context) builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: context.colors.scrim,
    builder: (context) => AppSheet(children: builder(context)),
  );
}
