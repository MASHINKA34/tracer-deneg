import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'core/router.dart';
import 'core/system_ui.dart';
import 'l10n/app_localizations.dart';

/// Корневой виджет: русская локаль, светлая/тёмная тема как в системе
/// (свои темы — этап 03), прозрачные системные панели, go_router.
class MilionchikApp extends StatefulWidget {
  const MilionchikApp({super.key});

  @override
  State<MilionchikApp> createState() => _MilionchikAppState();
}

class _MilionchikAppState extends State<MilionchikApp> {
  late final GoRouter _router = buildRouter();

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      locale: const Locale('ru'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: ThemeData(brightness: Brightness.light),
      darkTheme: ThemeData(brightness: Brightness.dark),
      routerConfig: _router,
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: systemUiStyleFor(Theme.of(context).brightness),
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
