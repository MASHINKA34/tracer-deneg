import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/app.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/data/api/api_client.dart';
import 'package:milionchik/data/api/api_config.dart';
import 'package:milionchik/data/api/api_providers.dart';
import 'package:milionchik/data/api/token_store.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/session/device_name.dart';
import 'package:milionchik/data/session/session.dart';
import 'package:milionchik/data/session/session_providers.dart';
import 'package:milionchik/data/session/session_state.dart';
import 'package:milionchik/data/session/session_store.dart';
import 'package:milionchik/ui/components/bottom_nav.dart';
import 'package:milionchik/ui/components/list_row.dart';
import 'package:milionchik/ui/components/text_field.dart';
import 'package:shared/shared.dart';

import '../../data/api/fake_api_adapter.dart';
import '../../data/session/fake_secure_values.dart';
import '../../support/app_scope.dart';
import 'profile_fixture.dart';

FakeReply noServer(FakeCall call) =>
    throw StateError('no request expected, got ${call.method} ${call.path}');

final class ProfileHarness {
  ProfileHarness._(this.tester, this.db, this.adapter, this.logs);

  static const AuthTokens tokens = AuthTokens(
    accessToken: 'ACCESS-profile-quebec-romeo',
    refreshToken: 'REFRESH-profile-sierra-tango',
  );

  final WidgetTester tester;
  final AppDatabase db;
  final FakeApiAdapter adapter;
  final LogCapture logs;

  ProviderContainer get container =>
      ProviderScope.containerOf(tester.element(find.byType(MilionchikApp)));

  static Future<ProfileHarness> start(
    WidgetTester tester, {
    FakeHandler server = noServer,
    SessionUser? user = profileUser,
    bool seed = true,
    AppDatabase? db,
    Size size = const Size(360, 800),
    double textScale = 1,
    Brightness platformBrightness = Brightness.light,
    List<Override> overrides = const [],
    bool sessionEvents = false,
  }) async {
    final logs = LogCapture();
    addTearDown(logs.dispose);
    final database = db ?? openTestDatabase();
    if (seed) {
      await tester.runAsync(() => ProfileFixture.mockup(database));
    }
    final adapter = FakeApiAdapter(server);
    final values = FakeSecureValues();
    if (user != null) {
      await SessionStore(values).save(Session(user: user, tokens: tokens));
    }
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = size
      ..viewPadding = const FakeViewPadding(top: 32)
      ..padding = const FakeViewPadding(top: 32);
    addTearDown(tester.view.reset);
    tester.platformDispatcher
      ..textScaleFactorTestValue = textScale
      ..platformBrightnessTestValue = platformBrightness;
    addTearDown(tester.platformDispatcher.clearAllTestValues);

    final config = ApiConfig.resolve(define: '', debugBuild: true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          clockProvider.overrideWithValue(Clock(now: () => testNow)),
          secureValuesProvider.overrideWithValue(values),
          deviceNameProvider.overrideWithValue('Pixel 7'),
          apiClientProvider.overrideWith((ref) {
            final client = ApiClient(
              config: config,
              tokens: ref.watch(tokenStoreProvider),
              adapter: adapter,
              newRequestId: () => 'ridprofile000001',
            );
            if (sessionEvents) listenSessionExpired(ref, client);
            return client;
          }),
          if (user != null)
            sessionProvider.overrideWithBuild((ref, _) => SessionActive(user)),
          ...overrides,
        ],
        child: MilionchikApp(today: LocalDate.fromDateTime(testNow)),
      ),
    );
    final h = ProfileHarness._(tester, database, adapter, logs);
    await h.settle();
    return h;
  }

  Future<void> settle() async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
    }
  }

  Future<void> enter(String label, String text) async {
    await tester.enterText(input(label), text);
    await tester.pump();
  }

  Future<void> openProfile() async {
    await tester.tap(
      find.descendant(
        of: find.byType(AppBottomNav),
        matching: find.text('Профиль'),
      ),
    );
    await settle();
  }

  Finder row(String title) => find.widgetWithText(ListRow, title);

  String? valueOf(String title) => tester.widget<ListRow>(row(title)).value;

  Future<void> tap(Finder target) async {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await settle();
  }

  Finder field(String label) =>
      find.ancestor(of: find.text(label), matching: find.byType(AppTextField));

  Finder input(String label) =>
      find.descendant(of: field(label), matching: find.byType(TextField));

  String? errorUnder(String label) =>
      tester.widget<AppTextField>(field(label)).errorText;

  ThemeMode get appThemeMode =>
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode!;

  Brightness get shownBrightness =>
      Theme.of(tester.element(find.byType(Scaffold).last)).brightness;

  List<String> linesOf(String logger, [Level from = Level.ALL]) =>
      logs.linesOf(logger, from);
}
