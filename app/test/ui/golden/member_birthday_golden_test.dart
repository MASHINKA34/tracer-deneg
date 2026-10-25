import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/core/router.dart';
import 'package:milionchik/data/holiday_settings.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/session/session_providers.dart';
import 'package:milionchik/data/session/session_state.dart';
import 'package:milionchik/features/budgets/budget_screen.dart';
import 'package:milionchik/features/month/month_screen.dart';
import 'package:milionchik/l10n/app_localizations.dart';
import 'package:milionchik/ui/components/holiday_banner.dart';
import 'package:milionchik/ui/theme/app_theme.dart';
import 'package:shared/shared.dart';

import '../../features/holidays/member_birthday_fixture.dart';
import '../../features/profile/profile_fixture.dart';
import '../../support/app_scope.dart';
import '../../support/golden.dart';
import '../../support/test_fonts.dart';

Future<void> _pump(
  WidgetTester tester, {
  required String location,
  required DateTime now,
  required Brightness brightness,
  required double width,
  required double scale,
  MonthDay? dima,
  MonthDay? mama,
}) async {
  await loadTestFonts();
  final db = openTestDatabase();
  await tester.runAsync(
    () => seedMemberBirthdays(db, dima: dima, mama: mama, expenses: true),
  );
  debugDisableShadows = false;
  tester.view
    ..devicePixelRatio = goldenPixelRatio
    ..physicalSize = Size(width, 800) * goldenPixelRatio
    ..viewPadding = const FakeViewPadding(top: 32)
    ..padding = const FakeViewPadding(top: 32);
  addTearDown(tester.view.reset);
  tester.platformDispatcher
    ..textScaleFactorTestValue = scale
    ..accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
      disableAnimations: true,
    );
  addTearDown(tester.platformDispatcher.clearAllTestValues);

  final router = buildRouter(initialLocation: location);
  addTearDown(router.dispose);
  final mood = moodOn(LocalDate.fromDateTime(now), const HolidaySettings());
  final base = AppTheme.build(brightness, mood);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(Clock(now: () => now)),
        sessionProvider.overrideWithBuild(
          (ref, _) => const SessionActive(profileUser),
        ),
        holidaySettingsProvider.overrideWithValue(const HolidaySettings()),
      ],
      child: RepaintBoundary(
        key: goldenKey,
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: base.copyWith(
            textTheme: base.textTheme.apply(
              fontFamilyFallback: const [testEmojiFamily],
            ),
          ),
          locale: const Locale('ru'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          routerConfig: router,
        ),
      ),
    ),
  );
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }
  await settleAssets(tester);
}

String _name(
  String screen,
  Brightness brightness,
  double width,
  double scale,
) =>
    '${screen}_${brightness.name}_${width.toInt()}'
    '${scale == 1 ? '' : '_x${scale.toInt()}'}';

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  for (final brightness in Brightness.values) {
    for (final width in const [360.0, 320.0]) {
      for (final scale in const [1.0, 2.0]) {
        final month = _name('month', brightness, width, scale);
        testWidgets('главная «Семья»: плашка «Участник», Дима через 3 дня '
            '$month (Figma 35:11612)', (tester) async {
          await _pump(
            tester,
            location: AppRoutes.month,
            now: mockupNow,
            brightness: brightness,
            width: width,
            scale: scale,
            dima: dimaMockupBirthday,
          );

          expect(find.byType(MonthScreen), findsOneWidget);
          expect(
            find.text('🎂 Дима — день рождения через 3 дня'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await expectGolden(tester, 'member_birthday', month);
        });

        final budget = _name('budget', brightness, width, scale);
        testWidgets('экран бюджета «Семья»: «Дима 🎂» в списке участников '
            '$budget (Figma 35:11612)', (tester) async {
          await _pump(
            tester,
            location: AppRoutes.budgetOf(familyId),
            now: mockupNow,
            brightness: brightness,
            width: width,
            scale: scale,
            dima: dimaMockupBirthday,
          );

          expect(find.byType(BudgetScreen), findsOneWidget);
          expect(find.text('Дима 🎂'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await expectGolden(tester, 'member_birthday', budget);
        });
      }
    }
  }

  for (final brightness in Brightness.values) {
    final today = _name('month_today_two', brightness, 360, 1);
    testWidgets('главная «Семья»: две плашки - сегодня у Мамы, через 3 дня у '
        'Димы $today', (tester) async {
      await _pump(
        tester,
        location: AppRoutes.month,
        now: mockupNow,
        brightness: brightness,
        width: 360,
        scale: 1,
        dima: dimaMockupBirthday,
        mama: MonthDay(11, 29),
      );

      expect(find.text('🎂 Сегодня день рождения: Мама'), findsOneWidget);
      expect(find.text('🎂 Дима — день рождения через 3 дня'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectGolden(tester, 'member_birthday', today);
    });

    final halloween = _name('month_under_halloween', brightness, 360, 1);
    testWidgets('главная «Семья»: плашка «Участник» под плашкой Хеллоуина '
        '$halloween', (tester) async {
      await _pump(
        tester,
        location: AppRoutes.month,
        now: DateTime(2026, 10, 28, 18, 40),
        brightness: brightness,
        width: 360,
        scale: 1,
        dima: MonthDay(10, 30),
      );

      expect(
        find.byWidgetPredicate(
          (w) => w is HolidayBanner && w.type == HolidayBannerType.countdown,
        ),
        findsOneWidget,
      );
      expect(find.text('🎂 Дима — день рождения через 2 дня'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectGolden(tester, 'member_birthday', halloween);
    });
  }
}
