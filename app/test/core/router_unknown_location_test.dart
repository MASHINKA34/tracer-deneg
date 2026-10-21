import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/router.dart';
import 'package:milionchik/features/month/month_screen.dart';
import 'package:milionchik/l10n/app_localizations.dart';
import 'package:milionchik/ui/components/bottom_nav.dart';
import 'package:milionchik/ui/theme/app_theme.dart';
import 'package:shared/shared.dart' show Mood;

import '../support/app_scope.dart';

void main() {
  testWidgets(
    'неизвестный адрес — предупреждение без query и вкладка «Месяц»',
    (tester) async {
      final records = <LogRecord>[];
      Logger.root.level = Level.ALL;
      final sub = Logger.root.onRecord.listen(records.add);
      addTearDown(sub.cancel);
      final router = buildRouter(initialLocation: '/join?code=MLN-7Q2K');
      addTearDown(router.dispose);

      await tester.pumpWidget(
        withDatabase(
          openTestDatabase(),
          MaterialApp.router(
            theme: AppTheme.build(Brightness.light, Mood.autumn),
            locale: const Locale('ru'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MonthScreen), findsOneWidget);
      expect(
        tester.widget<AppBottomNav>(find.byType(AppBottomNav)).active,
        AppNavTab.month,
      );
      expect(router.state.uri.path, AppRoutes.month);
      final warnings = records
          .where((r) => r.loggerName == 'nav' && r.level == Level.WARNING)
          .map((r) => r.message)
          .toList();
      expect(warnings, ['no route for path=/join → opening /month']);
      expect(
        records.map((r) => '${r.message} ${r.error ?? ''}'),
        everyElement(isNot(contains('MLN-7Q2K'))),
      );
    },
  );
}
