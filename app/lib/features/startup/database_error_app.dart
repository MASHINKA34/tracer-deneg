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

class DatabaseErrorApp extends StatelessWidget {
  const DatabaseErrorApp({super.key, this.clock = const Clock()});

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
      home: const DatabaseErrorScreen(),
    );
  }
}

class DatabaseErrorScreen extends StatelessWidget {
  const DatabaseErrorScreen({super.key});

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
                  l10n.databaseErrorTitle,
                  style: AppText.titleL.copyWith(color: colors.textPrimary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.databaseErrorMessage,
                  style: AppText.bodyM.copyWith(color: colors.textSecondary),
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
