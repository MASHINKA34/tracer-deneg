import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../core/router.dart';
import '../../core/web_links.dart';
import '../../data/api/api_error_text.dart';
import '../../data/api/api_exception.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/components/button.dart';
import '../../ui/components/snackbar.dart';
import '../../ui/components/text_field.dart';
import '../../ui/icons/app_icon.dart';
import '../../ui/theme/app_text.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/tokens/tokens.g.dart';
import '../auth/account_delete_service.dart';
import '../auth/auth_fields.dart';
import '../categories/categories_top_bar.dart';

final _log = Logger('profile');

final _nav = Logger('nav');

class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final TextEditingController _password = TextEditingController();
  bool _submitted = false;
  bool _busy = false;
  bool _wrongPassword = false;

  @override
  void initState() {
    super.initState();
    _log.fine('delete account screen opened');
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  ValidationError? _validate() => validatePassword(_password.text);

  void _changed() {
    if (_wrongPassword) {
      _log.fine(
        'delete account: password edited → clearing server error '
        '${ApiErrorCode.badCredentials.code}',
      );
      _wrongPassword = false;
    }
    setState(() {});
  }

  void _keyboardDone() {
    _log.fine(
      'delete account: keyboard "done" only closes the keyboard, deletion '
      'needs the button',
    );
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Future<void> _submit() async {
    if (_busy) {
      _log.fine('delete account tap ignored: request in progress');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final invalid = _validate();
    setState(() {
      _submitted = true;
      _wrongPassword = false;
    });
    if (invalid != null) {
      _log.fine('delete account blocked by validation ${invalid.code}');
      return;
    }
    setState(() => _busy = true);
    final outcome = await ref
        .read(accountDeleteServiceProvider)
        .deleteAccount(password: _password.text);
    if (!mounted) {
      _log.fine(
        'delete account screen already closed by the sign-in redirect after '
        '${outcome.runtimeType}',
      );
      return;
    }
    setState(() => _busy = false);
    final l10n = AppLocalizations.of(context);
    switch (outcome) {
      case AccountDeleted():
        _nav.fine(
          'delete account done, sign-in not forced by the gate → '
          '${AppRoutes.login}',
        );
        context.go(AppRoutes.login);
      case AccountDeleteFailed(code: ApiErrorCode.badCredentials):
        setState(() => _wrongPassword = true);
      case AccountDeleteFailed(error: final ApiException error):
        showAppSnackbar(context, text: apiErrorText(l10n, error));
      case AccountDeleteFailed():
        showAppSnackbar(context, text: l10n.deleteAccountFailed);
    }
  }

  void _back(String how) {
    if (_busy) {
      _log.fine('delete account $how ignored: request in progress');
      return;
    }
    if (context.canPop()) {
      _nav.fine('delete account closed by $how, nothing deleted');
      context.pop();
      return;
    }
    _nav.fine(
      'delete account closed by $how with nothing under it → '
      '${AppRoutes.profile}',
    );
    context.go(AppRoutes.profile);
  }

  Future<void> _openLink(WebPage page) async {
    final opened = await ref
        .read(webLinksProvider)
        .open(page, from: WebLinkSource.deleteAccount);
    if (!mounted || opened) return;
    showAppSnackbar(context, text: AppLocalizations.of(context).linkOpenFailed);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final invalid = _submitted ? _validate() : null;
    final errorText = invalid != null
        ? authValidationText(l10n, invalid)
        : _wrongPassword
        ? l10n.deleteAccountWrongPassword
        : null;
    return PopScope(
      canPop: !_busy,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _log.fine('delete account: system back ignored, request in progress');
        }
      },
      child: Scaffold(
        backgroundColor: colors.bgApp,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SafeArea(
              bottom: false,
              child: CategoriesTopBar(
                title: l10n.deleteAccountTitle,
                onBack: () => _back('back button'),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  20,
                  8,
                  20,
                  16 + MediaQuery.paddingOf(context).bottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Warning(),
                    const SizedBox(height: 16),
                    AppTextField(
                      label: l10n.deleteAccountPasswordLabel,
                      controller: _password,
                      icon: AppIcons.lock,
                      password: true,
                      autofocus: true,
                      errorText: errorText,
                      textInputAction: TextInputAction.done,
                      onChanged: (_) => _changed(),
                      onSubmitted: (_) => _keyboardDone(),
                    ),
                    const SizedBox(height: 16),
                    AppButton(
                      label: l10n.deleteAccountConfirm,
                      type: AppButtonType.danger,
                      expand: true,
                      onPressed: _busy ? null : _submit,
                    ),
                    const SizedBox(height: 16),
                    AppButton(
                      label: l10n.deleteAccountCancel,
                      type: AppButtonType.text,
                      expand: true,
                      onPressed: _busy
                          ? null
                          : () => _back('"changed my mind"'),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.deleteAccountNote,
                      style: AppText.caption.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final (page, label) in [
                      (WebPage.deleteAccount, l10n.linkDeleteAccountPage),
                      (WebPage.privacy, l10n.linkPrivacy),
                    ])
                      Semantics(
                        link: true,
                        label: l10n.a11yWebLink(label),
                        excludeSemantics: true,
                        onTap: () => _openLink(page),
                        child: AppButton(
                          label: label,
                          type: AppButtonType.text,
                          size: AppButtonSize.m,
                          expand: true,
                          onPressed: () => _openLink(page),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final point = AppText.bodyM.copyWith(color: colors.textPrimary);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: BorderRadius.circular(RadiusTokens.lg),
        border: Border.all(color: colors.statusDanger, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppIcon(
                AppIcons.alertCircle,
                size: 22,
                color: colors.statusDanger,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    l10n.deleteAccountWarning,
                    style: AppText.titleS.copyWith(color: colors.statusDanger),
                  ),
                ),
              ),
            ],
          ),
          for (final text in [
            l10n.deleteAccountPointData,
            l10n.deleteAccountPointShared,
            l10n.deleteAccountPointLogin,
          ]) ...[
            const SizedBox(height: 10),
            Semantics(
              label: text,
              excludeSemantics: true,
              child: Text('•  $text', style: point),
            ),
          ],
        ],
      ),
    );
  }
}
