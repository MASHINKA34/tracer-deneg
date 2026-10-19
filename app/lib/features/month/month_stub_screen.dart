import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Заглушка главного экрана: название приложения по центру.
/// Заменяется настоящей главной на этапе 05.
class MonthStubScreen extends StatelessWidget {
  const MonthStubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Text(
            AppLocalizations.of(context).appTitle,
            style: Theme.of(context).textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
