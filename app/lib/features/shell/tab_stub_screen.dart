import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/theme/app_text.dart';
import '../../ui/theme/app_theme.dart';

class TabStubScreen extends StatelessWidget {
  const TabStubScreen({super.key, required this.title});

  final String Function(AppLocalizations l10n) title;

  @override
  Widget build(BuildContext context) {
    final text = title(AppLocalizations.of(context));
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
              child: Semantics(
                header: true,
                child: Text(
                  text,
                  style: AppText.titleL.copyWith(
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
