import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../data/api/api_error_text.dart';
import '../../data/api/api_exception.dart';
import '../../data/sync/sync_service.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/components/dialog.dart';
import '../../ui/icons/app_icon.dart';
import '../auth/sign_out_service.dart';

final _log = Logger('auth');

Future<bool?> showSignOutDialog(
  BuildContext context, {
  required int queueSize,
}) => showAppDialog<bool>(
  context,
  builder: (context) => SignOutDialog(queueSize: queueSize),
);

enum _Phase { idle, syncing, signingOut }

class SignOutDialog extends ConsumerStatefulWidget {
  const SignOutDialog({super.key, required this.queueSize});

  final int queueSize;

  @override
  ConsumerState<SignOutDialog> createState() => _SignOutDialogState();
}

class _SignOutDialogState extends ConsumerState<SignOutDialog> {
  late int _queue = widget.queueSize;
  _Phase _phase = _Phase.idle;
  String? _error;
  SignOutChoice? _choice;

  bool get _busy => _phase != _Phase.idle;

  SignOutService get _service => ref.read(signOutServiceProvider);

  void _cancel() {
    if (_busy) return;
    _service.dialogClosed(queueSize: _queue, cancelled: true);
    Navigator.of(context).pop(false);
  }

  Future<void> _sync() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _phase = _Phase.syncing;
      _choice = SignOutChoice.sync;
    });
    final result = await _service.syncFirst(queueSize: _queue);
    if (!mounted) {
      _log.fine('sign-out dialog closed while syncing → result not shown');
      return;
    }
    switch (result) {
      case SyncNowDone():
        await _signOut(SignOutChoice.sync);
      case SyncNowFailed(:final remaining, :final error):
        setState(() {
          _phase = _Phase.idle;
          if (remaining > 0) _queue = remaining;
          _error = l10n.signOutSyncFailed(switch (error) {
            null => l10n.signOutSyncIncomplete,
            final ApiException e => apiErrorText(l10n, e),
            _ => l10n.signOutSyncError,
          });
        });
    }
  }

  Future<void> _signOut(SignOutChoice choice) async {
    if (_phase == _Phase.signingOut) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _phase = _Phase.signingOut;
      _choice = choice;
    });
    final outcome = await _service.signOut(choice: choice, queueSize: _queue);
    if (!mounted) {
      _log.fine(
        'sign-out dialog already closed by navigation after '
        '${outcome.runtimeType}',
      );
      return;
    }
    switch (outcome) {
      case SignedOut():
        Navigator.of(context).pop(true);
      case SignOutFailed():
        setState(() {
          _phase = _Phase.idle;
          _error = l10n.signOutFailed;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final signingOut = _phase == _Phase.signingOut;
    final Widget dialog;
    if (_queue == 0) {
      dialog = AppDialog(
        title: l10n.signOutTitle,
        message: _error ?? l10n.signOutMessage,
        primary: AppDialogAction(
          signingOut ? l10n.signOutProgress : l10n.signOutConfirm,
          _busy ? null : () => _signOut(SignOutChoice.confirm),
          destructive: true,
        ),
        secondary: AppDialogAction(l10n.signOutCancel, _busy ? null : _cancel),
      );
    } else {
      final syncing = _phase == _Phase.syncing;
      final viaSync = _choice == SignOutChoice.sync;
      dialog = AppDialog(
        icon: AppIcons.cloudOff,
        title: l10n.signOutUnsyncedTitle(_queue),
        message: _error ?? l10n.signOutUnsyncedMessage,
        primary: AppDialogAction(
          syncing
              ? l10n.syncSending
              : signingOut && viaSync
              ? l10n.signOutProgress
              : l10n.signOutSync,
          _busy ? null : _sync,
        ),
        secondary: AppDialogAction(
          signingOut && !viaSync ? l10n.signOutProgress : l10n.signOutDiscard,
          _busy ? null : () => _signOut(SignOutChoice.discard),
          destructive: true,
        ),
      );
    }
    return PopScope(
      canPop: !_busy,
      onPopInvokedWithResult: (didPop, result) {
        if (_busy && !didPop) {
          _log.fine(
            'sign-out dialog: back or tap outside ignored while '
            '${_phase.name}',
          );
          return;
        }
        if (didPop && result == null && !_busy) {
          _service.dialogClosed(queueSize: _queue, cancelled: false);
        }
      },
      child: dialog,
    );
  }
}
