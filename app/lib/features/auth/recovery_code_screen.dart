import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared/shared.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/components/button.dart';
import '../../ui/components/checkbox.dart';
import '../../ui/components/dialog.dart';
import '../../ui/components/fitting_text.dart';
import '../../ui/components/logo.dart';
import '../../ui/components/snackbar.dart';
import '../../ui/components/tap_target.dart';
import '../../ui/icons/app_icon.dart';
import '../../ui/theme/app_text.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/tokens/tokens.g.dart';
import 'recovery_code_state.dart';

final _log = Logger('auth');

const double recoveryCodeTitleOverhang = 12;

abstract interface class RecoveryCodeSharer {
  Future<ShareResult> share(String text);
}

final class SharePlusRecoveryCodeSharer implements RecoveryCodeSharer {
  const SharePlusRecoveryCodeSharer();

  @override
  Future<ShareResult> share(String text) =>
      SharePlus.instance.share(ShareParams(text: text));
}

final recoveryCodeSharerProvider = Provider<RecoveryCodeSharer>(
  (ref) => const SharePlusRecoveryCodeSharer(),
  name: 'recoveryCodeSharer',
);

String spellRecoveryCode(String code) =>
    code.split('-').map((group) => group.split('').join(' ')).join(', ');

class RecoveryCodeRoute extends ConsumerWidget {
  const RecoveryCodeRoute({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingRecoveryCodeProvider);
    if (pending == null) {
      return ColoredBox(color: context.colors.bgApp);
    }
    return RecoveryCodeScreen(
      key: ObjectKey(pending),
      code: pending.code,
      reason: pending.reason,
      onContinue: () =>
          ref.read(pendingRecoveryCodeProvider.notifier).confirm(),
    );
  }
}

class RecoveryCodeScreen extends ConsumerStatefulWidget {
  const RecoveryCodeScreen({
    super.key,
    required this.code,
    required this.reason,
    required this.onContinue,
  });

  final String code;
  final RecoveryCodeReason reason;
  final VoidCallback onContinue;

  @override
  ConsumerState<RecoveryCodeScreen> createState() => _RecoveryCodeScreenState();
}

class _RecoveryCodeScreenState extends ConsumerState<RecoveryCodeScreen> {
  bool _saved = false;
  bool _sharing = false;
  bool _reminding = false;

  String get _what => 'reason=${widget.reason.name}';

  @override
  void initState() {
    super.initState();
    _log.info('recovery code screen shown $_what (code is never logged)');
  }

  String _scrub(Object error) {
    var text = describeError(error);
    final normalized = normalizeRecoveryCode(widget.code);
    for (final secret in [widget.code, ?normalized]) {
      text = text.replaceAll(secret, maskRecoveryCode(secret));
    }
    return text;
  }

  Future<void> _copy() async {
    final l10n = AppLocalizations.of(context);
    final sw = Stopwatch()..start();
    try {
      await Clipboard.setData(ClipboardData(text: widget.code));
    } catch (e, st) {
      _log.warning(
        'recovery code copy failed $_what after ${sw.elapsedMilliseconds}ms, '
        'snackbar shown: ${_scrub(e)}',
        null,
        st,
      );
      if (mounted) showAppSnackbar(context, text: l10n.recoveryCodeCopyFailed);
      return;
    }
    _log.fine(
      'recovery code copied to the clipboard by user tap $_what '
      'in ${sw.elapsedMilliseconds}ms',
    );
    if (mounted) showAppSnackbar(context, text: l10n.recoveryCodeCopied);
  }

  Future<void> _share() async {
    if (_sharing) {
      _log.fine('recovery code share tap ignored: share sheet is opening');
      return;
    }
    final l10n = AppLocalizations.of(context);
    final sharer = ref.read(recoveryCodeSharerProvider);
    final sw = Stopwatch()..start();
    _sharing = true;
    _log.fine('recovery code share sheet opening $_what');
    try {
      final result = await sharer.share(
        l10n.recoveryCodeShareText(widget.code),
      );
      _log.fine(
        'recovery code share result=${result.status.name} '
        'target=${result.raw.isEmpty ? '-' : result.raw} $_what '
        'after ${sw.elapsedMilliseconds}ms',
      );
    } catch (e, st) {
      _log.warning(
        'recovery code share failed $_what after ${sw.elapsedMilliseconds}ms, '
        'snackbar shown: ${_scrub(e)}',
        null,
        st,
      );
      if (mounted) {
        showAppSnackbar(context, text: l10n.recoveryCodeShareFailed);
      }
    } finally {
      _sharing = false;
    }
  }

  void _toggle() {
    setState(() => _saved = !_saved);
    _log.fine(
      'recovery code "saved" checkbox → ${_saved ? 'checked' : 'unchecked'}: '
      'continue ${_saved ? 'enabled' : 'disabled'}',
    );
  }

  void _continue(String by) {
    _log.info('recovery code screen closed by $by $_what');
    widget.onContinue();
  }

  void _handlePop(bool didPop, Object? result) {
    if (didPop) return;
    if (_saved) {
      _continue('back gesture');
      return;
    }
    _remind();
  }

  Future<void> _remind() async {
    if (_reminding) return;
    _reminding = true;
    _log.fine(
      'back on recovery code screen before "saved" is checked → staying, '
      'reminder dialog shown $_what',
    );
    final l10n = AppLocalizations.of(context);
    await showAppDialog<void>(
      context,
      builder: (context) => AppDialog(
        title: l10n.recoveryCodeBackTitle,
        message: l10n.recoveryCodeBackMessage,
        primary: AppDialogAction(
          l10n.recoveryCodeBackOk,
          () => Navigator.of(context).pop(),
        ),
      ),
    );
    _reminding = false;
    _log.fine('recovery code reminder dialog closed $_what');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final media = MediaQuery.of(context);
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: _handlePop,
      child: Scaffold(
        backgroundColor: colors.bgApp,
        body: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            media.padding.top + 28,
            20,
            media.padding.bottom + 16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: AppLogo(size: 54),
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) => OverflowBox(
                  alignment: Alignment.centerLeft,
                  minWidth: constraints.maxWidth + recoveryCodeTitleOverhang,
                  maxWidth: constraints.maxWidth + recoveryCodeTitleOverhang,
                  fit: OverflowBoxFit.deferToChild,
                  child: Semantics(
                    header: true,
                    child: FittingText(
                      l10n.recoveryCodeTitle,
                      style: AppText.titleL.copyWith(color: colors.textPrimary),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.recoveryCodeText,
                style: AppText.bodyM.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: 16),
              _CodeCard(code: widget.code, onCopy: _copy, onShare: _share),
              const SizedBox(height: 8),
              _SavedRow(value: _saved, onToggle: _toggle),
              const SizedBox(height: 4),
              AppButton(
                label: l10n.recoveryCodeContinue,
                expand: true,
                onPressed: _saved ? () => _continue('continue button') : null,
              ),
              const SizedBox(height: 16),
              Text(
                l10n.recoveryCodeNote,
                style: AppText.caption.copyWith(color: colors.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({
    required this.code,
    required this.onCopy,
    required this.onShare,
  });

  final String code;
  final VoidCallback onCopy;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final mood = context.mood;
    final codeStyle = AppText.displayM.copyWith(
      color: mood.onSoft,
      letterSpacing: AppText.displayM.fontSize! * 0.06,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      decoration: BoxDecoration(
        color: mood.soft,
        borderRadius: BorderRadius.circular(RadiusTokens.xl),
      ),
      child: Column(
        children: [
          Text(
            l10n.recoveryCodeLabel,
            textAlign: TextAlign.center,
            style: AppText.labelS.copyWith(color: mood.onSoft),
          ),
          const SizedBox(height: 14),
          Semantics(
            label: l10n.a11yRecoveryCode(spellRecoveryCode(code)),
            excludeSemantics: true,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(code, maxLines: 1, softWrap: false, style: codeStyle),
            ),
          ),
          const SizedBox(height: 10),
          _CodeActions(onCopy: onCopy, onShare: onShare),
        ],
      ),
    );
  }
}

class _CodeActions extends StatelessWidget {
  const _CodeActions({required this.onCopy, required this.onShare});

  final VoidCallback onCopy;
  final VoidCallback onShare;

  static const double _gap = 8;
  static const double _sidePadding = 8;
  static const double _iconWithGap = 18 + 8;

  double _contentWidth(
    BuildContext context,
    String label, {
    required bool outline,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: DefaultTextStyle.of(context).style.merge(AppText.labelM),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return _iconWithGap + width + 2 * (_sidePadding + (outline ? 1.5 : 0));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final surface = context.colors.bgSurface;
    return LayoutBuilder(
      builder: (context, constraints) {
        final half = (constraints.maxWidth - _gap) / 2;
        final side =
            _contentWidth(context, l10n.recoveryCodeCopy, outline: false) <=
                half &&
            _contentWidth(context, l10n.recoveryCodeShare, outline: true) <=
                half;
        Widget copy({double? padding}) => AppButton(
          label: l10n.recoveryCodeCopy,
          icon: AppIcons.copy,
          size: AppButtonSize.m,
          expand: true,
          horizontalPadding: padding,
          onPressed: onCopy,
        );
        Widget share({double? padding}) => AppButton(
          label: l10n.recoveryCodeShare,
          icon: AppIcons.share,
          type: AppButtonType.outline,
          size: AppButtonSize.m,
          expand: true,
          background: surface,
          horizontalPadding: padding,
          onPressed: onShare,
        );
        if (side) {
          return Row(
            children: [
              Expanded(child: copy(padding: _sidePadding)),
              const SizedBox(width: _gap),
              Expanded(child: share(padding: _sidePadding)),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            copy(),
            SizedBox(height: _gap - (kMinTapTarget - 40)),
            share(),
          ],
        );
      },
    );
  }
}

class _SavedRow extends StatelessWidget {
  const _SavedRow({required this.value, required this.onToggle});

  final bool value;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      container: true,
      checked: value,
      label: l10n.recoveryCodeSaved,
      onTap: onToggle,
      excludeSemantics: true,
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(RadiusTokens.sm),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kMinTapTarget),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 24,
                child: AppCheckbox(value: value, onChanged: (_) => onToggle()),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.recoveryCodeSaved,
                  style: AppText.bodyM.copyWith(
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
