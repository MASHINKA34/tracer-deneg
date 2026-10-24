import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/core/router.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/session/session_providers.dart';
import 'package:milionchik/data/session/session_state.dart';
import 'package:milionchik/features/budgets/budget_invite.dart';
import 'package:milionchik/features/budgets/budget_screen.dart';
import 'package:milionchik/features/budgets/budget_screen_view.dart';
import 'package:milionchik/l10n/app_localizations.dart';
import 'package:milionchik/ui/theme/app_theme.dart';
import 'package:shared/shared.dart';

import '../../features/budgets/budget_screen_fixture.dart';
import '../../features/profile/profile_fixture.dart';
import '../../support/app_scope.dart';
import '../../support/golden.dart';
import '../../support/test_fonts.dart';

const String _code = 'MLN-48K2';

Future<void> _pump(
  WidgetTester tester, {
  required bool owner,
  required Brightness brightness,
  required double width,
  required double scale,
  bool code = true,
}) async {
  await loadTestFonts();
  final db = openTestDatabase();
  await tester.runAsync(() => BudgetScreenFixture.seed(db, owner: owner));
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

  final router = buildRouter(initialLocation: AppRoutes.budgetOf(familyId));
  addTearDown(router.dispose);
  final base = AppTheme.build(brightness, Mood.autumn);
  final container = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      clockProvider.overrideWithValue(Clock(now: () => testNow)),
      sessionProvider.overrideWithBuild(
        (ref, _) => const SessionActive(profileUser),
      ),
    ],
  );
  addTearDown(container.dispose);
  if (code) {
    container
        .read(budgetInvitesProvider.notifier)
        .remember(
          familyId,
          BudgetInvite(code: _code, expiresAt: inviteExpiry()),
        );
  }

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
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
  expect(find.byType(BudgetScreen), findsOneWidget);
}

Future<void> _scrollToEnd(WidgetTester tester) async {
  final scrollable = tester.state<ScrollableState>(
    find.byType(Scrollable).first,
  );
  scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
  await tester.pumpAndSettle();
  await settleAssets(tester);
}

String _name(Brightness brightness, double width, double scale) =>
    '${brightness.name}_${width.toInt()}'
    '${scale == 1 ? '' : '_x${scale.toInt()}'}';

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  for (final owner in const [true, false]) {
    final role = owner ? 'owner' : 'member';
    for (final brightness in Brightness.values) {
      for (final width in const [360.0, 320.0]) {
        for (final scale in const [1.0, 2.0]) {
          final name = '${role}_${_name(brightness, width, scale)}';
          testWidgets(
            'экран бюджета «Семья», ${owner ? 'создатель' : 'участник'} '
            '$name (Figma 13:1135)',
            (tester) async {
              await _pump(
                tester,
                owner: owner,
                brightness: brightness,
                width: width,
                scale: scale,
              );

              expect(find.text('🏠 Семья'), findsOneWidget);
              expect(find.text(_code), owner ? findsOneWidget : findsNothing);
              expect(tester.takeException(), isNull);
              await expectGolden(tester, 'budget_screen', name);
            },
          );

          if (scale != 1) {
            testWidgets('экран бюджета $name, прокручен до конца', (
              tester,
            ) async {
              await _pump(
                tester,
                owner: owner,
                brightness: brightness,
                width: width,
                scale: scale,
              );
              await _scrollToEnd(tester);

              expect(tester.takeException(), isNull);
              await expectGolden(tester, 'budget_screen', '${name}_end');
            });
          }

          if (owner && scale != 1) {
            testWidgets('экран бюджета $name, прокручен до кода', (
              tester,
            ) async {
              await _pump(
                tester,
                owner: owner,
                brightness: brightness,
                width: width,
                scale: scale,
              );
              await Scrollable.ensureVisible(
                tester.element(find.byType(BudgetInviteCard)),
              );
              await tester.pumpAndSettle();
              await settleAssets(tester);

              expect(tester.takeException(), isNull);
              await expectGolden(tester, 'budget_screen', '${name}_invite');
            });
          }
        }
      }
    }
  }

  for (final brightness in Brightness.values) {
    final name = 'owner_no_code_${brightness.name}_360';
    testWidgets('экран бюджета, создатель без действующего кода: «Пригласить» '
        '$name', (tester) async {
      await _pump(
        tester,
        owner: true,
        brightness: brightness,
        width: 360,
        scale: 1,
        code: false,
      );

      expect(find.text('Пригласить'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectGolden(tester, 'budget_screen', name);
    });
  }
}
