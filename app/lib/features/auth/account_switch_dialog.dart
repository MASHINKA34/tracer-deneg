import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/components/dialog.dart';
import '../../ui/components/snackbar.dart';
import '../../ui/icons/app_icon.dart';
import 'auth_service.dart';
import 'session_end_service.dart';

final _log = Logger('auth');

Future<bool> confirmSignIn(
  BuildContext context,
  WidgetRef ref, {
  required AuthAction action,
  required String login,
}) async {
  final check = await ref
      .read(sessionEndServiceProvider)
      .checkSignIn(
        action: action.name,
        login: login,
        newAccount: action == AuthAction.register,
      );
  if (!context.mounted) {
    _log.fine(
      '${action.name}: screen closed while checking the previous account → '
      'not signing in',
    );
    return false;
  }
  switch (check) {
    case SignInFresh() || SignInSameAccount():
      return true;
    case SignInOtherAccount(:final queueSize) when queueSize == 0:
      return true;
    case SignInOtherAccount(:final queueSize):
      final agreed = await showAppDialog<bool>(
        context,
        builder: (context) => AccountSwitchDialog(queueSize: queueSize),
      );
      final choice = switch (agreed) {
        true => 'delete',
        false => 'cancel',
        null => 'dismissed',
      };
      _log.info(
        '${action.name}: previous account dialog choice=$choice '
        'queue=$queueSize → '
        '${agreed == true ? 'signing in, previous account data cleared once the server accepts' : 'not signing in, nothing cleared'}',
      );
      return agreed == true;
    case SignInCheckFailed():
      showAppSnackbar(
        context,
        text: AppLocalizations.of(context).authSwitchCheckFailed,
      );
      return false;
  }
}

class AccountSwitchDialog extends StatelessWidget {
  const AccountSwitchDialog({super.key, required this.queueSize});

  final int queueSize;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppDialog(
      icon: AppIcons.cloudOff,
      title: l10n.authSwitchTitle,
      message: l10n.authSwitchMessage(queueSize),
      primary: AppDialogAction(
        l10n.authSwitchConfirm,
        () => Navigator.of(context).pop(true),
        destructive: true,
      ),
      secondary: AppDialogAction(
        l10n.authSwitchCancel,
        () => Navigator.of(context).pop(false),
      ),
    );
  }
}
