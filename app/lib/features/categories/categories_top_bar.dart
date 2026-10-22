import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/components/fitting_text.dart';
import '../../ui/components/tap_target.dart';
import '../../ui/icons/app_icon.dart';
import '../../ui/theme/app_text.dart';
import '../../ui/theme/app_theme.dart';

class CategoriesTopBar extends StatelessWidget {
  const CategoriesTopBar({
    super.key,
    required this.title,
    required this.onBack,
    this.addLabel,
    this.onAdd,
  });

  final String title;
  final VoidCallback onBack;
  final String? addLabel;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final label = addLabel;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            Semantics(
              button: true,
              label: l10n.a11yBack,
              excludeSemantics: true,
              onTap: onBack,
              child: InkResponse(
                radius: 22,
                onTap: onBack,
                child: SizedBox.square(
                  dimension: kMinTapTarget,
                  child: Center(
                    child: AppIcon(
                      AppIcons.arrowLeft,
                      size: 24,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: Semantics(
                header: true,
                child: FittingText(
                  title,
                  style: AppText.titleM.copyWith(color: colors.textPrimary),
                ),
              ),
            ),
            if (label != null)
              Semantics(
                button: true,
                enabled: onAdd != null,
                label: label,
                excludeSemantics: true,
                onTap: onAdd,
                child: InkResponse(
                  radius: 22,
                  onTap: onAdd,
                  child: SizedBox.square(
                    dimension: kMinTapTarget,
                    child: Center(
                      child: Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: colors.bgSurface,
                          shape: BoxShape.circle,
                        ),
                        child: AppIcon(
                          AppIcons.plus,
                          size: 22,
                          color: onAdd == null
                              ? colors.textDisabled
                              : colors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
