import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../core/router.dart';
import '../../data/api/api_error_text.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/components/button.dart';
import '../../ui/components/fitting_text.dart';
import '../../ui/components/snackbar.dart';
import '../../ui/components/text_field.dart';
import '../../ui/icons/app_icon.dart';
import '../../ui/theme/app_text.dart';
import '../../ui/theme/app_theme.dart';
import 'auth_fields.dart';
import 'auth_service.dart';
import 'auth_widgets.dart';

final _log = Logger('auth');

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final TextEditingController _login = TextEditingController();
  final TextEditingController _code = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _repeat = TextEditingController();
  bool _submitted = false;
  bool _busy = false;
  RecoverFieldErrors _rejected = const {};

  @override
  void initState() {
    super.initState();
    _log.fine('forgot password screen opened');
  }

  @override
  void dispose() {
    _login.dispose();
    _code.dispose();
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  RecoverFieldErrors _validate() => validateRecoverForm(
    login: _login.text,
    code: _code.text,
    password: _password.text,
    repeat: _repeat.text,
  );

  void _changed(RecoverField field) {
    final rejected = _rejected[field];
    if (rejected != null) {
      _log.fine(
        'recover form: ${field.name} edited → clearing server error '
        '${rejected.code}',
      );
      _rejected = Map.of(_rejected)..remove(field);
    }
    setState(() {});
  }

  Future<void> _submit() async {
    if (_busy) {
      _log.fine('recover tap ignored: request in progress');
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
        'recover blocked by validation ${describeRecoverErrors(errors)}',
      );
      return;
    }
    setState(() => _busy = true);
    final outcome = await ref
        .read(authServiceProvider)
        .recover(
          login: _login.text,
          recoveryCode: _code.text,
          newPassword: _password.text,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    _show(outcome);
  }

  void _show(AuthOutcome outcome) {
    final l10n = AppLocalizations.of(context);
    switch (outcome) {
      case AuthSignedIn():
        _log.fine('recover done → waiting for the recovery code redirect');
      case AuthApiFailed(code: ApiErrorCode.badCredentials):
        setState(
          () => _rejected = {RecoverField.code: const AuthRecoveryRejected()},
        );
      case AuthApiFailed(:final validation?)
          when recoverFieldOfValidation(validation) != null:
        setState(
          () => _rejected = {
            recoverFieldOfValidation(validation)!: AuthInvalid(validation),
          },
        );
      case AuthApiFailed(:final error):
        showAppSnackbar(context, text: apiErrorText(l10n, error));
      case AuthNotSaved():
        showAppSnackbar(context, text: l10n.authSaveFailed);
    }
  }

  void _back() {
    if (context.canPop()) {
      _log.fine('auth stack: forgot password → back to login');
      context.pop();
      return;
    }
    _log.fine(
      'auth stack: forgot password closed with nothing under it → '
      '${AppRoutes.login}',
    );
    context.go(AppRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final media = MediaQuery.of(context);
    final local = _submitted
        ? _validate()
        : const <RecoverField, AuthFieldError>{};
    String? errorOf(RecoverField field) =>
        (local[field] ?? _rejected[field])?.text(l10n);

    return Scaffold(
      backgroundColor: colors.bgApp,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SafeArea(bottom: false, child: AuthBackBar(onBack: _back)),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                8,
                20,
                media.padding.bottom + 16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    header: true,
                    child: FittingText(
                      l10n.authForgotTitle,
                      style: AppText.titleL.copyWith(color: colors.textPrimary),
                    ),
                  ),
                  const SizedBox(height: authFormGap),
                  Text(
                    l10n.authForgotSubtitle,
                    style: AppText.bodyM.copyWith(color: colors.textSecondary),
                  ),
                  const SizedBox(height: authFormGap),
                  AppTextField(
                    label: l10n.authLoginLabel,
                    controller: _login,
                    icon: AppIcons.user,
                    errorText: errorOf(RecoverField.login),
                    keyboardType: TextInputType.visiblePassword,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => _changed(RecoverField.login),
                  ),
                  const SizedBox(height: authFormGap),
                  AppTextField(
                    label: l10n.authRecoveryCodeLabel,
                    controller: _code,
                    icon: AppIcons.link,
                    helperText: l10n.authRecoveryCodeHint,
                    errorText: errorOf(RecoverField.code),
                    keyboardType: TextInputType.visiblePassword,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => _changed(RecoverField.code),
                  ),
                  const SizedBox(height: authFormGap),
                  AppTextField(
                    label: l10n.authNewPasswordLabel,
                    controller: _password,
                    icon: AppIcons.lock,
                    password: true,
                    errorText: errorOf(RecoverField.password),
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => _changed(RecoverField.password),
                  ),
                  const SizedBox(height: authFormGap),
                  AppTextField(
                    label: l10n.authPasswordRepeatLabel,
                    placeholder: l10n.authNewPasswordRepeatPlaceholder,
                    controller: _repeat,
                    icon: AppIcons.lock,
                    password: true,
                    errorText: errorOf(RecoverField.repeat),
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => _changed(RecoverField.repeat),
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: authFormGap),
                  AppButton(
                    label: l10n.authChangePassword,
                    expand: true,
                    onPressed: _busy ? null : _submit,
                  ),
                  const SizedBox(height: authFormGap),
                  Text(
                    l10n.authForgotNote,
                    style: AppText.caption.copyWith(color: colors.textTertiary),
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
