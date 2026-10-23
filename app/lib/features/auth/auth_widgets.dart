import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/components/fitting_text.dart';
import '../../ui/components/logo.dart';
import '../../ui/components/tap_target.dart';
import '../../ui/decor/decor_painter.dart';
import '../../ui/icons/app_icon.dart';
import '../../ui/theme/app_text.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/tokens/tokens.g.dart';

const double authHeroHeight = 300;

const double authHeroDecorHeight = 421;

const double authFormGap = 14;

class AuthHero extends StatelessWidget {
  const AuthHero({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final mood = context.mood;
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: mood.soft,
        borderRadius: BorderRadius.circular(RadiusTokens.xl),
        boxShadow: ShadowTokens.card,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(RadiusTokens.xl),
        child: Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _HeroDecorPainter(
                    DecorPainter(
                      mood: mood.mood,
                      brightness: theme.brightness,
                      cornerRadius: RadiusTokens.xl,
                    ),
                  ),
                ),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: authHeroHeight,
                minWidth: double.infinity,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 24,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const AppLogo(),
                    const SizedBox(height: 10),
                    Semantics(
                      header: true,
                      child: FittingText(
                        l10n.appTitle,
                        textAlign: TextAlign.center,
                        style: AppText.displayL.copyWith(color: mood.onSoft),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      l10n.authSlogan,
                      textAlign: TextAlign.center,
                      style: AppText.bodyM.copyWith(color: mood.onSoft),
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

class _HeroDecorPainter extends CustomPainter {
  _HeroDecorPainter(this.decor);

  final DecorPainter decor;

  @override
  void paint(Canvas canvas, Size size) => decor.paint(
    canvas,
    Size(size.width, math.max(size.height, authHeroDecorHeight)),
  );

  @override
  bool shouldRepaint(_HeroDecorPainter oldDelegate) =>
      decor.shouldRepaint(oldDelegate.decor);
}

class AuthBackBar extends StatelessWidget {
  const AuthBackBar({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Semantics(
            button: true,
            label: l10n.a11yBack,
            excludeSemantics: true,
            onTap: onBack,
            child: InkResponse(
              radius: 22,
              onTap: onBack,
              child: SizedBox.square(
                dimension: kMinTapTarget,
                child: Center(
                  child: AppIcon(
                    AppIcons.arrowLeft,
                    size: 24,
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AuthTextLink extends StatelessWidget {
  const AuthTextLink({
    super.key,
    required this.label,
    required this.onTap,
    this.top = 0,
    this.bottom = 0,
  });

  final String label;
  final VoidCallback onTap;
  final double top;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(RadiusTokens.xs),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: kMinTapTarget),
          child: Padding(
            padding: EdgeInsets.only(top: top, bottom: bottom),
            child: FittingText(
              label,
              textAlign: TextAlign.center,
              style: AppText.labelM.copyWith(color: context.mood.accentStrong),
            ),
          ),
        ),
      ),
    );
  }
}

class AuthSwitchRow extends StatelessWidget {
  const AuthSwitchRow({
    super.key,
    required this.question,
    required this.action,
    required this.onTap,
  });

  final String question;
  final String action;
  final VoidCallback onTap;

  static const double _slack = (kMinTapTarget - 20) / 2;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 6,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: _slack),
          child: Text(
            question,
            textAlign: TextAlign.center,
            style: AppText.bodyM.copyWith(color: context.colors.textSecondary),
          ),
        ),
        AuthTextLink(
          label: action,
          onTap: onTap,
          top: _slack,
          bottom: _slack + 2,
        ),
      ],
    );
  }
}

class AuthNote extends StatelessWidget {
  const AuthNote({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: BorderRadius.circular(RadiusTokens.md),
      ),
      child: Row(
        children: [
          AppIcon(
            AppIcons.cloudCheck,
            size: 22,
            color: context.mood.accentStrong,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: AppText.caption.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
