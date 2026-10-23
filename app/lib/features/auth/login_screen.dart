import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../core/router.dart';
import '../../data/api/api_error_text.dart';
import '../../data/session/session_providers.dart';
import '../../data/session/session_state.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/components/button.dart';
import '../../ui/components/fitting_text.dart';
import '../../ui/components/snackbar.dart';
import '../../ui/components/text_field.dart';
import '../../ui/icons/app_icon.dart';
import '../../ui/theme/app_text.dart';
import '../../ui/theme/app_theme.dart';
import 'account_switch_dialog.dart';
import 'auth_fields.dart';
import 'auth_service.dart';
import 'auth_widgets.dart';
import 'sign_in_notice.dart';

final _log = Logger('auth');

const List<AuthField> _fields = [AuthField.login, AuthField.password];

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final TextEditingController _login = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final FocusNode _passwordFocus = FocusNode();
  bool _submitted = false;
  bool _busy = false;
  AuthFieldErrors _rejected = const {};

  @override
  void initState() {
    super.initState();
    final session = ref.read(sessionProvider);
    if (session is SessionEnded) {
      _log.info(
        'login screen opened after session end reason=${session.reason.name} '
        'userId=${session.user.userId} → "session ended" notice shown, '
        'local data kept',
      );
    } else {
      _log.fine('login screen opened');
    }
    ref.listenManual(
      signInNoticeProvider,
      (previous, next) => _onNotice(next),
      fireImmediately: true,
    );
  }

  void _onNotice(SignInNotice? notice) {
    if (notice == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _log.fine('sign-in notice ${notice.name} left: login screen closed');
        return;
      }
      final taken = ref.read(signInNoticeProvider.notifier).take();
      if (taken == null) return;
      final l10n = AppLocalizations.of(context);
      switch (taken) {
        case SignInNotice.accountDeleted:
          _log.info(
            'login screen after account deletion → "account deleted" snackbar',
          );
          showAppSnackbar(context, text: l10n.accountDeletedSnackbar);
      }
    });
  }

  @override
  void dispose() {
    _login.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  AuthFieldErrors get _local => _submitted
      ? validateLoginForm(login: _login.text, password: _password.text)
      : const {};

  void _changed(AuthField field) {
    if (_rejected.isNotEmpty) {
      _log.fine(
        'login form: ${field.name} edited → clearing server error '
        '${_rejected.values.join(',')}',
      );
      _rejected = const {};
    }
    setState(() {});
  }

  Future<void> _submit() async {
    if (_busy) {
      _log.fine('login tap ignored: request in progress');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final errors = validateLoginForm(
      login: _login.text,
      password: _password.text,
    );
    setState(() {
      _submitted = true;
      _rejected = const {};
    });
    if (errors.isNotEmpty) {
      _log.fine(
        'login blocked by validation '
        '${describeFieldErrors(errors, _fields)}',
      );
      return;
    }
    setState(() => _busy = true);
    final proceed = await confirmSignIn(
      context,
      ref,
      action: AuthAction.login,
      login: _login.text,
    );
    if (!mounted) return;
    if (!proceed) {
      setState(() => _busy = false);
      return;
    }
    final outcome = await ref
        .read(authServiceProvider)
        .login(login: _login.text, password: _password.text);
    if (!mounted) return;
    setState(() => _busy = false);
    _show(outcome);
  }

  void _show(AuthOutcome outcome) {
    final l10n = AppLocalizations.of(context);
    switch (outcome) {
      case AuthSignedIn():
        _log.fine('login done → waiting for the sign-in redirect');
      case AuthApiFailed(code: ApiErrorCode.badCredentials):
        setState(
          () => _rejected = {
            AuthField.password: const AuthRejected(ApiErrorCode.badCredentials),
          },
        );
      case AuthApiFailed(:final validation?)
          when _fields.contains(fieldOfValidation(validation)):
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

  void _openRegister() {
    _log.fine('auth stack: login → ${AppRoutes.register}');
    context.push(AppRoutes.register);
  }

  void _openForgot() {
    _log.fine('auth stack: login → ${AppRoutes.forgotPassword}');
    context.push(AppRoutes.forgotPassword);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final media = MediaQuery.of(context);
    final local = _local;
    final ended = ref.watch(sessionProvider.select((s) => s is SessionEnded));
    String? errorOf(AuthField field) =>
        (local[field] ?? _rejected[field])?.text(l10n);

    return Scaffold(
      backgroundColor: colors.bgApp,
      body: SingleChildScrollView(
        padding: EdgeInsets.only(
          top: media.padding.top + 8,
          bottom: media.padding.bottom + 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: AuthHero(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 26, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    header: true,
                    child: FittingText(
                      l10n.authLoginTitle,
                      style: AppText.titleL.copyWith(color: colors.textPrimary),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    ended ? l10n.authSessionEnded : l10n.authLoginSubtitle,
                    style: AppText.bodyM.copyWith(color: colors.textSecondary),
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
                    onSubmitted: (_) => _passwordFocus.requestFocus(),
                  ),
                  const SizedBox(height: authFormGap),
                  AppTextField(
                    label: l10n.authPasswordLabel,
                    controller: _password,
                    focusNode: _passwordFocus,
                    icon: AppIcons.lock,
                    password: true,
                    errorText: errorOf(AuthField.password),
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => _changed(AuthField.password),
                    onSubmitted: (_) => _submit(),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: AuthTextLink(
                      label: l10n.authForgotPassword,
                      onTap: _openForgot,
                      top: authFormGap,
                      bottom: 16,
                    ),
                  ),
                  const SizedBox(height: 16),
                  AppButton(
                    label: l10n.authSignIn,
                    expand: true,
                    onPressed: _busy ? null : _submit,
                  ),
                  AuthSwitchRow(
                    question: l10n.authNoAccount,
                    action: l10n.authRegisterLink,
                    onTap: _openRegister,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
