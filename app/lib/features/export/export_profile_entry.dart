import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import '../../core/router.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/components/list_row.dart';
import '../../ui/icons/app_icon.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/tokens/tokens.g.dart';

final _log = Logger('export');

class ExportProfileEntry extends StatelessWidget {
  const ExportProfileEntry({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Material(
        color: context.colors.bgSurface,
        borderRadius: BorderRadius.circular(RadiusTokens.lg),
        clipBehavior: Clip.antiAlias,
        child: ListRow(
          icon: AppIcons.download,
          title: l10n.profileExport,
          onTap: () {
            _log.fine('profile export row tap → ${AppRoutes.export}');
            context.push(AppRoutes.export);
          },
        ),
      ),
    );
  }
}
