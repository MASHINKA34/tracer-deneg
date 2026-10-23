import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/core/router.dart';
import 'package:milionchik/data/api/api_client.dart';
import 'package:milionchik/data/api/api_config.dart';
import 'package:milionchik/data/api/api_providers.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/session/device_name.dart';
import 'package:milionchik/data/session/session_providers.dart';
import 'package:milionchik/features/auth/recovery_code_state.dart';
import 'package:milionchik/l10n/app_localizations.dart';
import 'package:milionchik/ui/components/text_field.dart';
import 'package:milionchik/ui/theme/app_theme.dart';
import 'package:shared/shared.dart';

import '../../data/api/fake_api_adapter.dart';
import '../../data/session/fake_secure_values.dart';
import '../../support/app_scope.dart';
import '../../support/golden.dart';
import '../../support/test_fonts.dart';

const String _code = 'K7QM-4XPA-9TRB';

FakeReply _noServer(FakeCall call) =>
    throw StateError('no request expected, got ${call.method} ${call.path}');

Future<void> _pump(
  WidgetTester tester, {
  required Brightness brightness,
  required double width,
  required double scale,
  required String location,
}) async {
  await loadTestFonts();
  final db = openTestDatabase();
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

  final router = buildRouter(initialLocation: location);
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
            newRequestId: () => 'ridrecoverygold1',
          ),
        ),
        pendingRecoveryCodeProvider.overrideWithBuild(
          (ref, _) => const PendingRecoveryCode(
            code: _code,
            reason: RecoveryCodeReason.register,
          ),
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

Future<void> _focus(WidgetTester tester, String label) async {
  final input = _input(label);
  await tester.ensureVisible(input);
  await tester.pumpAndSettle();
  await tester.showKeyboard(input);
  await tester.pumpAndSettle();
}

Future<void> _scrollTo(WidgetTester tester, {required bool end}) async {
  final scrollable = tester.state<ScrollableState>(
    find.byType(Scrollable).first,
  );
  scrollable.position.jumpTo(end ? scrollable.position.maxScrollExtent : 0);
  await tester.pumpAndSettle();
  await settleAssets(tester);
}

Future<void> _checkSaved(WidgetTester tester) async {
  final row = find.text('Я сохранил код в надёжном месте');
  await tester.ensureVisible(row);
  await tester.pumpAndSettle();
  await tester.tap(row);
  await tester.pumpAndSettle();
}

Future<void> _fillForgot(WidgetTester tester) async {
  await _type(tester, 'Логин', 'anya_m');
  await _type(tester, 'Код восстановления', _code);
  await _type(tester, 'Новый пароль', '12345678');
  await _focus(tester, 'Новый пароль');
}

String _name(Brightness brightness, double width, double scale) =>
    '${brightness.name}_${width.toInt()}'
    '${scale == 1 ? '' : '_x${scale.toInt()}'}';

void main() {
  for (final brightness in Brightness.values) {
    for (final width in const [360.0, 320.0]) {
      for (final scale in const [1.0, 2.0]) {
        final name = _name(brightness, width, scale);

        testWidgets('«Код восстановления» с отмеченным чекбоксом $name (Figma '
            '42:4019)', (tester) async {
          await _pump(
            tester,
            brightness: brightness,
            width: width,
            scale: scale,
            location: AppRoutes.recoveryCode,
          );
          await _checkSaved(tester);
          await _scrollTo(tester, end: false);
          expect(tester.takeException(), isNull);

          await expectGolden(tester, 'auth', 'recovery_code_$name');
        });

        testWidgets('«Забыл пароль» с новым паролем в фокусе $name (Figma '
            '42:4074)', (tester) async {
          await _pump(
            tester,
            brightness: brightness,
            width: width,
            scale: scale,
            location: AppRoutes.forgotPassword,
          );
          await _fillForgot(tester);
          await _scrollTo(tester, end: false);
          expect(tester.takeException(), isNull);

          await expectGolden(tester, 'auth', 'forgot_$name');
        });

        if (scale != 1) {
          testWidgets('«Забыл пароль» $name прокручен до конца', (
            tester,
          ) async {
            await _pump(
              tester,
              brightness: brightness,
              width: width,
              scale: scale,
              location: AppRoutes.forgotPassword,
            );
            await _fillForgot(tester);
            await _scrollTo(tester, end: true);
            expect(tester.takeException(), isNull);

            await expectGolden(tester, 'auth', 'forgot_${name}_end');
          });

          testWidgets('«Код восстановления» $name прокручен до конца', (
            tester,
          ) async {
            await _pump(
              tester,
              brightness: brightness,
              width: width,
              scale: scale,
              location: AppRoutes.recoveryCode,
            );
            await _checkSaved(tester);
            await _scrollTo(tester, end: true);
            expect(tester.takeException(), isNull);

            await expectGolden(tester, 'auth', 'recovery_code_${name}_end');
          });
        }
      }
    }
  }
}
