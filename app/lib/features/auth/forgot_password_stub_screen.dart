import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import '../../core/router.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/components/fitting_text.dart';
import '../../ui/theme/app_text.dart';
import '../../ui/theme/app_theme.dart';
import 'auth_widgets.dart';

final _log = Logger('auth');

class ForgotPasswordStubScreen extends StatelessWidget {
  const ForgotPasswordStubScreen({super.key});

  void _back(BuildContext context) {
    if (context.canPop()) {
      _log.fine('auth stack: forgot password stub → back to login');
      context.pop();
      return;
    }
    _log.fine(
      'auth stack: forgot password stub closed with nothing under it → '
      '${AppRoutes.login}',
    );
    context.go(AppRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.bgApp,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AuthBackBar(onBack: () => _back(context)),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Semantics(
                header: true,
                child: FittingText(
                  AppLocalizations.of(context).authForgotTitle,
                  style: AppText.titleL.copyWith(color: colors.textPrimary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
