import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/theme/app_text.dart';
import '../../ui/theme/app_theme.dart';

class TabStubScreen extends StatelessWidget {
  const TabStubScreen({
    super.key,
    required this.title,
    this.children = const [],
  });

  final String Function(AppLocalizations l10n) title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final text = title(AppLocalizations.of(context));
    final header = Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 60),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
          child: Semantics(
            header: true,
            child: Text(
              text,
              style: AppText.titleL.copyWith(color: context.colors.textPrimary),
            ),
          ),
        ),
      ),
    );
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: children.isEmpty
            ? header
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [header, ...children],
              ),
      ),
    );
  }
}
