import 'package:flutter/material.dart';

import '../icons/app_icon.dart';
import '../theme/app_text.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';
import 'button.dart';

/// Кнопка диалога.
final class AppDialogAction {
  const AppDialogAction(this.label, this.onPressed, {this.destructive = false});

  final String label;
  final VoidCallback? onPressed;

  /// Красный текст (для второй кнопки: «Выйти и потерять»).
  final bool destructive;
}

/// Диалог (как на макете `42:4321`): ширина до 312, скругление 28,
/// иконка 26 в круге 56 `bg/surface-2`, заголовок `Title/M`, текст `Body/M`
/// по центру, основная кнопка Primary L и вторая — Text L на всю ширину.
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    this.icon,
    required this.title,
    this.message,
    required this.primary,
    this.secondary,
    this.textAlign = TextAlign.center,
  });

  final AppIcons? icon;
  final String title;
  final String? message;
  final AppDialogAction primary;
  final AppDialogAction? secondary;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Сама карточка диалога; окно поверх экрана (затемнение, поля 24,
    // «назад») добавляет [showAppDialog].
    return Material(
      color: colors.bgSurface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(RadiusTokens.xl)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 312),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (icon != null) ...[
                Center(
                  child: Container(
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.bgSurface2,
                      shape: BoxShape.circle,
                    ),
                    child: AppIcon(
                      icon!,
                      size: 26,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Semantics(
                header: true,
                child: Text(
                  title,
                  textAlign: textAlign,
                  style: AppText.titleM.copyWith(color: colors.textPrimary),
                ),
              ),
              if (message != null) ...[
                const SizedBox(height: 12),
                Text(
                  message!,
                  textAlign: textAlign,
                  style: AppText.bodyM.copyWith(color: colors.textSecondary),
                ),
              ],
              const SizedBox(height: 12),
              AppButton(
                label: primary.label,
                onPressed: primary.onPressed,
                type: primary.destructive
                    ? AppButtonType.danger
                    : AppButtonType.primary,
                expand: true,
              ),
              if (secondary != null) ...[
                const SizedBox(height: 12),
                AppButton(
                  label: secondary!.label,
                  onPressed: secondary!.onPressed,
                  type: AppButtonType.text,
                  destructive: secondary!.destructive,
                  expand: true,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Показывает [AppDialog] поверх экрана: затемнение `scrim`, поля 24,
/// закрытие жестом «назад» и тапом мимо (если [barrierDismissible]).
Future<T?> showAppDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: context.colors.scrim,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(24),
      child: builder(context),
    ),
  );
}
