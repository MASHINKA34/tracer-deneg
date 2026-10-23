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
import 'package:milionchik/l10n/app_localizations.dart';
import 'package:milionchik/ui/components/button.dart';
import 'package:milionchik/ui/components/text_field.dart';
import 'package:milionchik/ui/theme/app_theme.dart';
import 'package:shared/shared.dart';

import '../../data/api/fake_api_adapter.dart';
import '../../data/session/fake_secure_values.dart';
import '../../support/app_scope.dart';
import '../../support/golden.dart';
import '../../support/test_fonts.dart';

Future<void> _pump(
  WidgetTester tester, {
  required Brightness brightness,
  required double width,
  required double scale,
  required String location,
  required FakeHandler server,
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
            adapter: FakeApiAdapter(server),
            newRequestId: () => 'ridauthgolden001',
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

FakeReply _noServer(FakeCall call) =>
    throw StateError('no request expected, got ${call.method} ${call.path}');

Finder _input(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(AppTextField)),
  matching: find.byType(TextField),
);

Future<void> _type(WidgetTester tester, String label, String text) async {
  await tester.enterText(_input(label), text);
  await tester.pump();
}

Future<void> _tapButton(WidgetTester tester, String label) async {
  final button = find.widgetWithText(AppButton, label);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> _focus(WidgetTester tester, String label) async {
  final input = _input(label);
  await tester.ensureVisible(input);
  await tester.pumpAndSettle();
  await tester.showKeyboard(input);
  await tester.pumpAndSettle();
}

Future<void> _top(WidgetTester tester) async {
  final scrollable = tester.state<ScrollableState>(
    find.byType(Scrollable).first,
  );
  scrollable.position.jumpTo(0);
  await tester.pumpAndSettle();
  await settleAssets(tester);
}

Future<void> _end(WidgetTester tester) async {
  final scrollable = tester.state<ScrollableState>(
    find.byType(Scrollable).first,
  );
  scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
  await tester.pumpAndSettle();
  await settleAssets(tester);
}

Future<void> _login(WidgetTester tester) async {
  await _type(tester, 'Логин', 'anya_m');
  await _type(tester, 'Пароль', '12345678');
  await _focus(tester, 'Пароль');
  await _top(tester);
}

Future<void> _loginError(WidgetTester tester) async {
  await _type(tester, 'Логин', 'anya_m');
  await _type(tester, 'Пароль', '123456');
  await _tapButton(tester, 'Войти');
  await _top(tester);
}

Future<void> _register(WidgetTester tester) async {
  await _type(tester, 'Как тебя зовут', 'Аня');
  await _type(tester, 'Логин', 'anya');
  await _type(tester, 'Пароль', '12345678');
  await _type(tester, 'Повтори пароль', '12345678');
  await _tapButton(tester, 'Создать аккаунт');
  await _focus(tester, 'Повтори пароль');
  await _top(tester);
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

        testWidgets('«Вход» с логином и паролем в фокусе $name (Figma '
            '$figma)', (tester) async {
          await _pump(
            tester,
            brightness: brightness,
            width: width,
            scale: scale,
            location: AppRoutes.login,
            server: _noServer,
          );
          await _login(tester);
          expect(tester.takeException(), isNull);

          await expectGolden(tester, 'auth', 'login_$name');
        });

        testWidgets('«Вход · ошибка» неверный пароль $name (Figma 42:4149)', (
          tester,
        ) async {
          await _pump(
            tester,
            brightness: brightness,
            width: width,
            scale: scale,
            location: AppRoutes.login,
            server: (call) => FakeReply.error(
              401,
              'bad_credentials',
              'Неверный логин или пароль',
            ),
          );
          await _loginError(tester);
          expect(tester.takeException(), isNull);

          await expectGolden(tester, 'auth', 'login_error_$name');
        });

        testWidgets('«Регистрация» логин занят $name (Figma 14:1295)', (
          tester,
        ) async {
          await _pump(
            tester,
            brightness: brightness,
            width: width,
            scale: scale,
            location: AppRoutes.register,
            server: (call) =>
                FakeReply.error(409, 'login_taken', 'Такой логин уже занят'),
          );
          await _register(tester);
          expect(tester.takeException(), isNull);

          await expectGolden(tester, 'auth', 'register_taken_$name');
        });

        if (scale != 1) {
          testWidgets('«Вход · ошибка» $name прокручен до конца', (
            tester,
          ) async {
            await _pump(
              tester,
              brightness: brightness,
              width: width,
              scale: scale,
              location: AppRoutes.login,
              server: (call) => FakeReply.error(401, 'bad_credentials'),
            );
            await _loginError(tester);
            await _end(tester);
            expect(tester.takeException(), isNull);

            await expectGolden(tester, 'auth', 'login_error_${name}_end');
          });

          testWidgets('«Регистрация» логин занят $name прокручена до конца', (
            tester,
          ) async {
            await _pump(
              tester,
              brightness: brightness,
              width: width,
              scale: scale,
              location: AppRoutes.register,
              server: (call) => FakeReply.error(409, 'login_taken'),
            );
            await _register(tester);
            await _end(tester);
            expect(tester.takeException(), isNull);

            await expectGolden(tester, 'auth', 'register_taken_${name}_end');
          });
        }
      }
    }
  }
}
