import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared/shared.dart';

import '../../core/clock.dart';
import '../../core/logging/navigation_logger.dart';
import '../../core/system_ui.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/components/logo.dart';
import '../../ui/theme/app_text.dart';
import '../../ui/theme/app_theme.dart';

class ApiConfigErrorApp extends StatelessWidget {
  const ApiConfigErrorApp({
    super.key,
    required this.details,
    this.clock = const Clock(),
  });

  final String details;
  final Clock clock;

  @override
  Widget build(BuildContext context) {
    final mood = moodOn(clock.today(), const HolidaySettings());
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      locale: const Locale('ru'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: AppTheme.build(Brightness.light, mood),
      darkTheme: AppTheme.build(Brightness.dark, mood),
      navigatorObservers: [NavigationLogger()],
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: systemUiStyleFor(Theme.of(context).brightness),
        child: child ?? const SizedBox.shrink(),
      ),
      home: ApiConfigErrorScreen(details: details),
    );
  }
}

class ApiConfigErrorScreen extends StatelessWidget {
  const ApiConfigErrorScreen({super.key, required this.details});

  final String details;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppLogo(semanticLabel: l10n.appTitle),
                const SizedBox(height: 24),
                Text(
                  l10n.apiConfigErrorTitle,
                  style: AppText.titleL.copyWith(color: colors.textPrimary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.apiConfigErrorMessage,
                  style: AppText.bodyM.copyWith(color: colors.textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  details,
                  style: AppText.caption.copyWith(color: colors.textTertiary),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
