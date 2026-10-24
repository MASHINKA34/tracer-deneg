import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../core/router.dart';
import '../../data/api/api_error_text.dart';
import '../../data/api/api_exception.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/components/button.dart';
import '../../ui/components/fitting_text.dart';
import '../../ui/components/snackbar.dart';
import '../../ui/components/text_field.dart';
import '../../ui/icons/app_icon.dart';
import '../../ui/theme/app_text.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/tokens/tokens.g.dart';
import '../categories/categories_top_bar.dart';
import 'budget_join_service.dart';
import 'invite_code_input.dart';

final _log = Logger('budgets');

final _nav = Logger('nav');

enum JoinCodeError { empty, incomplete, notFound }

JoinCodeError? localJoinCodeError(String text) {
  if (completeInviteCode(text) != null) return null;
  return inviteCodeBodyLength(text) == 0
      ? JoinCodeError.empty
      : JoinCodeError.incomplete;
}

String joinCodeErrorText(AppLocalizations l10n, JoinCodeError error) =>
    switch (error) {
      JoinCodeError.empty => l10n.joinBudgetCodeEmpty,
      JoinCodeError.incomplete => l10n.joinBudgetCodeIncomplete,
      JoinCodeError.notFound => l10n.joinBudgetCodeNotFound,
    };

String budgetJoinFailureText(AppLocalizations l10n, BudgetJoinFailed failure) =>
    switch (failure) {
      BudgetJoinFailed(stage: BudgetJoinStage.select) =>
        l10n.budgetSwitcherFailed,
      BudgetJoinFailed(stage: BudgetJoinStage.pull) => l10n.joinBudgetNotLoaded,
      BudgetJoinFailed(offline: true) => l10n.joinBudgetOffline,
      BudgetJoinFailed(error: final ApiException e) => apiErrorText(l10n, e),
      BudgetJoinFailed() => l10n.joinBudgetFailed,
    };

class JoinBudgetScreen extends ConsumerStatefulWidget {
  const JoinBudgetScreen({super.key});

  @override
  ConsumerState<JoinBudgetScreen> createState() => _JoinBudgetScreenState();
}

class _JoinBudgetScreenState extends ConsumerState<JoinBudgetScreen> {
  final TextEditingController _code = TextEditingController();
  JoinCodeError? _error;
  bool _busy = false;
  String _closedBy = 'back';

  @override
  void initState() {
    super.initState();
    _log.fine('join budget screen opened');
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _codeChanged(String text) {
    final shown = _error;
    if (shown != null) {
      _log.fine(
        'join code edited after ${shown.name} → error under the field '
        'cleared',
      );
    }
    _log.fine(
      'join code changed chars=${inviteCodeBodyLength(text)}/'
      '$inviteCodeLength complete=${completeInviteCode(text) != null}',
    );
    setState(() => _error = null);
  }

  Future<void> _join() async {
    if (_busy) {
      _log.fine('join budget tap ignored: request in progress');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final text = _code.text;
    final code = completeInviteCode(text);
    if (code == null) {
      final error = localJoinCodeError(text)!;
      setState(() => _error = error);
      _log.info(
        'budget join blocked: code ${error.name} '
        'chars=${inviteCodeBodyLength(text)}/$inviteCodeLength, error shown '
        'under the code field, no request',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final outcome = await ref.read(budgetJoinServiceProvider).join(code: code);
    if (!mounted) {
      _log.fine(
        'join budget screen closed before the result $outcome → nothing '
        'more to show',
      );
      return;
    }
    setState(() => _busy = false);
    switch (outcome) {
      case BudgetJoined(:final budgetId):
        _closedBy = 'join';
        _nav.fine(
          'join budget budgetId=$budgetId joined and selected → '
          '${AppRoutes.month}',
        );
        context.go(AppRoutes.month);
      case final BudgetJoinFailed failure when failure.inviteNotFound:
        _log.fine(
          'join budget: invite_not_found → error under the code field, code '
          'kept for editing',
        );
        setState(() => _error = JoinCodeError.notFound);
      case final BudgetJoinFailed failure:
        _log.fine(
          'join budget failed stage=${failure.stage.name} → snackbar, code '
          'kept',
        );
        showAppSnackbar(
          context,
          text: budgetJoinFailureText(AppLocalizations.of(context), failure),
        );
    }
  }

  void _leave(String reason) {
    _closedBy = reason;
    if (context.canPop()) {
      context.pop();
      return;
    }
    _nav.fine(
      'join budget closed by $reason with nothing under it → '
      '${AppRoutes.month}',
    );
    context.go(AppRoutes.month);
  }

  void _handlePop(bool didPop, Object? result) {
    if (!didPop) return;
    _nav.fine(
      'join budget closed by $_closedBy${_busy ? ' while joining' : ''}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final mood = context.mood;
    final error = _error;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return PopScope<Object?>(
      onPopInvokedWithResult: _handlePop,
      child: Scaffold(
        backgroundColor: colors.bgApp,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SafeArea(
              bottom: false,
              child: CategoriesTopBar(
                title: l10n.joinBudgetTitle,
                onBack: () => _leave('back button'),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottom),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: ExcludeSemantics(
                        child: Container(
                          width: 64,
                          height: 64,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: mood.soft,
                            borderRadius: BorderRadius.circular(
                              RadiusTokens.lg,
                            ),
                          ),
                          child: AppIcon(
                            AppIcons.link,
                            size: 28,
                            color: mood.accentStrong,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Semantics(
                      header: true,
                      child: FittingText(
                        l10n.joinBudgetHeading,
                        style: AppText.titleL.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.joinBudgetSubtitle,
                      style: AppText.bodyM.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    AppTextField(
                      label: l10n.joinBudgetCode,
                      placeholder: l10n.joinBudgetCodePlaceholder,
                      controller: _code,
                      errorText: error == null
                          ? null
                          : joinCodeErrorText(l10n, error),
                      keyboardType: TextInputType.visiblePassword,
                      textInputAction: TextInputAction.done,
                      inputFormatters: const [InviteCodeFormatter()],
                      onChanged: _codeChanged,
                      onSubmitted: (_) => _join(),
                    ),
                    const SizedBox(height: 16),
                    AppButton(
                      label: l10n.joinBudgetSubmit,
                      expand: true,
                      onPressed: _busy ? null : _join,
                    ),
                    if (error == null) ...[
                      const SizedBox(height: 16),
                      Text(
                        l10n.joinBudgetHint,
                        style: AppText.caption.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                    ],
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
