import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/components/logo.dart';
import '../../ui/theme/app_text.dart';
import '../../ui/theme/app_theme.dart';

final _log = Logger('month');

/// Заглушка главного экрана: логотип и название по центру. В debug-сборке
/// долгий тап по логотипу открывает каталог компонентов. Заменяется
/// настоящей главной на этапе 05.
class MonthStubScreen extends StatelessWidget {
  const MonthStubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final title = AppLocalizations.of(context).appTitle;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onLongPress: kDebugMode
                    ? () {
                        _log.info('long press on logo → debug catalog');
                        context.pushNamed('catalog');
                      }
                    : null,
                child: AppLogo(semanticLabel: title),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: AppText.displayM.copyWith(
                  color: context.colors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
