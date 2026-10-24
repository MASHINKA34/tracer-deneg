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
import 'package:milionchik/data/session/session_state.dart';
import 'package:milionchik/features/profile/delete_account_screen.dart';
import 'package:milionchik/l10n/app_localizations.dart';
import 'package:milionchik/ui/components/text_field.dart';
import 'package:milionchik/ui/theme/app_theme.dart';
import 'package:shared/shared.dart';

import '../../data/api/fake_api_adapter.dart';
import '../../data/session/fake_secure_values.dart';
import '../../features/profile/profile_fixture.dart';
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

  final router = buildRouter(initialLocation: AppRoutes.deleteAccount);
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
            newRequestId: () => 'riddeletegold001',
          ),
        ),
        sessionProvider.overrideWithBuild(
          (ref, _) => const SessionActive(profileUser),
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
  await tester.enterText(
    find.descendant(
      of: find.byType(AppTextField),
      matching: find.byType(TextField),
    ),
    'parol-12',
  );
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

String _name(Brightness brightness, double width, double scale) =>
    '${brightness.name}_${width.toInt()}'
    '${scale == 1 ? '' : '_x${scale.toInt()}'}';

void main() {
  for (final brightness in Brightness.values) {
    for (final width in const [360.0, 320.0]) {
      for (final scale in const [1.0, 2.0]) {
        final name = _name(brightness, width, scale);

        testWidgets('«Удалить аккаунт» с паролем в фокусе $name (Figma '
            '42:4394)', (tester) async {
          await _pump(
            tester,
            brightness: brightness,
            width: width,
            scale: scale,
          );
          expect(find.byType(DeleteAccountScreen), findsOneWidget);
          await _scrollTo(tester, end: false);
          expect(tester.takeException(), isNull);

          await expectGolden(tester, 'delete_account', 'delete_account_$name');
        });

        if (scale != 1) {
          testWidgets('«Удалить аккаунт» $name прокручен до конца', (
            tester,
          ) async {
            await _pump(
              tester,
              brightness: brightness,
              width: width,
              scale: scale,
            );
            await _scrollTo(tester, end: true);
            expect(tester.takeException(), isNull);

            await expectGolden(
              tester,
              'delete_account',
              'delete_account_${name}_end',
            );
          });
        }
      }
    }
  }
}
