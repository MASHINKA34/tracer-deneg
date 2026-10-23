import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../core/router.dart';
import '../../data/api/api_error_text.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/components/button.dart';
import '../../ui/components/snackbar.dart';
import '../../ui/components/text_field.dart';
import '../../ui/icons/app_icon.dart';
import '../../ui/theme/app_text.dart';
import '../../ui/theme/app_theme.dart';
import '../auth/auth_fields.dart';
import '../categories/categories_top_bar.dart';
import 'recovery_code_reissue.dart';

final _log = Logger('profile');

final _nav = Logger('nav');

class RecoveryCodeReissueScreen extends ConsumerStatefulWidget {
  const RecoveryCodeReissueScreen({super.key});

  @override
  ConsumerState<RecoveryCodeReissueScreen> createState() =>
      _RecoveryCodeReissueScreenState();
}

class _RecoveryCodeReissueScreenState
    extends ConsumerState<RecoveryCodeReissueScreen> {
  final TextEditingController _password = TextEditingController();
  bool _submitted = false;
  bool _busy = false;
  bool _wrongPassword = false;

  @override
  void initState() {
    super.initState();
    _log.fine('recovery code reissue screen opened');
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
        'recovery code reissue: password edited → clearing server error '
        '${ApiErrorCode.badCredentials.code}',
      );
      _wrongPassword = false;
    }
    setState(() {});
  }

  Future<void> _submit() async {
    if (_busy) {
      _log.fine('recovery code reissue tap ignored: request in progress');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final invalid = _validate();
    setState(() {
      _submitted = true;
      _wrongPassword = false;
    });
    if (invalid != null) {
      _log.fine('recovery code reissue blocked by validation ${invalid.code}');
      return;
    }
    setState(() => _busy = true);
    final outcome = await ref
        .read(recoveryCodeReissueProvider)
        .reissue(password: _password.text);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (outcome) {
      case ReissueDone(:final requestId):
        _log.fine(
          'recovery code reissue done rid=$requestId → waiting for the '
          'recovery code redirect',
        );
      case ReissueFailed(code: ApiErrorCode.badCredentials):
        setState(() => _wrongPassword = true);
      case ReissueFailed(:final error):
        showAppSnackbar(
          context,
          text: apiErrorText(AppLocalizations.of(context), error),
        );
    }
  }

  void _back() {
    if (context.canPop()) {
      _nav.fine('recovery code reissue closed by back button');
      context.pop();
      return;
    }
    _nav.fine(
      'recovery code reissue closed with nothing under it → '
      '${AppRoutes.profile}',
    );
    context.go(AppRoutes.profile);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final invalid = _submitted ? _validate() : null;
    final errorText = invalid != null
        ? authValidationText(l10n, invalid)
        : _wrongPassword
        ? l10n.recoveryReissueWrongPassword
        : null;
    return Scaffold(
      backgroundColor: colors.bgApp,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SafeArea(
            bottom: false,
            child: CategoriesTopBar(
              title: l10n.recoveryReissueTitle,
              onBack: _back,
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
                  Text(
                    l10n.recoveryReissueText,
                    style: AppText.bodyM.copyWith(color: colors.textSecondary),
                  ),
                  const SizedBox(height: 20),
                  AppTextField(
                    label: l10n.recoveryReissuePasswordLabel,
                    controller: _password,
                    icon: AppIcons.lock,
                    password: true,
                    autofocus: true,
                    errorText: errorText,
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => _changed(),
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 16),
                  AppButton(
                    label: l10n.recoveryReissueButton,
                    expand: true,
                    onPressed: _busy ? null : _submit,
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
