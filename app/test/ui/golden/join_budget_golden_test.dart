import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/core/router.dart';
import 'package:milionchik/data/api/api_exception.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/features/budgets/budget_join_service.dart';
import 'package:milionchik/features/budgets/join_budget_screen.dart';
import 'package:milionchik/l10n/app_localizations.dart';
import 'package:milionchik/ui/components/button.dart';
import 'package:milionchik/ui/theme/app_theme.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';
import '../../support/golden.dart';
import '../../support/test_fonts.dart';

final class _NotFoundJoin extends BudgetJoinService {
  _NotFoundJoin(super.ref);

  @override
  Future<BudgetJoinOutcome> join({required String code}) async =>
      BudgetJoinFailed(
        stage: BudgetJoinStage.request,
        requestId: 'ridgolden0000001',
        error: ApiErrorResponse(
          method: 'POST',
          path: '/api/v1/invites/join',
          requestId: 'ridgolden0000001',
          statusCode: 404,
          error: ApiError.of(
            ApiErrorCode.inviteNotFound,
            'Код не найден или истёк',
          ),
        ),
      );
}

Future<void> _pump(
  WidgetTester tester, {
  required Brightness brightness,
  required double width,
  required double scale,
}) async {
  await loadTestFonts();
  final db = openTestDatabase();
  debugDisableShadows = false;
  EditableText.debugDeterministicCursor = true;
  addTearDown(() => EditableText.debugDeterministicCursor = false);
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

  final router = buildRouter(initialLocation: AppRoutes.joinBudget);
  addTearDown(router.dispose);
  final base = AppTheme.build(brightness, Mood.autumn);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(Clock(now: () => testNow)),
        budgetJoinServiceProvider.overrideWith(_NotFoundJoin.new),
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
  await tester.pumpAndSettle();
  await settleAssets(tester);
  expect(find.byType(JoinBudgetScreen), findsOneWidget);
}

Future<void> _typeCode(WidgetTester tester, String code) async {
  await tester.tap(find.byType(TextField));
  await tester.pump();
  await tester.enterText(find.byType(TextField), code);
  await tester.pumpAndSettle();
}

Future<void> _join(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(AppButton, 'Присоединиться'));
  await tester.pumpAndSettle();
  await settleAssets(tester);
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
  for (final brightness in Brightness.values) {
    for (final width in const [360.0, 320.0]) {
      for (final scale in const [1.0, 2.0]) {
        final name = _name(brightness, width, scale);
        testWidgets('«Вход по коду» MLN-48K2, поле в фокусе $name '
            '(Figma 45:5099)', (tester) async {
          await _pump(
            tester,
            brightness: brightness,
            width: width,
            scale: scale,
          );
          await _typeCode(tester, 'mln48k2');

          expect(find.text('MLN-48K2'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await expectGolden(tester, 'join_budget', 'screen_$name');
        });

        if (scale != 1) {
          testWidgets('«Вход по коду» $name, прокручен до подсказки', (
            tester,
          ) async {
            await _pump(
              tester,
              brightness: brightness,
              width: width,
              scale: scale,
            );
            await _typeCode(tester, 'mln48k2');
            FocusManager.instance.primaryFocus?.unfocus();
            await tester.pumpAndSettle();
            await _scrollToEnd(tester);

            expect(tester.takeException(), isNull);
            await expectGolden(tester, 'join_budget', 'screen_${name}_end');
          });
        }

        testWidgets('«Вход по коду» MLN-48K9, код не найден $name '
            '(Figma 45:5138)', (tester) async {
          await _pump(
            tester,
            brightness: brightness,
            width: width,
            scale: scale,
          );
          await _typeCode(tester, 'MLN-48K9');
          await _join(tester);

          expect(
            find.text('Код не найден или истёк. Попроси новый.'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await expectGolden(tester, 'join_budget', 'not_found_$name');
        });
      }
    }

    final name = brightness.name;
    testWidgets('«Вход по коду» пустое поле, до ввода $name', (tester) async {
      await _pump(tester, brightness: brightness, width: 360, scale: 1);

      expect(tester.takeException(), isNull);
      await expectGolden(tester, 'join_budget', 'empty_$name');
    });
  }
}
