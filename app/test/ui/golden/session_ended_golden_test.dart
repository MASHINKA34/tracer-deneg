import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/core/router.dart';
import 'package:milionchik/data/api/api_client.dart';
import 'package:milionchik/data/api/api_config.dart';
import 'package:milionchik/data/api/api_exception.dart';
import 'package:milionchik/data/api/api_providers.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/session/device_name.dart';
import 'package:milionchik/data/session/session_providers.dart';
import 'package:milionchik/data/session/session_state.dart';
import 'package:milionchik/l10n/app_localizations.dart';
import 'package:milionchik/ui/components/button.dart';
import 'package:milionchik/ui/components/dialog.dart';
import 'package:milionchik/ui/components/text_field.dart';
import 'package:milionchik/ui/theme/app_theme.dart';
import 'package:shared/shared.dart';

import '../../data/api/fake_api_adapter.dart';
import '../../data/session/fake_secure_values.dart';
import '../../features/auth/session_expired_fixture.dart'
    show testUnmounting;
import '../../features/profile/profile_fixture.dart';
import '../../features/profile/sign_out_fixture.dart';
import '../../support/app_scope.dart';
import '../../support/golden.dart';
import '../../support/test_fonts.dart';

FakeReply _noServer(FakeCall call) =>
    throw StateError('no request expected, got ${call.method} ${call.path}');

Future<void> _pump(
  WidgetTester tester, {
  required Brightness brightness,
  required double width,
  required double scale,
  Future<void> Function(AppDatabase db)? seed,
}) async {
  await loadTestFonts();
  final db = openTestDatabase();
  if (seed != null) await tester.runAsync(() => seed(db));
  EditableText.debugDeterministicCursor = true;
  addTearDown(() => EditableText.debugDeterministicCursor = false);
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

  final router = buildRouter(initialLocation: AppRoutes.login);
  addTearDown(router.dispose);
  final base = AppTheme.build(brightness, Mood.autumn);
  final config = ApiConfig.resolve(define: '', debugBuild: true);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(Clock(now: () => testNow)),
        secureValuesProvider.overrideWithValue(FakeSecureValues()),
        deviceNameProvider.overrideWithValue('Pixel 7'),
        apiClientProvider.overrideWith(
          (ref) => ApiClient(
            config: config,
            tokens: ref.watch(tokenStoreProvider),
            adapter: FakeApiAdapter(_noServer),
            newRequestId: () => 'ridendedgolden01',
          ),
        ),
        sessionProvider.overrideWithBuild(
          (ref, _) =>
              const SessionEnded(profileUser, SessionEndReason.refreshRejected),
        ),
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
}

Finder _input(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(AppTextField)),
  matching: find.byType(TextField),
);

Future<void> _type(WidgetTester tester, String label, String text) async {
  await tester.enterText(_input(label), text);
  await tester.pump();
}

Future<void> _top(WidgetTester tester) async {
  tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position
      .jumpTo(0);
  await tester.pumpAndSettle();
  await settleAssets(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }
}

String _name(Brightness brightness, double width, double scale) =>
    '${brightness.name}_${width.toInt()}'
    '${scale == 1 ? '' : '_x${scale.toInt()}'}';

void main() {
  for (final brightness in Brightness.values) {
    for (final width in const [360.0, 320.0]) {
      for (final scale in const [1.0, 2.0]) {
        final name = _name(brightness, width, scale);
        final figma = brightness == Brightness.light ? '14:1120' : '15:1561';

        testUnmounting('«Вход» после истёкшей сессии: «Сессия закончилась, '
            'войди снова» вместо подзаголовка $name (Figma $figma)', (
          tester,
        ) async {
          await _pump(
            tester,
            brightness: brightness,
            width: width,
            scale: scale,
          );
          await _type(tester, 'Логин', 'anya_m');
          await _type(tester, 'Пароль', '12345678');
          await tester.showKeyboard(_input('Пароль'));
          await tester.pumpAndSettle();
          await _top(tester);
          expect(find.text('Сессия закончилась, войди снова'), findsOneWidget);
          expect(tester.takeException(), isNull);

          await expectGolden(tester, 'session_ended', 'login_$name');
        });

        testUnmounting('вход другим логином при 3 несохранённых тратах: '
            'диалог $name (по образцу Figma 42:4321)', (tester) async {
          await _pump(
            tester,
            brightness: brightness,
            width: width,
            scale: scale,
            seed: (db) async {
              await ProfileFixture.mockup(db);
              await addUnsyncedExpenses(db, 3);
            },
          );
          await _type(tester, 'Логин', 'boris_k');
          await _type(tester, 'Пароль', '12345678');
          final signIn = find.widgetWithText(AppButton, 'Войти');
          await tester.ensureVisible(signIn);
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            await tester.tap(signIn);
            await Future<void>.delayed(const Duration(milliseconds: 100));
          });
          await _settle(tester);
          await _top(tester);
          expect(find.byType(AppDialog), findsOneWidget);
          expect(find.text('Войти в другой аккаунт?'), findsOneWidget);
          expect(
            find.text(
              'Несохранённые траты прошлого аккаунта (3) будут удалены. '
              'Чтобы их сохранить, войди прежним логином.',
            ),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);

          await expectGolden(tester, 'session_ended', 'account_switch_$name');
        });
      }
    }
  }
}
