import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../core/router.dart';
import '../../core/web_links.dart';
import '../../data/api/api_error_text.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/components/button.dart';
import '../../ui/components/fitting_text.dart';
import '../../ui/components/logo.dart';
import '../../ui/components/snackbar.dart';
import '../../ui/components/text_field.dart';
import '../../ui/icons/app_icon.dart';
import '../../ui/theme/app_text.dart';
import '../../ui/theme/app_theme.dart';
import 'account_switch_dialog.dart';
import 'auth_fields.dart';
import 'auth_service.dart';
import 'auth_widgets.dart';

final _log = Logger('auth');

const List<AuthField> _fields = AuthField.values;

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _login = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _repeat = TextEditingController();
  bool _submitted = false;
  bool _busy = false;
  AuthFieldErrors _rejected = const {};

  @override
  void initState() {
    super.initState();
    _log.fine('register screen opened');
  }

  @override
  void dispose() {
    _name.dispose();
    _login.dispose();
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  AuthFieldErrors _validate() => validateRegisterForm(
    name: _name.text,
    login: _login.text,
    password: _password.text,
    repeat: _repeat.text,
  );

  void _changed(AuthField field) {
    final rejected = _rejected[field];
    if (rejected != null) {
      _log.fine(
        'register form: ${field.name} edited → clearing server error '
        '${rejected.code}',
      );
      _rejected = Map.of(_rejected)..remove(field);
    }
    setState(() {});
  }

  Future<void> _submit() async {
    if (_busy) {
      _log.fine('register tap ignored: request in progress');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final errors = _validate();
    setState(() {
      _submitted = true;
      _rejected = const {};
    });
    if (errors.isNotEmpty) {
      _log.fine(
        'register blocked by validation ${describeFieldErrors(errors, _fields)}',
      );
      return;
    }
    setState(() => _busy = true);
    final proceed = await confirmSignIn(
      context,
      ref,
      action: AuthAction.register,
      login: _login.text,
    );
    if (!mounted) return;
    if (!proceed) {
      setState(() => _busy = false);
      return;
    }
    final outcome = await ref
        .read(authServiceProvider)
        .register(
          displayName: _name.text,
          login: _login.text,
          password: _password.text,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    _show(outcome);
  }

  void _show(AuthOutcome outcome) {
    final l10n = AppLocalizations.of(context);
    switch (outcome) {
      case AuthSignedIn():
        _log.fine('register done → waiting for the sign-in redirect');
      case AuthApiFailed(code: ApiErrorCode.loginTaken):
        setState(
          () => _rejected = {
            AuthField.login: const AuthRejected(ApiErrorCode.loginTaken),
          },
        );
      case AuthApiFailed(:final validation?)
          when fieldOfValidation(validation) != null:
        setState(
          () => _rejected = {
            fieldOfValidation(validation)!: AuthInvalid(validation),
          },
        );
      case AuthApiFailed(:final error):
        showAppSnackbar(context, text: apiErrorText(l10n, error));
      case AuthNotSaved():
        showAppSnackbar(context, text: l10n.authSaveFailed);
    }
  }

  void _back(String reason) {
    if (context.canPop()) {
      _log.fine('auth stack: register → back to login by $reason');
      context.pop();
      return;
    }
    _log.fine(
      'auth stack: register closed by $reason with nothing under it → '
      '${AppRoutes.login}',
    );
    context.go(AppRoutes.login);
  }

  Future<void> _openPrivacy() async {
    final opened = await ref
        .read(webLinksProvider)
        .open(WebPage.privacy, from: WebLinkSource.register);
    if (!mounted || opened) return;
    showAppSnackbar(context, text: AppLocalizations.of(context).linkOpenFailed);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final media = MediaQuery.of(context);
    final local = _submitted
        ? _validate()
        : const <AuthField, AuthFieldError>{};
    String? errorOf(AuthField field) =>
        (local[field] ?? _rejected[field])?.text(l10n);

    return Scaffold(
      backgroundColor: colors.bgApp,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SafeArea(
            bottom: false,
            child: AuthBackBar(onBack: () => _back('back button')),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                4,
                20,
                media.padding.bottom + 16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const AppLogo(size: 54),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Semantics(
                              header: true,
                              child: FittingText(
                                l10n.authRegisterTitle,
                                style: AppText.titleL.copyWith(
                                  color: colors.textPrimary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              l10n.authRegisterSubtitle,
                              style: AppText.bodyM.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: authFormGap),
                  AuthNote(text: l10n.authRegisterNote),
                  const SizedBox(height: authFormGap),
                  AppTextField(
                    label: l10n.authNameLabel,
                    controller: _name,
                    icon: AppIcons.user,
                    errorText: errorOf(AuthField.name),
                    keyboardType: TextInputType.name,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => _changed(AuthField.name),
                  ),
                  const SizedBox(height: authFormGap),
                  AppTextField(
                    label: l10n.authLoginLabel,
                    controller: _login,
                    icon: AppIcons.user,
                    errorText: errorOf(AuthField.login),
                    keyboardType: TextInputType.visiblePassword,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => _changed(AuthField.login),
                  ),
                  const SizedBox(height: authFormGap),
                  AppTextField(
                    label: l10n.authPasswordLabel,
                    controller: _password,
                    icon: AppIcons.lock,
                    password: true,
                    helperText: l10n.authPasswordHint(passwordMinLength),
                    errorText: errorOf(AuthField.password),
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => _changed(AuthField.password),
                  ),
                  const SizedBox(height: authFormGap),
                  AppTextField(
                    label: l10n.authPasswordRepeatLabel,
                    controller: _repeat,
                    icon: AppIcons.lock,
                    password: true,
                    errorText: errorOf(AuthField.repeat),
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => _changed(AuthField.repeat),
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: authFormGap),
                  AppButton(
                    label: l10n.authCreateAccount,
                    expand: true,
                    onPressed: _busy ? null : _submit,
                  ),
                  AuthSwitchRow(
                    question: l10n.authHaveAccount,
                    action: l10n.authSignIn,
                    onTap: () => _back('sign-in link'),
                  ),
                  Semantics(
                    link: true,
                    label: l10n.a11yWebLink(l10n.linkPrivacy),
                    excludeSemantics: true,
                    onTap: _openPrivacy,
                    child: AppButton(
                      label: l10n.linkPrivacy,
                      type: AppButtonType.text,
                      size: AppButtonSize.m,
                      expand: true,
                      onPressed: _openPrivacy,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
