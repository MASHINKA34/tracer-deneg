import 'package:flutter/material.dart';

import '../theme/app_text.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';
import 'fitting_text.dart';

/// Снекбар (Figma Snackbar `41:4128`): тёмная плашка `text/primary`,
/// скругление 16, текст `Body/M` `text/inverse`, действие `Label/M`
/// `accent/soft` («Отменить»).
class AppSnackbar extends StatelessWidget {
  const AppSnackbar({
    super.key,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mood = context.mood;
    return Container(
      padding: EdgeInsets.only(left: 16, right: actionLabel == null ? 16 : 4),
      constraints: const BoxConstraints(minHeight: 44),
      decoration: BoxDecoration(
        color: colors.textPrimary,
        borderRadius: BorderRadius.circular(RadiusTokens.md),
      ),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: FittingText(
                text,
                style: AppText.bodyM.copyWith(color: colors.textInverse),
              ),
            ),
          ),
          if (actionLabel != null)
            // Текст действия — на месте Figma (16 от правого края);
            // область нажатия — вся высота снекбара (44) и по 12 вбок.
            Semantics(
              button: true,
              child: InkWell(
                borderRadius: BorderRadius.circular(RadiusTokens.sm),
                onTap: onAction,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 13,
                  ),
                  child: Text(
                    actionLabel!,
                    style: AppText.labelM.copyWith(color: mood.soft),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Показывает [AppSnackbar] внизу экрана (над нижним меню, если оно есть
/// в `Scaffold`). [duration] по умолчанию 5 с — как у «Отменить» (00-spec §2).
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showAppSnackbar(
  BuildContext context, {
  required String text,
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 5),
  EdgeInsetsGeometry margin = const EdgeInsets.fromLTRB(12, 0, 12, 12),
}) {
  final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
  return messenger.showSnackBar(
    SnackBar(
      duration: duration,
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.transparent,
      elevation: 0,
      padding: EdgeInsets.zero,
      margin: margin,
      content: AppSnackbar(
        text: text,
        actionLabel: actionLabel,
        onAction: () {
          messenger.hideCurrentSnackBar(reason: SnackBarClosedReason.action);
          onAction?.call();
        },
      ),
    ),
  );
}
