import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/icons/app_icon.dart';
import '../../ui/theme/app_text.dart';
import '../../ui/theme/app_theme.dart';

final _log = Logger('nav');

class NewExpenseStubScreen extends StatefulWidget {
  const NewExpenseStubScreen({super.key});

  @override
  State<NewExpenseStubScreen> createState() => _NewExpenseStubScreenState();
}

class _NewExpenseStubScreenState extends State<NewExpenseStubScreen> {
  bool _closeTapped = false;

  void _close() {
    _closeTapped = true;
    context.pop();
  }

  void _handlePop(bool didPop, Object? result) {
    if (!didPop) return;
    _log.fine(
      'new expense closed by ${_closeTapped ? 'close button' : 'back'}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    return PopScope<Object?>(
      onPopInvokedWithResult: _handlePop,
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  children: [
                    Semantics(
                      button: true,
                      label: l10n.a11yClose,
                      excludeSemantics: true,
                      onTap: _close,
                      child: InkResponse(
                        radius: 22,
                        onTap: _close,
                        child: SizedBox.square(
                          dimension: 48,
                          child: Center(
                            child: AppIcon(
                              AppIcons.x,
                              size: 24,
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          l10n.newExpenseTitle,
                          textAlign: TextAlign.center,
                          style: AppText.titleS.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
